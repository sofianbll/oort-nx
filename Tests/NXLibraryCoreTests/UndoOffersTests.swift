import XCTest
@testable import NXLibraryCore

@MainActor final class UndoOffersTests: XCTestCase {
    func testOnlyTheLastGestureIsUndoneAndOnce() {
        let offers = UndoOffers()
        XCTAssertFalse(offers.perform())
        var undone: [String] = []
        offers.offer("first") { undone.append("first") }
        offers.offer("second") { undone.append("second") }
        XCTAssertEqual(offers.offer?.message, "second")
        XCTAssertTrue(offers.perform())
        XCTAssertFalse(offers.perform())
        XCTAssertEqual(undone, ["second"])
        XCTAssertNil(offers.offer)
    }

    func testTheNoticeLeavesButTheWayBackStaysUntilReplacedOrDropped() {
        let offers = UndoOffers()
        offers.offer("a") {}
        let first = offers.offer!.id
        offers.hide(first)
        XCTAssertFalse(offers.isShown)
        XCTAssertEqual(offers.offer?.id, first)
        offers.offer("b") {}
        offers.hide(first)
        XCTAssertTrue(offers.isShown, "An older notice's timer does not hide a newer one")
        offers.drop()
        XCTAssertFalse(offers.perform())
        XCTAssertFalse(offers.isShown)
    }

    func testAnUndoMayOfferItsOwnWayBack() {
        let offers = UndoOffers()
        offers.offer("hide") { offers.offer("show") {} }
        offers.perform()
        XCTAssertEqual(offers.offer?.message, "show")
    }

    func testActivityListsTheWayBackWithTheResults() {
        let result = UUID()
        XCTAssertEqual(ActivityCenterFocus.rows(isBuilding: false, undo: true), [.undo])
        XCTAssertEqual(ActivityCenterFocus.rows(isBuilding: true, results: [result], undo: true),
                       [.build(nil), .undo, .result(result), .clearAll])
    }
}
