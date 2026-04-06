//
//  I18N.swift
//  STPaywallUIKit
//

import Foundation

struct I18N {

    // MARK: - Common

    static let common_confirm = "stpaywall_common_confirm".localized
    static let common_cancel = "stpaywall_common_cancel".localized

    // MARK: - List Scene

    static let list_section_subscription = "stpaywall_list_section_subscription".localized
    static let list_menu_subscription_info = "stpaywall_list_menu_subscription_info".localized
    static let list_menu_restore = "stpaywall_list_menu_restore".localized
    static let list_menu_manage_subscription = "stpaywall_list_menu_manage_subscription".localized
    static let list_menu_terminate_trial = "stpaywall_list_menu_terminate_trial".localized
    static let list_alert_terminate_title = "stpaywall_list_alert_terminate_title".localized
    static let list_alert_terminate_msg = "stpaywall_list_alert_terminate_msg".localized
    static let list_action_terminate = "stpaywall_list_action_terminate".localized

    static let list_msg_restore_success = "stpaywall_list_msg_restore_success".localized
    static let list_msg_restore_failed = "stpaywall_list_msg_restore_failed".localized
    static let list_status_subscribed = "stpaywall_list_status_subscribed".localized

    // MARK: - Detail Scene

    static let detail_price_format = "stpaywall_detail_price_format".localized
    static let detail_period_day = "stpaywall_detail_period_day".localized
    static let detail_period_week = "stpaywall_detail_period_week".localized
    static let detail_period_month = "stpaywall_detail_period_month".localized
    static let detail_period_year = "stpaywall_detail_period_year".localized

    static let detail_promotion_free_trial = "stpaywall_detail_promotion_free_trial".localized
    static let detail_promotion_introductory = "stpaywall_detail_promotion_introductory".localized

    static let detail_restore_desc = "stpaywall_detail_restore_desc".localized
    static let detail_terms_link = "stpaywall_detail_terms_link".localized

    static let detail_btn_subscribe = "stpaywall_detail_btn_subscribe".localized
    static let detail_btn_subscribed = "stpaywall_detail_btn_subscribed".localized

    static let detail_msg_success = "stpaywall_detail_msg_success".localized
    static let detail_msg_restore_success = "stpaywall_detail_msg_restore_success".localized
    static let detail_msg_restore_failed = "stpaywall_detail_msg_restore_failed".localized
    static let detail_msg_pending = "stpaywall_detail_msg_pending".localized
    static let detail_msg_verification_failed = "stpaywall_detail_msg_verification_failed".localized
    static let detail_msg_error = "stpaywall_detail_msg_error".localized
    static let detail_msg_fetch_failed = "stpaywall_detail_msg_fetch_failed".localized

    static let detail_terms_action_title = "stpaywall_detail_terms_action_title".localized
    static let detail_terms_action_message = "stpaywall_detail_terms_action_message".localized
    static let detail_terms_of_service = "stpaywall_detail_terms_of_service".localized
    static let detail_privacy_policy = "stpaywall_detail_privacy_policy".localized
}

// MARK: - String Extension

private extension String {
    var localized: String {
        return NSLocalizedString(self, bundle: .module, comment: "")
    }
}
