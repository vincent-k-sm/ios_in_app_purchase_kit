//
//  IAPManager.swift
//  IAPKit
//
//  공통 SDK. configure()로 상품 ID 주입.
//  상태는 lastStatus(PurchaseStatus) 단일 소스.
//  UserDefaults에는 rawValue만 저장/복원.
//

import Combine
import Foundation
import StoreKit
import UIKit

// MARK: - PurchaseStatus

public enum PurchaseStatus: String, CaseIterable {
    case free
    case freeTrial
    case subscribed
    case admin

    public var isPremium: Bool {
        return self != .free
    }

    public var titleString: String {
        switch self {
            case .free:
                return "Free"
            case .freeTrial:
                return "Trial"
            case .subscribed:
                return "Subscribed"
            case .admin:
                return "Admin"
        }
    }
}

// MARK: - IAPConfiguration

// MARK: - IAPManager

final class IAPManager {

    // MARK: - Singleton

    static let shared = IAPManager()

    // MARK: - Admin Backdoor

    static var paywallStatusString: String = ""

    // MARK: - Properties

    private static var productIds: [String] = []
    private static var appGroupIdentifier: String?
    private static var freeTrialKeychainKey: String = ""
    private static var freeTrialDays: Int = 7
    private static let appGroupPurchasedKey = "isPurchased"

    // MARK: - Configure (프로젝트별 래퍼에서 호출)

    static func configure(
        productIds: [String],
        appGroupIdentifier: String? = nil,
        freeTrialKeychainKey: String? = nil,
        freeTrialDays: Int = 7
    ) {
        Self.productIds = productIds
        Self.appGroupIdentifier = appGroupIdentifier
        Self.freeTrialKeychainKey = freeTrialKeychainKey
            ?? "\(Bundle.main.bundleIdentifier ?? "app").freeTrialStart"
        Self.freeTrialDays = freeTrialDays

        // 앱 저장소 → 메모리 (최초 1회)
        let instance = Self.shared
        instance.loadTrialStartDateFromKeychain()
        instance.lastStatus = instance.restoreStatus()
        instance.syncPurchaseStatusToAppGroup()
        instance.startTransactionListener()

        // StoreKit 실시간 검증
        Task { await instance.checkPurchaseStatus() }
    }

    // MARK: - Notifications


    // MARK: - Status (단일 소스)

    private static let statusKey = "IAPManager.lastStatus"

    @Published private(set) var lastStatus: PurchaseStatus = .free

    // MARK: - Free Trial

    /// 메모리 캐시 (앱 시작 시 키체인에서 로드, 이후 메모리에서 관리)
    private var trialStartDate: Date?

    var isInFreeTrial: Bool {
        guard let startDate = self.trialStartDate else { return false }
        return self.elapsedTrialDays(from: startDate) < Self.freeTrialDays
    }

    var freeTrialRemainingDays: Int {
        guard let startDate = self.trialStartDate else { return 0 }
        return max(0, Self.freeTrialDays - self.elapsedTrialDays(from: startDate))
    }

    var hasUsedFreeTrial: Bool {
        return self.trialStartDate != nil
    }

    @discardableResult
    func startFreeTrialIfNeeded() -> Bool {
        guard !self.hasUsedFreeTrial else { return false }
        self.setTrialStartDate(Date())
        self.applyStatus(.freeTrial)
        return true
    }

    func forceStartFreeTrial() {
        self.setTrialStartDate(Date())
        self.applyStatus(.freeTrial)
    }

    func terminateFreeTrial() {
        self.setTrialStartDate(Date.distantPast)
        self.applyStatus(.free)
    }

    // MARK: - Free Trial (Private)

    private func elapsedTrialDays(from startDate: Date) -> Int {
        return Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
    }

    private func setTrialStartDate(_ date: Date) {
        self.trialStartDate = date
        Self.keychainSetString(ISO8601DateFormatter().string(from: date), forKey: Self.freeTrialKeychainKey)
    }

    private func loadTrialStartDateFromKeychain() {
        guard let dateString = Self.keychainGetString(forKey: Self.freeTrialKeychainKey),
              let date = ISO8601DateFormatter().date(from: dateString)
        else {
            self.trialStartDate = nil
            return
        }
        self.trialStartDate = date
    }

    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Initialization

    private init() { }

    deinit {
        self.updateListenerTask?.cancel()
    }

    // MARK: - Transaction Listener

    private func startTransactionListener() {
        self.updateListenerTask?.cancel()
        self.updateListenerTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    guard let self = self else { return }
                    let transaction = try self.checkVerified(result)
                    await self.checkPurchaseStatus()
                    await transaction.finish()
                }
                catch { }
            }
        }
    }

    // MARK: - Public Methods

    @discardableResult
    func verifyAdminCode(_ code: String, from viewController: UIViewController? = nil, completion: (() -> Void)? = nil) -> Bool {
        let isValid = code.lowercased() == Self.paywallStatusString.lowercased()
        if isValid {
            self.presentAdminModeSelector(from: viewController, completion: completion)
        }
        else {
            completion?()
        }
        return isValid
    }

    private func presentAdminModeSelector(from viewController: UIViewController?, completion: (() -> Void)?) {
        let alert = UIAlertController(
            title: "Select Mode",
            message: "Current: \(self.lastStatus.titleString)",
            preferredStyle: .alert
        )

        var modes: [(String, PurchaseStatus?)] = PurchaseStatus.allCases.map { ($0.titleString, $0) }
        modes.append(("Reset", nil))

        for (title, status) in modes {
            let action = UIAlertAction(
                title: title,
                style: status == nil ? .destructive : .default,
                handler: { [weak self] _ in
                    guard let self = self else { return }
                    if let status = status {
                        self.applyAdminOverride(status)
                    }
                    else {
                        Task { await self.checkPurchaseStatus(ignoreAdmin: true) }
                    }
                    completion?()
                }
            )
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            completion?()
        }))

        DispatchQueue.main.async {
            let presenter = viewController ?? Self.topViewController()
            presenter?.present(alert, animated: true)
        }
    }

    func setSubscribed() {
        self.applyStatus(.subscribed)
    }

    func disableAdmin() {
        Task { await self.checkPurchaseStatus(ignoreAdmin: true) }
    }

    /// admin Alert에서 상태 강제 설정
    private func applyAdminOverride(_ status: PurchaseStatus) {
        switch status {
            case .free:
                self.terminateFreeTrial()
            case .freeTrial:
                self.forceStartFreeTrial()
            case .subscribed, .admin:
                self.applyStatus(status)
        }
    }

    @discardableResult
    func checkPurchaseStatus(ignoreAdmin: Bool = false) async -> Bool {
        let resolved = await self.resolveStatus(ignoreAdmin: ignoreAdmin)
        self.applyStatus(resolved)
        return resolved.isPremium
    }

    /// admin -> StoreKit -> trial -> free 순서로 상태 결정
    private func resolveStatus(ignoreAdmin: Bool) async -> PurchaseStatus {
        // 1. admin 강제 설정은 유지 (ignoreAdmin=true면 건너뜀)
        if !ignoreAdmin, self.lastStatus == .admin { return .admin }

        // 2. 실제 구독 검증
        for await result in Transaction.currentEntitlements {
            if case .verified = result {
                return .subscribed
            }
        }

        // 3. trial 기간 확인
        if self.isInFreeTrial {
            return .freeTrial
        }

        // 4. 아무것도 아님
        return .free
    }

    // MARK: - Fetch Products

    func fetchProducts() async throws -> [Product] {
        let products = try await Product.products(for: Self.productIds)
        return products.sorted { $0.price < $1.price }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Transaction? {
        if self.lastStatus == .admin { return nil }

        let result = try await product.purchase()

        switch result {
            case let .success(verification):
                let transaction = try self.checkVerified(verification)
                await self.checkPurchaseStatus()
                await transaction.finish()
                return transaction

            case .userCancelled, .pending:
                return nil

            @unknown default:
                return nil
        }
    }

    // MARK: - Restore

    func restorePurchases() async throws -> Bool {
        if self.lastStatus == .admin { return true }
        try await AppStore.sync()
        return await self.checkPurchaseStatus()
    }

    // MARK: - Manage Subscriptions

    func openManageSubscriptions() {
        Task {
            if let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene {
                do {
                    try await AppStore.showManageSubscriptions(in: windowScene)
                }
                catch {
                    await MainActor.run {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subscription Alert

    func presentNeedSubscriptionAlert(from viewController: UIViewController? = nil) {
        let alert = UIAlertController(
            title: I18N.alert_subscription_required_title,
            message: I18N.alert_subscription_required_message,
            preferredStyle: .alert
        )

        let subscribeAction = UIAlertAction(
            title: I18N.alert_subscription_required_action,
            style: .default,
            handler: { [weak self] _ in
                self?.openManageSubscriptions()
            }
        )

        let cancelAction = UIAlertAction(
            title: I18N.alert_cancel,
            style: .cancel
        )

        alert.addAction(subscribeAction)
        alert.addAction(cancelAction)

        DispatchQueue.main.async {
            let presentingVC = viewController ?? Self.topViewController()
            presentingVC?.present(alert, animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return nil
        }
        var topVC = window.rootViewController
        while let presented = topVC?.presentedViewController {
            topVC = presented
        }
        return topVC
    }

    // MARK: - Status 영속화

    private func applyStatus(_ newStatus: PurchaseStatus) {
        guard self.lastStatus != newStatus else { return }
        self.lastStatus = newStatus
        UserDefaults.standard.set(newStatus.rawValue, forKey: IAPManager.statusKey)
        self.syncPurchaseStatusToAppGroup()
    }

    private func restoreStatus() -> PurchaseStatus {
        guard let raw = UserDefaults.standard.string(forKey: IAPManager.statusKey),
              let status = PurchaseStatus(rawValue: raw)
        else {
            return .free
        }
        return status
    }

    // MARK: - App Group Sync

    private func syncPurchaseStatusToAppGroup() {
        guard let groupId = Self.appGroupIdentifier else { return }
        let defaults = UserDefaults(suiteName: groupId)
        defaults?.set(self.lastStatus.isPremium, forKey: Self.appGroupPurchasedKey)
    }

    // MARK: - Private

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
            case .unverified:
                throw IAPError.failedVerification
            case let .verified(safe):
                return safe
        }
    }

    // MARK: - Keychain

    private static func keychainGetString(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainSetString(_ value: String, forKey key: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var newItem = query
        newItem[kSecValueData as String] = data
        SecItemAdd(newItem as CFDictionary, nil)
    }
}

// MARK: - Notification Name Extension

