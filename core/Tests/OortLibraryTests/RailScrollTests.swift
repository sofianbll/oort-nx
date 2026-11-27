import XCTest
@testable import NXLibraryCore

final class RailScrollTests: XCTestCase {
    func testFingersMoveOneTilePerTileOfTravel() {
        var rail = RailScroll()
        var steps = 0
        for event in 0..<30 { steps += rail.steps(-10, precise: true, began: event == 0, pitch: 100, at: Double(event) / 60) }
        XCTAssertEqual(steps, 3)
    }

    func testDraggingRightGoesBack() {
        var rail = RailScroll()
        XCTAssertEqual(rail.steps(250, precise: true, began: true, pitch: 100, at: 0), -2)
        XCTAssertEqual(rail.steps(50, precise: true, began: false, pitch: 100, at: 0.02), -1, "The half tile left is kept")
    }

    func testAWheelNotchIsOneTileWhateverItsAcceleration() {
        var rail = RailScroll()
        XCTAssertEqual(rail.steps(-1, precise: false, began: false, pitch: 100, at: 0), 1)
        XCTAssertEqual(rail.steps(-9, precise: false, began: false, pitch: 100, at: 0.1), 1)
        XCTAssertEqual(rail.steps(1, precise: false, began: false, pitch: 100, at: 0.2), -1)
        XCTAssertEqual(rail.steps(0, precise: false, began: false, pitch: 100, at: 0.3), 0)
    }

    func testAnOldGestureNeverAddsUp() {
        var rail = RailScroll()
        XCTAssertEqual(rail.steps(-90, precise: true, began: true, pitch: 100, at: 0), 0)
        XCTAssertEqual(rail.steps(-20, precise: true, began: false, pitch: 100, at: 2), 0)
        XCTAssertEqual(rail.steps(-90, precise: true, began: true, pitch: 100, at: 2.1), 0, "A new touch starts over")
        XCTAssertEqual(rail.steps(20, precise: true, began: false, pitch: 100, at: 2.15), 0, "Turning back starts over")
    }

    func testVerticalScrollingIsTheRowsOnlyWhereNothingElseScrolls() {
        XCTAssertEqual(RailScroll.delta(x: 5, y: 2, verticalToo: false), 5)
        XCTAssertNil(RailScroll.delta(x: 2, y: 5, verticalToo: false))
        XCTAssertEqual(RailScroll.delta(x: 2, y: 5, verticalToo: true), 5)
        XCTAssertNil(RailScroll.delta(x: 0, y: 0, verticalToo: true))
    }
}
