//
//  STPaywallListViewController.swift
//  STPaywallUIKit
//

import Combine
import STPaywallCore
import SnapKit
import StoreKit
import UIKit

open class STPaywallListViewController: UIViewController {
    deinit { }

    // MARK: - UI Components

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = STPaywallColors.background
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 62, bottom: 0, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(STPaywallListCell.self, forCellReuseIdentifier: STPaywallListCell.stIdentifier)
        tableView.register(STPaywallListHeaderView.self, forHeaderFooterViewReuseIdentifier: STPaywallListHeaderView.stIdentifier)
        tableView.keyboardDismissMode = .onDrag
        return tableView
    }()

    // MARK: - Properties

    public let configuration: STPaywallConfiguration
    private var subscriptionItems: [SubscriptionItem] = [.subscriptionInfo, .restore, .manageSubscription]
    private var cachedAdditionalSections: [STPaywallSection] = []
    private var cancellables = Set<AnyCancellable>()
    private var adminTapView: UIView?
    private var adminTapCount: Int = 0

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

        self.serviceBase.statusPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadAllSections()
            }
            .store(in: &self.cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.reloadAllSections()
        self.setupAdminTapArea()
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.adminTapView?.removeFromSuperview()
        self.adminTapView = nil
    }

    @objc private func appDidBecomeActive() {
        guard self.viewIfLoaded?.window != nil else { return }
        self.reloadAllSections()
    }

    // MARK: - Setup Methods

    private func setupUI() {
        self.view.backgroundColor = STPaywallColors.background
        self.navigationItem.title = self.configuration.sceneTitle

        self.view.addSubview(self.tableView)

        self.tableView.snp.makeConstraints { make in
            make.edges.equalTo(self.view.safeAreaLayoutGuide)
        }
    }

    // MARK: - Open Override Points

    /// 프로젝트별 추가 섹션. 구독 관리 섹션 아래에 순서대로 표시.
    open func additionalSections() -> [STPaywallSection] {
        return []
    }

    /// Detail 화면 생성. 커스텀 Detail VC 사용 시 오버라이드.
    open func makePurchaseDetailViewController() -> UIViewController {
        return STPaywallDetailViewController(configuration: self.configuration)
    }

    /// 토스트 메시지 표시. 기본: no-op. 프로젝트에서 오버라이드.
    open func showToast(_ message: String) {
        // 프로젝트에서 MKToast 등으로 오버라이드
    }

    /// 로딩 표시. 기본: no-op. 프로젝트에서 오버라이드.
    open func showLoading(_ isLoading: Bool) {
        // 프로젝트에서 ProgressView 등으로 오버라이드
    }

    /// 구독 상태 텍스트. 기본: 프리미엄이면 "구독 중".
    open func subscriptionStatusText() -> String? {
        switch self.serviceBase.currentStatus {
            case .free:
                return nil
            case .freeTrial:
                let days = self.serviceBase.freeTrialRemainingDays
                return "\(I18N.list_status_trial) (\(days)\(I18N.list_status_trial_days_remaining))"
            case .subscribed:
                return I18N.list_status_subscribed
            case .admin:
                return I18N.list_status_admin
        }
    }

    // MARK: - Public Methods

    /// 추가 섹션 데이터를 갱신합니다.
    public func reloadAdditionalSections() {
        self.cachedAdditionalSections = self.additionalSections()
        self.tableView.reloadData()
    }

    // MARK: - Private Methods

    private func reloadAllSections() {
        self.rebuildSubscriptionItems()
        self.cachedAdditionalSections = self.additionalSections()
        self.tableView.reloadData()
    }

    private func rebuildSubscriptionItems() {
        var items: [SubscriptionItem] = [.subscriptionInfo, .restore, .manageSubscription]
        if self.serviceBase.currentStatus == .freeTrial {
            items.append(.terminateFreeTrial)
        }
        self.subscriptionItems = items
    }

    private func confirmTerminateFreeTrial() {
        let alert = UIAlertController(
            title: I18N.list_alert_terminate_title,
            message: I18N.list_alert_terminate_msg,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: I18N.common_cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: I18N.list_action_terminate, style: .destructive, handler: { [weak self] _ in
            guard let self = self else { return }
            self.serviceBase.terminateFreeTrial()
            self.reloadAllSections()
        }))
        self.present(alert, animated: true)
    }

    private func restorePurchase() {
        self.showLoading(true)

        Task {
            do {
                let restored = try await self.serviceBase.restorePurchases()
                await MainActor.run {
                    self.showLoading(false)
                    if restored {
                        self.showToast(I18N.list_msg_restore_success)
                        self.reloadAllSections()
                    }
                    else {
                        self.showToast(I18N.list_msg_restore_failed)
                    }
                }
            }
            catch {
                await MainActor.run {
                    self.showLoading(false)
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    private func openManageSubscription() {
        self.serviceBase.openManageSubscriptions()
    }

    private func presentPurchaseDetail() {
        let detailVC = self.makePurchaseDetailViewController()
        let navController = UINavigationController(rootViewController: detailVC)
        navController.modalPresentationStyle = .fullScreen
        self.present(navController, animated: true, completion: nil)
    }

    // MARK: - Admin

    private func setupAdminTapArea() {
        guard self.adminTapView == nil,
              let navBar = self.navigationController?.navigationBar
        else { return }

        let tapView = UIView()
        tapView.backgroundColor = .clear
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.adminAreaTapped))
        tapView.addGestureRecognizer(tapGesture)
        navBar.addSubview(tapView)
        tapView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(8)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(44)
        }
        self.adminTapView = tapView
    }

    @objc private func adminAreaTapped() {
        self.adminTapCount += 1
        if self.adminTapCount >= 5 {
            self.adminTapCount = 0
            self.showAdminAlert()
        }
    }

    private func showAdminAlert() {
        let alert = UIAlertController(
            title: " ",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: I18N.common_cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: I18N.common_confirm, style: .default, handler: { [weak self] _ in
            guard let self = self else { return }
            guard let code = alert.textFields?.first?.text?.lowercased() else { return }

            // 첫 번째 Alert dismiss 완료 후 verify 수행
            self.dismiss(animated: true, completion: { [weak self] in
                guard let self = self else { return }
                let isAdmin = self.serviceBase.verify(
                    code: code,
                    from: self,
                    completion: { [weak self] in
                        guard let self = self else { return }
                        self.reloadAllSections()
                    }
                )
                if !isAdmin {
                    self.showToast("Invalid Code")
                    self.reloadAllSections()
                }
            })
        }))
        self.present(alert, animated: true)
    }
}

// MARK: - Subscription Items

extension STPaywallListViewController {

    enum SubscriptionItem {
        case subscriptionInfo
        case restore
        case manageSubscription
        case terminateFreeTrial

        var title: String {
            switch self {
                case .subscriptionInfo:
                    return I18N.list_menu_subscription_info
                case .restore:
                    return I18N.list_menu_restore
                case .manageSubscription:
                    return I18N.list_menu_manage_subscription
                case .terminateFreeTrial:
                    return I18N.list_menu_terminate_trial
            }
        }

        var icon: String {
            switch self {
                case .subscriptionInfo:
                    return "creditcard"
                case .restore:
                    return "arrow.clockwise"
                case .manageSubscription:
                    return "gearshape"
                case .terminateFreeTrial:
                    return "xmark.circle"
            }
        }

        var isDestructive: Bool {
            return self == .terminateFreeTrial
        }
    }
}

// MARK: - UITableViewDataSource

extension STPaywallListViewController: UITableViewDataSource {

    public func numberOfSections(in tableView: UITableView) -> Int {
        return 1 + self.cachedAdditionalSections.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return self.subscriptionItems.count
        }
        return self.cachedAdditionalSections[section - 1].items.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.stDequeueCell(type: STPaywallListCell.self, for: indexPath)

        if indexPath.section == 0 {
            let item = self.subscriptionItems[indexPath.row]
            var statusText: String? = nil
            if case .subscriptionInfo = item {
                statusText = self.subscriptionStatusText()
            }
            cell.configure(title: item.title, icon: item.icon, statusText: statusText)
        }
        else {
            let additionalItem = self.cachedAdditionalSections[indexPath.section - 1].items[indexPath.row]
            switch additionalItem.accessory {
                case let .toggle(isOn, onChange):
                    cell.configure(
                        title: additionalItem.title,
                        icon: additionalItem.iconName,
                        isDestructive: additionalItem.isDestructive,
                        hasSwitch: true,
                        isSwitchOn: isOn,
                        isDisabled: !additionalItem.isEnabled
                    )
                    cell.onSwitchChanged = onChange

                case let .label(text):
                    cell.configure(
                        title: additionalItem.title,
                        icon: additionalItem.iconName,
                        isDestructive: additionalItem.isDestructive,
                        statusText: text,
                        isDisabled: !additionalItem.isEnabled
                    )

                case .arrow, .none:
                    cell.configure(
                        title: additionalItem.title,
                        icon: additionalItem.iconName,
                        isDestructive: additionalItem.isDestructive,
                        isDisabled: !additionalItem.isEnabled
                    )
            }
        }

        return cell
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let headerView = tableView.dequeueReusableHeaderFooterView(
            withIdentifier: STPaywallListHeaderView.stIdentifier
        ) as? STPaywallListHeaderView else { return nil }

        if section == 0 {
            headerView.configure(title: I18N.list_section_subscription)
        }
        else {
            let sectionModel = self.cachedAdditionalSections[section - 1]
            headerView.configure(title: sectionModel.headerTitle ?? "")
        }
        return headerView
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 44
    }
}

// MARK: - UITableViewDelegate

extension STPaywallListViewController: UITableViewDelegate {

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            let item = self.subscriptionItems[indexPath.row]
            switch item {
                case .subscriptionInfo:
                    self.presentPurchaseDetail()
                case .restore:
                    self.restorePurchase()
                case .manageSubscription:
                    self.openManageSubscription()
                case .terminateFreeTrial:
                    self.confirmTerminateFreeTrial()
            }
        }
        else {
            let additionalItem = self.cachedAdditionalSections[indexPath.section - 1].items[indexPath.row]
            if case .toggle = additionalItem.accessory {
                return
            }
            additionalItem.action()
        }
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 52
    }
}

// MARK: - STPaywallListHeaderView Identifier

extension STPaywallListHeaderView {
    static var stIdentifier: String {
        return String(describing: self)
    }
}
