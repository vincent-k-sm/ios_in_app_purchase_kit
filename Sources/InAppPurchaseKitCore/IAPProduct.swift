//
//  IAPProduct.swift
//  InAppPurchaseKitCore
//

import Foundation

public struct IAPProduct {
    public let period: Period
    public let id: String

    public var isPopular: Bool

    public init(period: Period, id: String, isPopular: Bool = false) {
        self.period = period
        self.id = id
        self.isPopular = isPopular
    }

    /// App Store Connect에서 설정 가능한 구독/결제 기간
    public enum Period {
        /// 1일 (비소모성 테스트용)
        case daily
        /// 1주
        case weekly
        /// 1개월
        case monthly
        /// 2개월
        case bimonthly
        /// 3개월 (분기)
        case quarterly
        /// 6개월 (반기)
        case semiannual
        /// 1년
        case annual
        /// 평생 (비소모성)
        case lifetime
    }
}
