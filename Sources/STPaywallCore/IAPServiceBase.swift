//
//  IAPServiceBase.swift
//  InAppPurchaseKitCore
//
//  외부 접근: IAPService.status / IAPService.admin / IAPService.features
//  IAPService.shared는 internal.
//

import Combine
import Foundation
import StoreKit
import UIKit

open class IAPServiceBase: IAPStatusProvider, IAPAdminProvider {

    public init() { }

    deinit { }

    // MARK: - Configure

    public static var _products: [IAPProduct] = []

    public static func configure(
        products: [IAPProduct],
        adminString: String,
        appGroupIdentifier: String? = nil,
        freeTrialKeychainKey: String? = nil,
        freeTrialDays: Int = 7
    ) {
        Self._products = products
        IAPManager.paywallStatusString = adminString
        IAPManager.configure(
            productIds: products.map { $0.id },
            appGroupIdentifier: appGroupIdentifier,
            freeTrialKeychainKey: freeTrialKeychainKey,
            freeTrialDays: freeTrialDays
        )
    }

    // MARK: - Notifications

    // MARK: - IAPStatusProvider

    public var currentStatus: PurchaseStatus {
        return IAPManager.shared.purchaseStatus
    }

    public var isPremium: Bool {
        return IAPManager.shared.purchaseStatus.isPremium
    }

    public var isAdmin: Bool {
        return IAPManager.shared.purchaseStatus == .admin
    }

    public var hasUsedFreeTrial: Bool {
        return IAPManager.shared.hasUsedFreeTrial
    }

    public var products: [IAPProduct] {
        return Self._products
    }

    public var statusPublisher: AnyPublisher<PurchaseStatus, Never> {
        return IAPManager.shared.$lastStatus.eraseToAnyPublisher()
    }

    public var freeTrialRemainingDays: Int {
        return IAPManager.shared.freeTrialRemainingDays
    }

    public var statusLabel: String {
        switch IAPManager.shared.purchaseStatus {
            case .free: return "unsubscribed"
            case .freeTrial: return "trial"
            case .subscribed: return "subscribed"
            case .admin: return "admin"
        }
    }

    // MARK: - IAPAdminProvider

    @discardableResult
    public func verify(code: String, from viewController: UIViewController? = nil, completion: (() -> Void)? = nil) -> Bool {
        return IAPManager.shared.verifyAdminCode(code, from: viewController, completion: completion)
    }

    public func disable() {
        IAPManager.shared.disableAdmin()
    }

    public func setPurchased(_ purchased: Bool) {
        IAPManager.shared.setPurchased(purchased)
    }

    @discardableResult
    public func startFreeTrialIfNeeded() -> Bool {
        return IAPManager.shared.startFreeTrialIfNeeded()
    }

    public func terminateFreeTrial() {
        IAPManager.shared.terminateFreeTrial()
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

}
