//
//  IAPManager.swift
//  IAPKit
//
//  공통 SDK. configure()로 상품 ID 주입.
//  상태는 lastStatus(PurchaseStatus) 단일 소스.
//  UserDefaults에는 rawValue만 저장/복원.
//

import Foundation
import StoreKit
import UIKit

// MARK: - PurchaseStatus

public enum PurchaseStatus: Int, Comparable {
    case forceFree = -1
    case free = 0
    case freeTrial = 1
    case subscribed = 2
    case admin = 99

    public var isPremium: Bool {
        return self != .free && self != .forceFree
    }

    public static func < (lhs: PurchaseStatus, rhs: PurchaseStatus) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - IAPConfiguration

// MARK: - IAPManager

public final class IAPManager {

    // MARK: - Singleton

    public static let shared = IAPManager()

    // MARK: - Admin Backdoor

    private static let adminString: String = "vincent"

    // MARK: - Properties

    private static var productIds: [String] = []
    private static var appGroupIdentifier: String?
    private static var freeTrialKeychainKey: String?
    private static var freeTrialDays: Int = 7
    private static let appGroupPurchasedKey = "isPurchased"

    // MARK: - Configure (프로젝트별 래퍼에서 호출)

    public static func configure(
        productIds: [String],
        appGroupIdentifier: String? = nil,
        freeTrialKeychainKey: String? = nil,
        freeTrialDays: Int = 7
    ) {
        Self.productIds = productIds
        Self.appGroupIdentifier = appGroupIdentifier
        Self.freeTrialKeychainKey = freeTrialKeychainKey
        Self.freeTrialDays = freeTrialDays
    }

    // MARK: - Notifications

    public static let didCompletePurchaseNotification = Notification.Name("IAPManagerDidCompletePurchase")
    public static let didExpirePurchaseNotification = Notification.Name("IAPManagerDidExpirePurchase")
    public static let needPresentPurchaseSceneNotification = Notification.Name("IAPManagerNeedPresentPurchaseScene")

    // MARK: - Status (단일 소스)

    private static let statusKey = "IAPManager.lastStatus"

    private(set) public var lastStatus: PurchaseStatus = .free

    public var purchaseStatus: PurchaseStatus {
        if self.lastStatus == .freeTrial && !self.isInFreeTrial {
            self.applyStatus(.free)
        }
        return self.lastStatus
    }

    public var isPurchased: Bool {
        return self.lastStatus.isPremium
    }

    public var isAdmin: Bool {
        return self.lastStatus == .admin
    }

    // MARK: - Free Trial (키체인 기반)

    public var isInFreeTrial: Bool {
        guard let key = Self.freeTrialKeychainKey,
              let startDateString = Self.keychainGetString(forKey: key),
              let startDate = ISO8601DateFormatter().date(from: startDateString)
        else {
            return false
        }
        let elapsed = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return elapsed < Self.freeTrialDays
    }

    public var hasUsedFreeTrial: Bool {
        guard let key = Self.freeTrialKeychainKey else { return false }
        return Self.keychainGetString(forKey: key) != nil
    }

    @discardableResult
    public func startFreeTrialIfNeeded() -> Bool {
        guard let key = Self.freeTrialKeychainKey else { return false }
        guard !self.hasUsedFreeTrial else { return false }
        let formatter = ISO8601DateFormatter()
        Self.keychainSetString(formatter.string(from: Date()), forKey: key)
        self.applyStatus(.freeTrial)
        return true
    }

    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Initialization

    private init() {
        self.lastStatus = self.restoreStatus()
        self.updateListenerTask = self.listenForTransactions()
        self.syncPurchaseStatusToAppGroup()
    }

    deinit {
        self.updateListenerTask?.cancel()
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updatePurchasedState()
                    await transaction.finish()
                }
                catch { }
            }
        }
    }

    // MARK: - Public Methods

    @discardableResult
    public func verifyAdminCode(_ code: String) -> Bool {
        let isValid = code.lowercased() == Self.adminString.lowercased()
        self.applyStatus(isValid ? .admin : self.isInFreeTrial ? .freeTrial : .free)
        return isValid
    }

    public func disableAdmin() {
        if self.isAdmin {
            self.applyStatus(self.isInFreeTrial ? .freeTrial : .free)
        }
    }

    public var isForceFree: Bool {
        return self.lastStatus == .forceFree
    }

    public func setForceFree(_ enabled: Bool) {
        self.applyStatus(enabled ? .forceFree : self.isInFreeTrial ? .freeTrial : .free)
    }

    public func setPurchased(_ purchased: Bool) {
        self.applyStatus(purchased ? .subscribed : .free)
    }

    public func refreshStatusFromExternalSource() {
        let resolved = self.isInFreeTrial ? PurchaseStatus.freeTrial : .free
        if self.lastStatus != .admin && self.lastStatus != .subscribed {
            self.applyStatus(resolved)
        }
    }

    @discardableResult
    public func checkPurchaseStatus() async -> Bool {
        if self.isAdmin { return true }

        var hasActiveSubscription = false
        for await result in Transaction.currentEntitlements {
            if case .verified = result {
                hasActiveSubscription = true
                break
            }
        }
        if hasActiveSubscription {
            self.applyStatus(.subscribed)
        }
        else if self.lastStatus == .subscribed {
            self.applyStatus(self.isInFreeTrial ? .freeTrial : .free)
        }
        return self.isPurchased
    }

    // MARK: - Fetch Products

    public func fetchProducts() async throws -> [Product] {
        let products = try await Product.products(for: Self.productIds)
        return products.sorted { $0.price < $1.price }
    }

    // MARK: - Purchase

    public func purchase(_ product: Product) async throws -> Transaction? {
        if self.isAdmin { return nil }

        let result = try await product.purchase()

        switch result {
            case let .success(verification):
                let transaction = try self.checkVerified(verification)
                await self.updatePurchasedState()
                await transaction.finish()
                return transaction

            case .userCancelled, .pending:
                return nil

            @unknown default:
                return nil
        }
    }

    // MARK: - Restore

    public func restorePurchases() async throws -> Bool {
        if self.isAdmin { return true }
        try await AppStore.sync()
        return await self.checkPurchaseStatus()
    }

    // MARK: - Manage Subscriptions

    public func openManageSubscriptions() {
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

    public func presentNeedSubscriptionAlert(from viewController: UIViewController? = nil) {
        let alert = UIAlertController(
            title: I18N.alert_subscription_required_title,
            message: I18N.alert_subscription_required_message,
            preferredStyle: .alert
        )

        let subscribeAction = UIAlertAction(
            title: I18N.alert_subscription_required_action,
            style: .default,
            handler: { _ in
                NotificationCenter.default.post(
                    name: IAPManager.needPresentPurchaseSceneNotification,
                    object: nil
                )
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

    // MARK: - Status 영속화 (rawValue 저장)

    private func applyStatus(_ newStatus: PurchaseStatus) {
        let oldStatus = self.lastStatus
        guard oldStatus != newStatus else { return }
        self.lastStatus = newStatus
        UserDefaults.standard.set(newStatus.rawValue, forKey: IAPManager.statusKey)
        self.syncPurchaseStatusToAppGroup()
        guard oldStatus.isPremium != newStatus.isPremium else { return }
        let name = newStatus.isPremium
            ? IAPManager.didCompletePurchaseNotification
            : IAPManager.didExpirePurchaseNotification
        NotificationCenter.default.post(name: name, object: nil)
    }

    private func restoreStatus() -> PurchaseStatus {
        let raw = UserDefaults.standard.integer(forKey: IAPManager.statusKey)
        let status = PurchaseStatus(rawValue: raw) ?? .free
        if status == .freeTrial && !self.isInFreeTrial { return .free }
        return status
    }

    // MARK: - App Group Sync

    private func syncPurchaseStatusToAppGroup() {
        guard let groupId = Self.appGroupIdentifier else { return }
        let defaults = UserDefaults(suiteName: groupId)
        defaults?.set(self.isPurchased, forKey: Self.appGroupPurchasedKey)
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

    private func updatePurchasedState() async {
        await self.checkPurchaseStatus()
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

public extension Notification.Name {
    static let didCompletePurchase = IAPManager.didCompletePurchaseNotification
    static let didExpirePurchase = IAPManager.didExpirePurchaseNotification
    static let needPresentPurchaseScene = IAPManager.needPresentPurchaseSceneNotification
}
