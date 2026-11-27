import XCTest
@testable import NXLibraryCore

final class InputInHandTests: XCTestCase {
    func testAConnectedControllerLeadsUntilSomethingElseIsUsed() {
        var hand = InputInHand()
        XCTAssertTrue(hand.usesController(connected: true))
        XCTAssertFalse(hand.usesController(connected: false))
        hand.keyPressed()
        XCTAssertFalse(hand.usesController(connected: true))
        hand.controllerUsed(at: 1)
        XCTAssertTrue(hand.usesController(connected: true))
        XCTAssertFalse(hand.usesController(connected: false), "Unplugged, its buttons name nothing")
        hand.pointerUsed()
        XCTAssertFalse(hand.usesController(connected: true))
    }

    func testSmallOrScatteredPointerMovesNeverSwitch() {
        var hand = InputInHand()
        hand.controllerUsed(at: 0)
        for step in 0..<200 { hand.pointerMoved(by: 2, at: 1 + Double(step)) }
        XCTAssertEqual(hand.device, .controller, "One nudge a second is a table, not a hand")
        hand.pointerMoved(by: 20, at: 300)
        XCTAssertEqual(hand.device, .controller)
    }

    func testARealMoveSwitchesOnce() {
        var hand = InputInHand()
        hand.controllerUsed(at: 0)
        for step in 0..<3 { hand.pointerMoved(by: 10, at: 2 + Double(step) * 0.016) }
        XCTAssertEqual(hand.device, .pointer)
    }

    func testAMoveRightAfterAPressIsIgnored() {
        var hand = InputInHand()
        hand.controllerUsed(at: 10)
        for step in 0..<20 { hand.pointerMoved(by: 10, at: 10 + Double(step) * 0.016) }
        XCTAssertEqual(hand.device, .controller)
        for step in 0..<3 { hand.pointerMoved(by: 10, at: 10.5 + Double(step) * 0.016) }
        XCTAssertEqual(hand.device, .pointer)
    }

    func testAlternatingPressesAndBrushesDoNotFlicker() {
        var hand = InputInHand()
        for step in 0..<50 {
            hand.controllerUsed(at: Double(step))
            hand.pointerMoved(by: 8, at: Double(step) + 0.5)
            XCTAssertEqual(hand.device, .controller)
        }
    }

    func testAViewThatSlidesUnderAStillPointerIsNotHovered() {
        defer { PointerAnchor.location = nil }
        let still = CGPoint(x: 40, y: 40)
        XCTAssertFalse(PointerAnchor.isMove(to: still, from: still))
        XCTAssertTrue(PointerAnchor.isMove(to: still, from: .zero))
        PointerAnchor.location = still
        XCTAssertFalse(PointerAnchor.isMove(to: still, from: .zero), "A key scrolled the view under the pointer")
        XCTAssertTrue(PointerAnchor.isMove(to: CGPoint(x: 41, y: 40), from: .zero))
    }

    /// A hover that takes the focus goes through `seleneHover` or `SeleneHoverFocus`; a bare `onHover` only lights.
    func testNoScreenTakesTheFocusFromABareHover() throws {
        let views = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NXLibrary/Views")
        let files = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        var bare: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for piece in text.components(separatedBy: ".onHover {").dropFirst() {
                let use = piece.prefix(160).components(separatedBy: "\n        }").first ?? ""
                if !use.contains("hover.moved(") && !use.hasPrefix(" hovered = $0") { bare.append("\(file.lastPathComponent): \(use.prefix(60))") }
            }
        }
        XCTAssertEqual(bare, [])
    }
}
