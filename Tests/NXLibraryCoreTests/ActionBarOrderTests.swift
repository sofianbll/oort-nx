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

    func testAListPutsTheWayForwardOnTopAndTheWayBackAtTheBottom() {
        XCTAssertEqual(ActionBarOrder.stacked(["Delete", "Cancel", "Keep", "Use"], role: roles), ["Use", "Keep", "Delete", "Cancel"])
    }

    func testAQuestionLeadsWithItsWayBackAndEndsWithItsMainAnswer() {
        func order(_ main: String?, _ others: [String], erases: Set<String> = []) -> [String] {
            ActionBarOrder.question(main: main, others: others, back: "Cancel") { erases.contains($0) }.map(\.item)
        }
        XCTAssertEqual(order("Use", ["Keep", "Other"]), ["Cancel", "Other", "Keep", "Use"], "The first offered stays nearest the main answer")
        XCTAssertEqual(order(nil, ["Keep", "Other"]), ["Cancel", "Other", "Keep"], "Without a main answer the first offered leads")
        XCTAssertEqual(order("Use", ["Delete"], erases: ["Delete"]), ["Delete", "Cancel", "Use"])
        XCTAssertEqual(order("Delete", [], erases: ["Delete"]), ["Cancel", "Delete"], "A question that only erases keeps its answer last, in the danger colour")
        XCTAssertEqual(order(nil, []), ["Cancel"])
        XCTAssertEqual(ActionBarOrder.question(main: nil, others: [], back: "OK") { _ in false }.first?.role, .primary, "A notice has one key, on the right")
    }
}
