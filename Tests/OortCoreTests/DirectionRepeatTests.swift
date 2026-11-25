import XCTest
@testable import OortCore

final class DirectionRepeatTests: XCTestCase {
    func testAHeldDirectionMovesOnceThenRepeatsFasterUntilReleased() {
        var repeats = DirectionRepeat()
        XCTAssertNil(repeats.tick())
        XCTAssertTrue(repeats.press(.down, from: .pad))
        XCTAssertFalse(repeats.press(.down, from: .pad))
        XCTAssertEqual(repeats.nextDelay, DirectionRepeat.firstDelay)
        XCTAssertEqual(repeats.tick(), .down)
        XCTAssertEqual(repeats.nextDelay, DirectionRepeat.interval)
        for _ in 0..<8 { XCTAssertEqual(repeats.tick(), .down) }
        XCTAssertEqual(repeats.nextDelay, DirectionRepeat.fastInterval)
        repeats.release(.down, from: .pad)
        XCTAssertNil(repeats.current); XCTAssertNil(repeats.tick())
    }

    func testTheLastDirectionLeadsAndTheOneStillHeldTakesOver() {
        var repeats = DirectionRepeat()
        _ = repeats.press(.down, from: .pad); _ = repeats.press(.right, from: .pad)
        XCTAssertEqual(repeats.current, .right)
        repeats.release(.right, from: .pad)
        XCTAssertEqual(repeats.current, .down)
        XCTAssertEqual(repeats.nextDelay, DirectionRepeat.firstDelay)
        repeats.reset()
        XCTAssertNil(repeats.current)
    }

    func testAStickMovesOncePerPushAndDoesNotChatter() {
        var repeats = DirectionRepeat()
        func push(_ x: Float, _ y: Float) -> ControllerDirection? { repeats.stick(SIMD2(x, y), deadzone: 0.35, from: .leftStick) }
        XCTAssertNil(push(0.2, 0.1))
        XCTAssertEqual(push(0.5, 0.1), .right)
        XCTAssertNil(push(0.6, 0.1)); XCTAssertNil(push(0.33, 0)); XCTAssertNil(push(0.36, 0))
        XCTAssertEqual(repeats.current, .right)
        XCTAssertEqual(push(0.1, -0.9), .down)
        XCTAssertEqual(repeats.current, .down)
        XCTAssertNil(push(0, 0))
        XCTAssertNil(repeats.current)
        XCTAssertEqual(push(0, 1), .up)
    }

    func testTheRightStickScrollsVerticallyOnly() {
        var repeats = DirectionRepeat()
        XCTAssertNil(repeats.stick(SIMD2(1, 0), deadzone: 0.35, from: .rightStick))
        XCTAssertNil(repeats.current)
        XCTAssertEqual(repeats.stick(SIMD2(0, -1), deadzone: 0.35, from: .rightStick), .down)
        XCTAssertLessThan(repeats.nextDelay, DirectionRepeat.firstDelay)
        XCTAssertNil(repeats.stick(.zero, deadzone: 0.35, from: .rightStick))
        XCTAssertNil(repeats.current)
    }
}
