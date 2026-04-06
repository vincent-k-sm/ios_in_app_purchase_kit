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

public enum PurchaseStatus: Int, Comparable, CaseIterable {
    case free = 0
    case freeTrial = 1
    case subscribed = 2
    case admin = 99

    public var isPremium: Bool {
        return self != .free
    }

    public static func < (lhs: PurchaseStatus, rhs: PurchaseStatus) -> Bool {
        return lhs.rawValue < rhs.rawValue
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
    private static var freeTrialKeychainKey: String?
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
        Self.freeTrialDays = freeTrialDays
        Self.shared.lastStatus = Self.shared.restoreStatus()
        Self.shared.syncPurchaseStatusToAppGroup()
        Task { await Self.shared.checkPurchaseStatus() }
    }

    // MARK: - Notifications


    // MARK: - Status (단일 소스)

    private static let statusKey = "IAPManager.lastStatus"

    @Published private(set) var lastStatus: PurchaseStatus = .free

    /// admin이 강제로 설정한 상태인지 여부
    private var isAdminOverride: Bool = false

    var purchaseStatus: PurchaseStatus {
        if !self.isAdminOverride && self.lastStatus == .freeTrial && !self.isInFreeTrial {
            self.applyStatus(.free)
        }
        return self.lastStatus
    }

    var isPurchased: Bool {
        return self.lastStatus.isPremium
    }

    var isAdmin: Bool {
        return self.lastStatus == .admin
    }

    // MARK: - Free Trial (키체인 기반)

    var isInFreeTrial: Bool {
        guard let key = Self.freeTrialKeychainKey,
              let startDateString = Self.keychainGetString(forKey: key),
              let startDate = ISO8601DateFormatter().date(from: startDateString)
        else {
            return false
        }
        let elapsed = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return elapsed < Self.freeTrialDays
    }

    var freeTrialRemainingDays: Int {
        guard let key = Self.freeTrialKeychainKey,
              let startDateString = Self.keychainGetString(forKey: key),
              let startDate = ISO8601DateFormatter().date(from: startDateString)
        else {
            return 0
        }
        let elapsed = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return max(0, Self.freeTrialDays - elapsed)
    }

    var hasUsedFreeTrial: Bool {
        guard let key = Self.freeTrialKeychainKey else { return false }
        return Self.keychainGetString(forKey: key) != nil
    }

    @discardableResult
    func startFreeTrialIfNeeded() -> Bool {
        guard let key = Self.freeTrialKeychainKey else { return false }
        guard !self.hasUsedFreeTrial else { return false }
        let formatter = ISO8601DateFormatter()
        Self.keychainSetString(formatter.string(from: Date()), forKey: key)
        self.applyStatus(.freeTrial)
        return true
    }

    private func expireFreeTrialKeychain() {
        guard let key = Self.freeTrialKeychainKey else { return }
        let formatter = ISO8601DateFormatter()
        var components = DateComponents()
        components.year = 2000
        components.month = 1
        components.day = 1
        let pastDate = Calendar.current.date(from: components) ?? Date.distantPast
        Self.keychainSetString(formatter.string(from: pastDate), forKey: key)
    }

    func terminateFreeTrial() {
        self.expireFreeTrialKeychain()
        self.applyStatus(.free)
    }

    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Initialization

    private init() {
        self.lastStatus = self.restoreStatus()
        self.updateListenerTask = self.listenForTransactions()
        self.syncPurchaseStatusToAppGroup()
        Task { await self.checkPurchaseStatus() }
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

    /// free/freeTrial 판별 (키체인 기준)
    private var defaultFreeStatus: PurchaseStatus {
        return self.isInFreeTrial ? .freeTrial : .free
    }

    @discardableResult
    func verifyAdminCode(_ code: String, from viewController: UIViewController? = nil, completion: (() -> Void)? = nil) -> Bool {
        let isValid = code.lowercased() == Self.paywallStatusString.lowercased()
        if isValid {
            self.presentAdminModeSelector(from: viewController, completion: completion)
        }
        else {
            self.applyStatus(self.defaultFreeStatus)
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
                        self.isAdminOverride = true
                        self.applyStatus(status)
                    }
                    else {
                        self.isAdminOverride = false
                        Task { await self.checkPurchaseStatus() }
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

    func disableAdmin() {
        if self.isAdmin {
            self.applyStatus(self.defaultFreeStatus)
        }
    }


    func setPurchased(_ purchased: Bool) {
        self.applyStatus(purchased ? .subscribed : self.defaultFreeStatus)
    }

    @discardableResult
    func checkPurchaseStatus() async -> Bool {
        if self.isAdmin { return true }

        var hasActiveSubscription = false
        for await result in Transaction.currentEntitlements {
            if case .verified = result {
                hasActiveSubscription = true
                break
            }
        }
        self.applyStatus(hasActiveSubscription ? .subscribed : self.defaultFreeStatus)
        return self.isPurchased
    }

    // MARK: - Fetch Products

    func fetchProducts() async throws -> [Product] {
        let products = try await Product.products(for: Self.productIds)
        return products.sorted { $0.price < $1.price }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Transaction? {
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

    func restorePurchases() async throws -> Bool {
        if self.isAdmin { return true }
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

    // MARK: - Status 영속화 (rawValue 저장)

    private func applyStatus(_ newStatus: PurchaseStatus) {
        let oldStatus = self.lastStatus
        guard oldStatus != newStatus else { return }
        self.lastStatus = newStatus
        UserDefaults.standard.set(newStatus.rawValue, forKey: IAPManager.statusKey)
        self.syncPurchaseStatusToAppGroup()
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

