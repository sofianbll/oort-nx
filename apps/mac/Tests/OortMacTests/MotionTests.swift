import XCTest
@testable import OortMac

final class MotionTests: XCTestCase {
    func testReducedMotionStopsFocusRailsAndPagesButAllowsFades() {
        XCTAssertNil(Motion.focus(true))
        XCTAssertNil(Motion.focus(true, entering: false))
        XCTAssertNil(Motion.rail(true, .spotlight))
        XCTAssertNil(Motion.rail(true, .collection))
        XCTAssertNil(Motion.screen(true))
        XCTAssertNotNil(Motion.rail(false, .spotlight))
        XCTAssertNotNil(Motion.rail(false, .collection))
        XCTAssertNotNil(Motion.overlay(true))
        XCTAssertNotNil(Motion.anchoredCard(true))
        XCTAssertNotNil(Motion.toast(true))
    }

    func testRailClampsInterpolatedPositionToCurrentBounds() {
        XCTAssertEqual(Motion.railOffset(-0.5, maximum: 5), 0)
        XCTAssertEqual(Motion.railOffset(2.5, maximum: 5), 2.5)
        XCTAssertEqual(Motion.railOffset(5.5, maximum: 5), 5)
        XCTAssertEqual(Motion.railOffset(2, maximum: 0), 0)
    }

    func testReducedMotionStopsTransfersAndBuildArt() {
        XCTAssertNil(Motion.transfer(true))
        XCTAssertNil(Motion.buildArt(true, .fill))
    }
}
