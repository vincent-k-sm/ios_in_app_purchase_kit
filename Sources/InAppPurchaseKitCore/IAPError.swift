//
//  IAPError.swift
//  InAppPurchaseKit
//

import Foundation

public enum IAPError: LocalizedError {
    case failedVerification
    case noProductsFound
    case purchaseFailed
    case restoreFailed
    case timeout
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .failedVerification:
            return I18N.error_verification_failed

        case .noProductsFound:
            return I18N.error_no_products

        case .purchaseFailed:
            return I18N.error_purchase_failed

        case .restoreFailed:
            return I18N.error_restore_failed

        case .timeout:
            return I18N.error_timeout

        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
