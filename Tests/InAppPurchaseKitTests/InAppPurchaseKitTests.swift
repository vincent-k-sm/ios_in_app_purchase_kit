import XCTest
@testable import IAPKit

final class InAppPurchaseKitTests: XCTestCase {
    func testPurchaseStatusComparable() {
        XCTAssertTrue(PurchaseStatus.free < PurchaseStatus.subscribed)
        XCTAssertTrue(PurchaseStatus.subscribed < PurchaseStatus.admin)
    }

    func testIsPremium() {
        XCTAssertFalse(PurchaseStatus.free.isPremium)
        XCTAssertTrue(PurchaseStatus.freeTrial.isPremium)
        XCTAssertTrue(PurchaseStatus.subscribed.isPremium)
        XCTAssertTrue(PurchaseStatus.admin.isPremium)
    }
}
