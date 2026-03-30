//
//  I18N.swift
//  InAppPurchaseKitCore
//

import Foundation

enum I18N {
    // MARK: - Errors
    static let error_verification_failed = NSLocalizedString("iap_error_verification_failed", bundle: Bundle.module, comment: "")
    static let error_no_products = NSLocalizedString("iap_error_no_products", bundle: Bundle.module, comment: "")
    static let error_purchase_failed = NSLocalizedString("iap_error_purchase_failed", bundle: Bundle.module, comment: "")
    static let error_restore_failed = NSLocalizedString("iap_error_restore_failed", bundle: Bundle.module, comment: "")
    static let error_timeout = NSLocalizedString("iap_error_timeout", bundle: Bundle.module, comment: "")

    // MARK: - Messages
    static let msg_purchase_success = NSLocalizedString("iap_msg_purchase_success", bundle: Bundle.module, comment: "")
    static let msg_restore_success = NSLocalizedString("iap_msg_restore_success", bundle: Bundle.module, comment: "")

    // MARK: - Alerts
    static let alert_subscription_required_title = NSLocalizedString("iap_alert_subscription_required_title", bundle: Bundle.module, comment: "")
    static let alert_subscription_required_message = NSLocalizedString("iap_alert_subscription_required_message", bundle: Bundle.module, comment: "")
    static let alert_subscription_required_action = NSLocalizedString("iap_alert_subscription_required_action", bundle: Bundle.module, comment: "")
    static let alert_cancel = NSLocalizedString("iap_alert_cancel", bundle: Bundle.module, comment: "")
}
