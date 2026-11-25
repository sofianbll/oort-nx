import XCTest
@testable import OortCore

final class FocusGridTests: XCTestCase {
    private let rows = [["a", "b", "c"], ["play", "info"]]

    func testTheFirstDirectionFindsTheFirstControl() {
        var focus = FocusGrid<String>()
        XCTAssertTrue(focus.move(.down, in: rows))
        XCTAssertEqual(focus.current, "a")
    }

    func testEachRowRemembersItsPlaceAndTheEdgesHold() {
        var focus = FocusGrid("c")
        XCTAssertFalse(focus.move(.right, in: rows))
        XCTAssertTrue(focus.move(.down, in: rows))
        XCTAssertEqual(focus.current, "info", "the column is kept, inside the shorter row")
        XCTAssertTrue(focus.move(.left, in: rows))
        XCTAssertTrue(focus.move(.up, in: rows))
        XCTAssertEqual(focus.current, "c", "the row was left on c")
        XCTAssertTrue(focus.move(.down, in: rows))
        XCTAssertEqual(focus.current, "play", "the row was left on Play")
        XCTAssertFalse(focus.move(.down, in: rows))
    }

    func testARemovedControlAndAnEmptyScreenAreHarmless() {
        var focus = FocusGrid("gone")
        XCTAssertTrue(focus.move(.left, in: rows))
        XCTAssertEqual(focus.current, "a")
        XCTAssertFalse(focus.move(.left, in: [[], []]))
    }

    func testAGridIsCutIntoWholeLines() {
        XCTAssertEqual(FocusGrid.rows([1, 2, 3, 4, 5], columns: 2), [[1, 2], [3, 4], [5]])
        XCTAssertEqual(FocusGrid.rows([1], columns: 0), [[1]])
    }
}
