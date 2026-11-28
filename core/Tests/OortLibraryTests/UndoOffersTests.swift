import XCTest
@testable import OortLibrary

@MainActor final class UndoOffersTests: XCTestCase {
    func testOnlyTheLastGestureIsUndoneAndOnce() async {
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

    func testTheNoticeLeavesButTheWayBackStaysUntilReplacedOrDropped() async {
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

    func testAnUndoMayOfferItsOwnWayBack() async {
        let offers = UndoOffers()
        offers.offer("hide") { offers.offer("show") {} }
        offers.perform()
        XCTAssertEqual(offers.offer?.message, "show")
    }

    func testActivityListsTheWayBackWithTheResults() async {
        let result = UUID()
        XCTAssertEqual(ActivityCenterFocus.rows(isBuilding: false, undo: true), [.undo])
        XCTAssertEqual(ActivityCenterFocus.rows(isBuilding: true, results: [result], undo: true),
                       [.build(nil), .undo, .result(result), .clearAll])
    }
}

final class NoticeFocusTests: XCTestCase {
    func testTheKeysAreReachedOnRequestAndLetGo() {
        var focus = NoticeFocus()
        focus.move(by: 1)
        XCTAssertFalse(focus.isActive, "Moving never takes the focus")
        focus.enter(keys: 2)
        XCTAssertEqual(focus.index, 0)
        for _ in 0..<3 { focus.move(by: 1) }
        XCTAssertEqual(focus.index, 1)
        for _ in 0..<3 { focus.move(by: -1) }
        XCTAssertEqual(focus.index, 0)
        focus.leave()
        XCTAssertEqual(focus, NoticeFocus())
        focus.enter(keys: 0)
        XCTAssertFalse(focus.isActive)
    }
}
