//
//  IAPServiceBase.swift
//  InAppPurchaseKitCore
//
//  외부에 노출되는 유일한 접근점.
//  각 프로젝트에서 상속하여 initSDK()에서 configure 호출.
//

import Foundation
import StoreKit
import UIKit

public protocol AvailablePremiumFeatures {
    var shouldShowWelcome: Bool { get }
}

open class IAPServiceBase {

    public init() { }

    deinit { }

    // MARK: - Configure

    public static func configure(
        productIds: [String],
        appGroupIdentifier: String? = nil,
        freeTrialKeychainKey: String? = nil,
        freeTrialDays: Int = 7
    ) {
        IAPManager.configure(
            productIds: productIds,
            appGroupIdentifier: appGroupIdentifier,
            freeTrialKeychainKey: freeTrialKeychainKey,
            freeTrialDays: freeTrialDays
        )
    }

    // MARK: - Notifications

    public static let didCompletePurchaseNotification = IAPManager.didCompletePurchaseNotification
    public static let didExpirePurchaseNotification = IAPManager.didExpirePurchaseNotification
    public static let needPresentPurchaseSceneNotification = IAPManager.needPresentPurchaseSceneNotification

    // MARK: - 구독 상태

    public var status: PurchaseStatus {
        return IAPManager.shared.purchaseStatus
    }

    public var isPremium: Bool {
        return self.status.isPremium
    }

    public var isAdmin: Bool {
        return self.status == .admin
    }

    public var isForceFree: Bool {
        return IAPManager.shared.isForceFree
    }

    public var hasUsedFreeTrial: Bool {
        return IAPManager.shared.hasUsedFreeTrial
    }

    public var statusLabel: String {
        switch self.status {
            case .forceFree: return "forceFree"
            case .free: return "unsubscribed"
            case .freeTrial: return "trial"
            case .subscribed: return "subscribed"
            case .admin: return "admin"
        }
    }

    // MARK: - 상태 변경

    @discardableResult
    public func verifyAdminCode(_ code: String) -> Bool {
        return IAPManager.shared.verifyAdminCode(code)
    }

    public func disableAdmin() {
        IAPManager.shared.disableAdmin()
    }

    public func setForceFree(_ enabled: Bool) {
        IAPManager.shared.setForceFree(enabled)
    }

    public func setPurchased(_ purchased: Bool) {
        IAPManager.shared.setPurchased(purchased)
    }

    @discardableResult
    public func startFreeTrialIfNeeded() -> Bool {
        return IAPManager.shared.startFreeTrialIfNeeded()
    }

    // MARK: - StoreKit

    public func fetchProducts() async throws -> [Product] {
        return try await IAPManager.shared.fetchProducts()
    }

    public func purchase(_ product: Product) async throws -> Transaction? {
        return try await IAPManager.shared.purchase(product)
    }

    public func restorePurchases() async throws -> Bool {
        return try await IAPManager.shared.restorePurchases()
    }

    @discardableResult
    public func checkPurchaseStatus() async -> Bool {
        return await IAPManager.shared.checkPurchaseStatus()
    }

    // MARK: - UI

    public func openManageSubscriptions() {
        IAPManager.shared.openManageSubscriptions()
    }

    public func presentNeedSubscriptionAlert(from viewController: UIViewController? = nil) {
        IAPManager.shared.presentNeedSubscriptionAlert(from: viewController)
    }

    public func requestPremiumIfNeeded() {
        guard !self.isPremium else { return }
        NotificationCenter.default.post(
            name: Self.needPresentPurchaseSceneNotification,
            object: nil
        )
    }
}
