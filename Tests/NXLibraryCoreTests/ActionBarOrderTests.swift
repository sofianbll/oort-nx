import XCTest
@testable import NXLibraryCore

final class ActionBarOrderTests: XCTestCase {
    private let roles: (String) -> ActionBarRole = {
        ["Delete": .destructive, "Cancel": .back, "Keep": .secondary, "Other": .secondary, "Use": .primary][$0]!
    }

    func testBackIsOnTheLeftAndTheWayForwardIsLastOnTheRight() {
        let sorted = ActionBarOrder.sorted(["Use", "Keep", "Cancel", "Other", "Delete"], role: roles)
        XCTAssertEqual(sorted, ["Delete", "Cancel", "Keep", "Other", "Use"])
        XCTAssertEqual(sorted.filter { roles($0).isLeading }, ["Delete", "Cancel"])
        let forward = sorted.firstIndex(of: "Use")!, erase = sorted.firstIndex(of: "Delete")!
        XCTAssertGreaterThan(forward - erase, 1, "What erases is never beside the way forward")
    }

    func testReturnIsTheWayForwardUnlessItErasesOrMoves() {
        XCTAssertEqual(ActionBarOrder.initial(["Cancel", "Use"], role: roles), "Use")
        XCTAssertEqual(ActionBarOrder.initial(["Cancel", "Use"], safe: true, role: roles), "Cancel")
        XCTAssertEqual(ActionBarOrder.initial(["Cancel"], role: roles), "Cancel")
        XCTAssertNil(ActionBarOrder.initial([String](), role: roles))
    }
}
