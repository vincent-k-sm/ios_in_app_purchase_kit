//
//  IAPAccessPoints.swift
//  InAppPurchaseKitCore
//
//  외부에서 IAPService.status / IAPService.admin으로 접근.
//  IAPService.shared는 internal.
//

import Combine
import Foundation
import StoreKit
import UIKit

// MARK: - 상태 읽기

public protocol IAPStatusProvider {
    var isPremium: Bool { get }
    var isAdmin: Bool { get }
    var isForceFree: Bool { get }
    var hasUsedFreeTrial: Bool { get }
    var statusLabel: String { get }
    var products: [IAPProduct] { get }
    /// 구독 상태 변경 Publisher
    var statusPublisher: AnyPublisher<PurchaseStatus, Never> { get }
}

// MARK: - 상태 변경 + StoreKit 액션

public protocol IAPAdminProvider {
    /// admin 코드 검증 + 상태 변경
    @discardableResult
    func verify(code: String) -> Bool
    /// admin 해제
    func disable()
    /// 강제 무료 모드
    func setForceFree(_ enabled: Bool)
    /// 구독 상태 설정
    func setPurchased(_ purchased: Bool)
    /// 무료 체험 시작
    @discardableResult
    func startFreeTrialIfNeeded() -> Bool
    /// StoreKit 구독 검증
    @discardableResult
    func checkPurchaseStatus() async -> Bool
    /// 상품 조회
    func fetchProducts() async throws -> [Product]
    /// 구매
    func purchase(_ product: Product) async throws -> Transaction?
    /// 복원
    func restorePurchases() async throws -> Bool
    /// 구독 관리 화면
    func openManageSubscriptions()
    /// 구독 필요 알림
    func presentNeedSubscriptionAlert(from viewController: UIViewController?)
}

public extension IAPAdminProvider {
    func presentNeedSubscriptionAlert() {
        self.presentNeedSubscriptionAlert(from: nil)
    }
}
