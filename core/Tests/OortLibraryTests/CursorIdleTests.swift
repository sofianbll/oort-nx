import XCTest
@testable import OortLibrary

final class CursorIdleTests: XCTestCase {
    func testPointerSamplingDetectsMovementMissedByNativeEventTracking() {
        var cursor = CursorIdleState()
        XCTAssertFalse(cursor.observePointer(at: CGPoint(x: 100, y: 100), now: 0))
        _ = cursor.update(now: 0, eligible: true)
        XCTAssertTrue(cursor.update(now: 3, eligible: true))
        // Keyboard-only menu changes leave the actual pointer in place.
        XCTAssertFalse(cursor.observePointer(at: CGPoint(x: 100, y: 100), now: 4))
        XCTAssertTrue(cursor.isHidden)
        // No mouse event needs to reach the local monitor for this movement to be detected.
        XCTAssertTrue(cursor.observePointer(at: CGPoint(x: 120, y: 100), now: 5))
        XCTAssertFalse(cursor.isHidden)
        XCTAssertFalse(cursor.update(now: 7.9, eligible: true))
        XCTAssertTrue(cursor.update(now: 8, eligible: true))
    }

    func testHidesAfterThreeSecondsAndMouseMovementRestartsTheDelay() {
        var cursor = CursorIdleState()
        XCTAssertFalse(cursor.update(now: 10, eligible: true))
        XCTAssertFalse(cursor.update(now: 12.9, eligible: true))
        XCTAssertTrue(cursor.update(now: 13, eligible: true))
        cursor.mouseActivity(now: 14)
        XCTAssertFalse(cursor.isHidden)
        XCTAssertFalse(cursor.update(now: 16.9, eligible: true))
        XCTAssertTrue(cursor.update(now: 17, eligible: true))
    }

    func testLeavingFullscreenOrOpeningADialogRestoresAndRestartsTheDelay() {
        var cursor = CursorIdleState()
        _ = cursor.update(now: 0, eligible: true)
        XCTAssertTrue(cursor.update(now: 3, eligible: true))
        XCTAssertFalse(cursor.update(now: 4, eligible: false))
        XCTAssertFalse(cursor.update(now: 20, eligible: true))
        XCTAssertFalse(cursor.update(now: 22.9, eligible: true))
        XCTAssertTrue(cursor.update(now: 23, eligible: true))
    }

    func testWindowedOrInactiveLauncherNeverHides() {
        var cursor = CursorIdleState()
        XCTAssertFalse(cursor.update(now: 0, eligible: false))
        XCTAssertFalse(cursor.update(now: 500, eligible: false))
        XCTAssertFalse(cursor.update(now: 501, eligible: true))
    }

    func testAControllerHidesThePointerUntilItMovesInAWindowToo() {
        var cursor = CursorIdleState()
        XCTAssertFalse(cursor.update(now: 0, eligible: true, fullscreen: false))
        XCTAssertFalse(cursor.update(now: 60, eligible: true, fullscreen: false), "A still pointer stays in a window")
        cursor.controllerUsed()
        XCTAssertTrue(cursor.update(now: 60.1, eligible: true, fullscreen: false))
        _ = cursor.observePointer(at: .zero, now: 61)
        XCTAssertTrue(cursor.update(now: 61, eligible: true, fullscreen: false))
        XCTAssertTrue(cursor.observePointer(at: CGPoint(x: 4, y: 0), now: 62))
        XCTAssertFalse(cursor.update(now: 62, eligible: true, fullscreen: false))
        cursor.controllerUsed()
        XCTAssertFalse(cursor.update(now: 63, eligible: false), "Another window or a menu shows it")
        XCTAssertFalse(cursor.update(now: 64, eligible: true, fullscreen: false))
    }
}
