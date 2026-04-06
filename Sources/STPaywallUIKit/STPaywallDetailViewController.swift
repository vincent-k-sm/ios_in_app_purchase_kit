//
//  STPaywallDetailViewController.swift
//  STPaywallUIKit
//

import Combine
import SafariServices
import STPaywallCore
import SnapKit
import StoreKit
import UIKit

open class STPaywallDetailViewController: UIViewController {
    deinit { }

    // MARK: - UI Components

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 40, right: 0)
        tableView.keyboardDismissMode = .onDrag
        tableView.stRegisterCell(type: STPaywallDetailHeaderCell.self)
        tableView.stRegisterCell(type: STPaywallDetailFeatureCell.self)
        tableView.stRegisterCell(type: STPaywallDetailProductCell.self)
        tableView.stRegisterCell(type: STPaywallDetailRestoreCell.self)
        tableView.stRegisterCell(type: STPaywallDetailNoticeCell.self)
        tableView.stRegisterCell(type: STPaywallDetailTermsCell.self)
        tableView.stRegisterCell(type: STPaywallDetailSpacingCell.self)
        return tableView
    }()

    // MARK: - Properties

    public let configuration: STPaywallConfiguration
    private var datasource: [STPaywallDetailCellType] = []
    private var storeProducts: [Product] = []
    private var cancellables = Set<AnyCancellable>()

    private var serviceBase: IAPServiceBase {
        return self.configuration.serviceBase
    }

    // MARK: - Initialization

    public init(configuration: STPaywallConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    open override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.loadProducts()

        self.serviceBase.statusPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &self.cancellables)
    }

    // MARK: - Setup Methods

    private func setupUI() {
        self.view.backgroundColor = STPaywallColors.background
        self.navigationItem.title = self.configuration.detailSceneTitle

        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(self.closeButtonTapped)
        )
        closeButton.tintColor = STPaywallColors.textPrimary
        self.navigationItem.leftBarButtonItem = closeButton

        self.view.addSubview(self.tableView)

        self.tableView.snp.makeConstraints { make in
            make.edges.equalTo(self.view.safeAreaLayoutGuide)
        }
    }

    // MARK: - Open Override Points

    /// 토스트 메시지 표시
    open func showToast(_ message: String) { }

    /// 로딩 표시
    open func showLoading(_ isLoading: Bool) { }

    /// 구매 완료 후 호출
    open func didCompletePurchase(productId: String) { }

    /// 복원 완료 후 호출
    open func didCompleteRestore(success: Bool) { }

    // MARK: - Private Methods

    private func loadProducts() {
        self.showLoading(true)

        Task {
            do {
                let productIds = self.serviceBase.products
                    .filter { $0.period != .lifetime }
                    .map { $0.id }

                let products = try await self.fetchProductsWithTimeout(
                    productIds: productIds,
                    timeoutSeconds: 15
                )
                self.storeProducts = products.sorted { $0.price < $1.price }

                let isPurchased = await self.serviceBase.checkPurchaseStatus()

                await MainActor.run {
                    self.showLoading(false)
                    self.buildDatasource(products: self.storeProducts, isPurchased: isPurchased)
                    self.tableView.reloadData()
                }
            }
            catch {
                await MainActor.run {
                    self.showLoading(false)
                    self.showToast(I18N.detail_msg_fetch_failed)
                }
            }
        }
    }

    private func fetchProductsWithTimeout(productIds: [String], timeoutSeconds: UInt64) async throws -> [Product] {
        try await withThrowingTaskGroup(of: [Product].self) { group in
            group.addTask {
                try await Product.products(for: productIds)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw IAPError.timeout
            }
            guard let result = try await group.next() else {
                throw IAPError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private func buildDatasource(products: [Product], isPurchased: Bool) {
        var datasource: [STPaywallDetailCellType] = []

        // Header
        let lowestPriceProduct = products.min(by: { $0.price < $1.price })
        let lowestPrice = lowestPriceProduct?.displayPrice ?? ""
        let headerTitle = String(format: self.configuration.headerTitleFormat, lowestPrice)
        datasource.append(.header(STPaywallDetailHeaderViewModel(
            title: headerTitle,
            subtitle: self.configuration.headerSubtitle,
            emoji: self.configuration.headerEmoji
        )))

        // Features
        datasource.append(.spacing(16))
        for feature in self.configuration.features {
            datasource.append(.feature(STPaywallDetailFeatureViewModel(
                title: feature.title,
                iconName: feature.iconName
            )))
        }

        // Products
        datasource.append(.spacing(32))
        let sortedProducts = products.sorted(by: { $0.price < $1.price })
        for (index, product) in sortedProducts.enumerated() {
            let iapProduct = self.serviceBase.products.first(where: { $0.id == product.id })
            let periodDescription = self.extractPeriodDescription(from: product)
            let pricePerPeriod = self.formatPricePerPeriod(product: product)
            let promotionText = self.extractPromotionText(from: product)

            datasource.append(.product(STPaywallDetailProductViewModel(
                id: product.id,
                title: product.displayName,
                price: product.displayPrice,
                pricePerPeriod: pricePerPeriod,
                periodDescription: periodDescription,
                promotionText: promotionText,
                isPopular: iapProduct?.isPopular ?? false,
                index: index
            )))
        }

        // Restore + Notice + Terms
        datasource.append(.spacing(8))
        datasource.append(.restore)
        datasource.append(.spacing(8))
        datasource.append(.notice)
        datasource.append(.spacing(16))
        datasource.append(.terms)
        datasource.append(.spacing(40))

        self.datasource = datasource
    }

    private func purchaseProduct(_ productId: String) {
        guard let product = self.storeProducts.first(where: { $0.id == productId }) else { return }
        guard !self.serviceBase.isPremium else { return }

        self.showLoading(true)

        Task {
            do {
                let result = try await product.purchase()

                switch result {
                    case let .success(verification):
                        switch verification {
                            case let .verified(transaction):
                                await transaction.finish()
                                self.serviceBase.applySubscribed()
                                self.didCompletePurchase(productId: product.id)

                                await MainActor.run {
                                    self.showLoading(false)
                                    self.showToast(I18N.detail_msg_success)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: { [weak self] in
                                        self?.dismiss(animated: true)
                                    })
                                }

                            case .unverified:
                                await MainActor.run {
                                    self.showLoading(false)
                                    self.showToast(I18N.detail_msg_verification_failed)
                                }
                        }

                    case .pending:
                        await MainActor.run {
                            self.showLoading(false)
                            self.showToast(I18N.detail_msg_pending)
                        }

                    case .userCancelled:
                        await MainActor.run {
                            self.showLoading(false)
                        }

                    @unknown default:
                        await MainActor.run {
                            self.showLoading(false)
                        }
                }
            }
            catch {
                await MainActor.run {
                    self.showLoading(false)
                    self.showToast(I18N.detail_msg_error)
                }
            }
        }
    }

    private func restorePurchase() {
        self.showLoading(true)

        Task {
            do {
                try await AppStore.sync()
                let isPurchased = await self.serviceBase.checkPurchaseStatus()
                self.didCompleteRestore(success: isPurchased)

                await MainActor.run {
                    self.showLoading(false)
                    if isPurchased {
                        self.showToast(I18N.detail_msg_restore_success)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: { [weak self] in
                            self?.dismiss(animated: true)
                        })
                    }
                    else {
                        self.showToast(I18N.detail_msg_restore_failed)
                    }
                }
            }
            catch {
                await MainActor.run {
                    self.showLoading(false)
                    self.showToast(I18N.detail_msg_error)
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func closeButtonTapped() {
        self.dismiss(animated: true, completion: nil)
    }

    private func termsButtonTapped() {
        let alert = UIAlertController(
            title: I18N.detail_terms_action_title,
            message: I18N.detail_terms_action_message,
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: I18N.detail_terms_of_service, style: .default, handler: { [weak self] _ in
            self?.openWebView(url: self?.configuration.termsOfServiceURL ?? "")
        }))

        alert.addAction(UIAlertAction(title: I18N.detail_privacy_policy, style: .default, handler: { [weak self] _ in
            self?.openWebView(url: self?.configuration.privacyPolicyURL ?? "")
        }))

        alert.addAction(UIAlertAction(title: I18N.common_cancel, style: .cancel))

        self.present(alert, animated: true)
    }

    private func openWebView(url: String) {
        guard let url = URL(string: url) else { return }
        let safariVC = SFSafariViewController(url: url)
        safariVC.modalPresentationStyle = .pageSheet
        self.present(safariVC, animated: true, completion: nil)
    }

    // MARK: - Price Helpers

    private func extractPeriodDescription(from product: Product) -> String? {
        guard let subscription = product.subscription else { return nil }

        let unit = subscription.subscriptionPeriod.unit
        let value = subscription.subscriptionPeriod.value

        let periodString: String
        switch unit {
            case .day: periodString = I18N.detail_period_day
            case .week: periodString = I18N.detail_period_week
            case .month: periodString = I18N.detail_period_month
            case .year: periodString = I18N.detail_period_year
            @unknown default: return nil
        }

        if value == 1 {
            return periodString
        }
        else {
            return "\(value) \(periodString)"
        }
    }

    private func formatPricePerPeriod(product: Product) -> String {
        guard let subscription = product.subscription else { return product.displayPrice }

        let unit = subscription.subscriptionPeriod.unit
        let periodString: String
        switch unit {
            case .day: periodString = I18N.detail_period_day
            case .week: periodString = I18N.detail_period_week
            case .month: periodString = I18N.detail_period_month
            case .year: periodString = I18N.detail_period_year
            @unknown default: return product.displayPrice
        }

        return String(format: I18N.detail_price_format, product.displayPrice, periodString)
    }

    private func extractPromotionText(from product: Product) -> String? {
        guard let subscription = product.subscription,
              let introOffer = subscription.introductoryOffer
        else { return nil }

        switch introOffer.paymentMode {
            case .freeTrial:
                let trialPeriod = introOffer.period
                let unit = trialPeriod.unit
                let value = trialPeriod.value

                let periodString: String
                switch unit {
                    case .day: periodString = I18N.detail_period_day
                    case .week: periodString = I18N.detail_period_week
                    case .month: periodString = I18N.detail_period_month
                    case .year: periodString = I18N.detail_period_year
                    @unknown default: return I18N.detail_promotion_free_trial
                }

                if value == 1 {
                    return "\(periodString) \(I18N.detail_promotion_free_trial)"
                }
                else {
                    return "\(value) \(periodString) \(I18N.detail_promotion_free_trial)"
                }

            case .payAsYouGo, .payUpFront:
                return I18N.detail_promotion_introductory

            default:
                return nil
        }
    }
}

// MARK: - UITableViewDataSource

extension STPaywallDetailViewController: UITableViewDataSource {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.datasource.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellType = self.datasource[indexPath.row]

        switch cellType {
            case let .header(viewModel):
                let cell = tableView.stDequeueCell(type: STPaywallDetailHeaderCell.self, for: indexPath)
                cell.configure(with: viewModel)
                return cell

            case let .feature(viewModel):
                let cell = tableView.stDequeueCell(type: STPaywallDetailFeatureCell.self, for: indexPath)
                cell.configure(with: viewModel)
                return cell

            case let .product(viewModel):
                let cell = tableView.stDequeueCell(type: STPaywallDetailProductCell.self, for: indexPath)
                cell.configure(with: viewModel, isPurchased: self.serviceBase.isPremium)
                cell.delegate = self
                return cell

            case .restore:
                let cell = tableView.stDequeueCell(type: STPaywallDetailRestoreCell.self, for: indexPath)
                cell.delegate = self
                return cell

            case .notice:
                let cell = tableView.stDequeueCell(type: STPaywallDetailNoticeCell.self, for: indexPath)
                cell.configure(text: self.configuration.noticeText)
                return cell

            case .terms:
                let cell = tableView.stDequeueCell(type: STPaywallDetailTermsCell.self, for: indexPath)
                cell.delegate = self
                return cell

            case .spacing:
                let cell = tableView.stDequeueCell(type: STPaywallDetailSpacingCell.self, for: indexPath)
                return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension STPaywallDetailViewController: UITableViewDelegate {

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let cellType = self.datasource[indexPath.row]

        switch cellType {
            case .header:
                return UITableView.automaticDimension
            case .feature:
                return 72
            case .product:
                return UITableView.automaticDimension
            case .restore:
                return 50
            case .notice:
                return UITableView.automaticDimension
            case .terms:
                return 44
            case let .spacing(height):
                return height
        }
    }
}

// MARK: - STPaywallDetailCellDelegate

extension STPaywallDetailViewController: STPaywallDetailCellDelegate {

    func detailCellDidTapSubscribe(productId: String) {
        self.purchaseProduct(productId)
    }

    func detailCellDidTapRestore() {
        self.restorePurchase()
    }

    func detailCellDidTapTerms() {
        self.termsButtonTapped()
    }
}
