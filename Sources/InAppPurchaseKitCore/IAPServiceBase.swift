//
//  IAPServiceBase.swift
//  InAppPurchaseKitCore
//
//  외부 접근: IAPService.status / IAPService.admin / IAPService.features
//  IAPService.shared는 internal.
//

import Foundation
import StoreKit
import UIKit

open class IAPServiceBase: IAPStatusProvider, IAPAdminProvider {

    public init() { }

    deinit { }

    // MARK: - Configure

    public static var products: [IAPProduct] = []

    public static func configure(
        products: [IAPProduct],
        appGroupIdentifier: String? = nil,
        freeTrialKeychainKey: String? = nil,
        freeTrialDays: Int = 7
    ) {
        Self.products = products
        IAPManager.configure(
            productIds: products.map { $0.id },
            appGroupIdentifier: appGroupIdentifier,
            freeTrialKeychainKey: freeTrialKeychainKey,
            freeTrialDays: freeTrialDays
        )
    }

    // MARK: - Notifications

    public static let didCompletePurchaseNotification = IAPManager.didCompletePurchaseNotification
    public static let didExpirePurchaseNotification = IAPManager.didExpirePurchaseNotification
    public static let needPresentPurchaseSceneNotification = IAPManager.needPresentPurchaseSceneNotification

    // MARK: - IAPStatusProvider

    public var isPremium: Bool {
        return IAPManager.shared.purchaseStatus.isPremium
    }

    public var isAdmin: Bool {
        return IAPManager.shared.purchaseStatus == .admin
    }

    public var isForceFree: Bool {
        return IAPManager.shared.isForceFree
    }

    public var hasUsedFreeTrial: Bool {
        return IAPManager.shared.hasUsedFreeTrial
    }

    public var statusLabel: String {
        switch IAPManager.shared.purchaseStatus {
            case .forceFree: return "forceFree"
            case .free: return "unsubscribed"
            case .freeTrial: return "trial"
            case .subscribed: return "subscribed"
            case .admin: return "admin"
        }
    }

    // MARK: - IAPAdminProvider

    @discardableResult
    public func verify(code: String) -> Bool {
        return IAPManager.shared.verifyAdminCode(code)
    }

    public func disable() {
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

    @discardableResult
    public func checkPurchaseStatus() async -> Bool {
        return await IAPManager.shared.checkPurchaseStatus()
    }

    public func fetchProducts() async throws -> [Product] {
        return try await IAPManager.shared.fetchProducts()
    }

    public func purchase(_ product: Product) async throws -> Transaction? {
        return try await IAPManager.shared.purchase(product)
    }

    public func restorePurchases() async throws -> Bool {
        return try await IAPManager.shared.restorePurchases()
    }

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
