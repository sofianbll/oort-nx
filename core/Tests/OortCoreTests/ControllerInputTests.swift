import XCTest
@testable import OortCore

final class ControllerInputTests: XCTestCase {
    func testNintendoReportMapsEveryButtonBit() throws {
        let expected: [ControllerButton] = [
            .b, .a, .y, .x, .l, .r, .zl, .zr,
            .view, .menu, .l3, .r3, .home, .capture,
        ]
        var decoder = NintendoHIDInput()
        for bit in 0..<16 {
            var bytes = report()
            bytes[bit / 8] = UInt8(1 << (bit % 8))
            let state = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: bytes))
            XCTAssertEqual(state.buttons, expected.indices.contains(bit) ? [expected[bit]] : [], "bit \(bit)")
        }
    }

    func testHatMovesClockwiseAndCentersOutsideItsRange() throws {
        let expected: [Set<ControllerButton>] = [
            [.up], [.up, .right], [.right], [.right, .down],
            [.down], [.down, .left], [.left], [.left, .up], [],
        ]
        var decoder = NintendoHIDInput()
        for (hat, buttons) in expected.enumerated() {
            XCTAssertEqual(decoder.decode(reportID: 0x3f, bytes: report(hat: UInt8(hat)))?.buttons, buttons)
        }
        XCTAssertEqual(decoder.decode(reportID: 0x3f, bytes: report(hat: 255))?.buttons, [])
    }

    func testReportWithOrWithoutIDAndRejectsShortOrUnrelatedReports() throws {
        var decoder = NintendoHIDInput()
        let bytes = report(buttons: 0x3f)
        let payload = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: bytes))
        XCTAssertEqual(payload.buttons, [.b, .a, .y, .x, .l, .r])
        XCTAssertEqual(decoder.decode(reportID: 0x3f, bytes: [0x3f] + bytes), payload)
        XCTAssertNil(decoder.decode(reportID: 0x21, bytes: bytes))
        XCTAssertNil(decoder.decode(reportID: 0x3f, bytes: []))
        XCTAssertNil(decoder.decode(reportID: 0x3f, bytes: Array(bytes.prefix(10))))
        XCTAssertNil(decoder.decode(reportID: 0x3f, bytes: [0x3f] + bytes.prefix(9)))
    }

    func testSticksLearnRestAndSeparateReachesAndSaturateAt91Percent() throws {
        var decoder = NintendoHIDInput()
        XCTAssertEqual(decoder.decode(reportID: 0x3f, bytes: report(lx: 29_491))?.leftStick, .zero)
        XCTAssertEqual(decoder.decode(reportID: 0x3f, bytes: report(lx: 32_000))?.leftStick, .zero)
        let halfReach = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: report(lx: 40_959)))
        XCTAssertEqual(halfReach.leftStick.x, 0.48718, accuracy: 0.0002)
        XCTAssertEqual(decoder.decode(reportID: 0x3f, bytes: report(lx: 58_982))?.leftStick.x, 1)
        XCTAssertEqual(decoder.decode(reportID: 0x3f, bytes: report(lx: 56_328))?.leftStick.x, 1)
        let grownReach = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: report(lx: 44_237)))
        XCTAssertEqual(grownReach.leftStick.x, 0.48718, accuracy: 0.0002)
        let otherSide = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: report(lx: 18_022)))
        XCTAssertEqual(otherSide.leftStick.x, -0.48718, accuracy: 0.0002)
    }

    func testHeldStickIsNotLearnedAsRestAndBothYAxesAreInverted() throws {
        var decoder = NintendoHIDInput()
        let first = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: report(ly: 0, rx: .max, ry: .max)))
        XCTAssertEqual(first.leftStick, SIMD2(0, 1))
        XCTAssertEqual(first.rightStick.x, 1)
        XCTAssertEqual(first.rightStick.y, -1)
        let centered = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: report()))
        XCTAssertEqual(centered.leftStick, .zero)
        XCTAssertEqual(centered.rightStick, .zero)
    }

    func testTransitionsOnlyEmitChangedControls() throws {
        var decoder = NintendoHIDInput()
        let upAndA = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: report(buttons: 2, hat: 0)))
        XCTAssertEqual(upAndA.changes(from: .init()), [.button(.up, true), .button(.a, true)])
        XCTAssertEqual(upAndA.changes(from: upAndA), [])
        let right = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: report(hat: 2, lx: .max)))
        XCTAssertEqual(right.changes(from: upAndA), [
            .button(.up, false), .button(.right, true), .button(.a, false), .leftStick(SIMD2(1, 0)),
        ])
        XCTAssertEqual(ControllerInputState().changes(from: right), [.button(.right, false), .leftStick(.zero)])
    }

    func testNintendoReportModeSwitchPreservesHeldButtonsAndReleasesStaleInputs() throws {
        var decoder = NintendoHIDInput()
        let simple = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: report(buttons: 3, hat: 0, lx: .max)))
        let fullBytes = fullReport(buttons: [0x08, 0, 0x04])
        let full = try XCTUnwrap(decoder.decode(reportID: 0x30, bytes: fullBytes))
        XCTAssertEqual(full.changes(from: simple), [
            .button(.up, false), .button(.right, true), .button(.b, false), .leftStick(.zero),
        ])
        XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: [0x30] + fullBytes)?.changes(from: full), [])
        let neutral = try XCTUnwrap(decoder.decode(reportID: 0x3f, bytes: report()))
        XCTAssertEqual(neutral.changes(from: full), [.button(.right, false), .button(.a, false)])
    }

    func testNintendoFullReportMapsEveryButtonBit() {
        let expected: [ControllerButton?] = [
            .y, .x, .b, .a, nil, nil, .r, .zr,
            .view, .menu, .r3, .l3, .home, .capture, nil, nil,
            .down, .up, .right, .left, nil, nil, .l, .zl,
        ]
        var decoder = NintendoHIDInput()
        for (bit, button) in expected.enumerated() {
            var bytes = fullReport()
            bytes[2 + bit / 8] = UInt8(1 << (bit % 8))
            let buttons: Set<ControllerButton> = button.map { [$0] } ?? []
            XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: bytes)?.buttons, buttons, "payload bit \(bit)")
            XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: [0x30] + bytes)?.buttons, buttons, "report bit \(bit)")
        }
        XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: fullReport(buttons: [0, 0, 0x06]))?.buttons, [.up, .right])
    }

    func testNintendoFullReportRejectsUnknownIDsAndInvalidLengths() throws {
        var decoder = NintendoHIDInput()
        let bytes = fullReport(buttons: [0x08, 0, 0], lx: 3500)
        let padded = bytes + Array(repeating: 0, count: 15)
        for id: UInt32 in [0, 0x21, 0x31, 0x81] {
            XCTAssertNil(decoder.decode(reportID: id, bytes: [0x30] + bytes))
        }
        XCTAssertNil(decoder.decode(reportID: 0x30, bytes: []))
        XCTAssertNil(decoder.decode(reportID: 0x30, bytes: bytes.dropLast()))
        XCTAssertNil(decoder.decode(reportID: 0x30, bytes: [0x21] + bytes))
        let state = try XCTUnwrap(decoder.decode(reportID: 0x30, bytes: bytes))
        XCTAssertEqual(state.buttons, [.a])
        XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: padded), state)
        XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: [0x30] + padded), state)
    }

    func testNintendoFullReportPacksBothSticksWithYUpAndCentersAfterExtremes() throws {
        var decoder = NintendoHIDInput()
        for (low, high): (UInt16, UInt16) in [(0, 4095), (4095, 0)] {
            let state = try XCTUnwrap(decoder.decode(reportID: 0x30,
                                                     bytes: fullReport(lx: low, ly: high, rx: high, ry: low)))
            let direction: Float = low == 0 ? -1 : 1
            XCTAssertEqual(state.leftStick, SIMD2(direction, -direction))
            XCTAssertEqual(state.rightStick, SIMD2(-direction, direction))
        }
        XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: fullReport()), ControllerInputState())
    }

    func testNintendoFullReportLearnsItsOwnRestAndReach() throws {
        var decoder = NintendoHIDInput()
        _ = decoder.decode(reportID: 0x3f, bytes: report())
        XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: fullReport(lx: 1700, ly: 1700))?.leftStick, .zero)
        XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: fullReport(lx: 1843, ly: 1700))?.leftStick, .zero)
        let diagonal = try XCTUnwrap(decoder.decode(reportID: 0x30, bytes: fullReport(lx: 1843, ly: 1843)))
        XCTAssertEqual(diagonal.leftStick.x, 0.0440, accuracy: 0.001)
        XCTAssertEqual(diagonal.leftStick.x, diagonal.leftStick.y)
        XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: fullReport(lx: 3700, ly: 1700))?.leftStick.x, 1)
        XCTAssertEqual(decoder.decode(reportID: 0x30, bytes: fullReport(lx: 3500, ly: 1700))?.leftStick.x, 1)
        let halfReach = try XCTUnwrap(decoder.decode(reportID: 0x30, bytes: fullReport(lx: 2700, ly: 1700)))
        XCTAssertEqual(halfReach.leftStick.x, 0.48718, accuracy: 0.0002)
        let otherSide = try XCTUnwrap(decoder.decode(reportID: 0x30, bytes: fullReport(lx: 1100, ly: 1700)))
        XCTAssertEqual(otherSide.leftStick.x, -0.48718, accuracy: 0.0002)
    }

    func testGCClaimWaitsTwoSecondsAndMatchingGCTakesOverEvenLater() {
        var pad = ControllerArbitration.HID(name: "Lic Pro Controller", claimedByGC: true, connectedAt: 10)
        XCTAssertEqual(pad.admission(gcNames: [], at: 11.99), .wait(until: 12))
        var early = pad
        XCTAssertEqual(early.admission(gcNames: ["Lic Pro Controller"], at: 10.5), .gameController)
        XCTAssertEqual(early.admission(gcNames: [], at: 10.6), .hid)
        XCTAssertEqual(pad.admission(gcNames: ["Other gamepad"], at: 12), .hid)
        XCTAssertEqual(pad.admission(gcNames: ["lic pro controller"], at: 13), .gameController)
        XCTAssertEqual(pad.admission(gcNames: [], at: 14), .hid)
        var unclaimed = ControllerArbitration.HID(name: "Pad", claimedByGC: false, connectedAt: 10)
        XCTAssertEqual(unclaimed.admission(gcNames: [], at: 10), .hid)
        XCTAssertEqual(ControllerArbitration.preferred(hasGameController: true, hasHID: true), .gameController)
        XCTAssertEqual(ControllerArbitration.preferred(hasGameController: false, hasHID: true), .hid)
        XCTAssertNil(ControllerArbitration.preferred(hasGameController: false, hasHID: false))
    }

    private func report(buttons: UInt16 = 0, hat: UInt8 = 8, lx: UInt16 = 32_768, ly: UInt16 = 32_768,
                        rx: UInt16 = 32_768, ry: UInt16 = 32_768) -> [UInt8] {
        [UInt8(truncatingIfNeeded: buttons), UInt8(buttons >> 8), hat] +
            [lx, ly, rx, ry].flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] }
    }

    private func fullReport(buttons: [UInt8] = [0, 0, 0], lx: UInt16 = 2048, ly: UInt16 = 2048,
                            rx: UInt16 = 2048, ry: UInt16 = 2048) -> [UInt8] {
        func packed(_ x: UInt16, _ y: UInt16) -> [UInt8] {
            [UInt8(truncatingIfNeeded: x), UInt8(x >> 8 | (y & 0xf) << 4), UInt8(y >> 4)]
        }
        // The timer can have the same value as the report ID. Vibration and IMU bytes are unused.
        return [0x30, 0x8e] + buttons + packed(lx, ly) + packed(rx, ry) + Array(repeating: 0xff, count: 37)
    }
}
