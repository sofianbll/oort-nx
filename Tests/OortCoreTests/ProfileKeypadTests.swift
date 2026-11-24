import XCTest
@testable import OortCore

final class ProfileKeypadTests: XCTestCase {
    func testNavigationStopsAtEdgesAndReachesAllBottomKeys() {
        var keypad = ProfileKeypad(pinLength: 4)
        keypad.move(.left)
        keypad.move(.up)
        XCTAssertEqual(keypad.selected, .digit(1))
        keypad.move(.right)
        keypad.move(.right)
        keypad.move(.right)
        XCTAssertEqual(keypad.selected, .digit(3))
        for _ in 0..<3 { keypad.move(.down) }
        XCTAssertEqual(keypad.selected, .validate)
        keypad.move(.right)
        keypad.move(.down)
        XCTAssertEqual(keypad.selected, .validate)
        keypad.move(.left)
        keypad.move(.down)
        XCTAssertEqual(keypad.selected, .digit(0))
        keypad.move(.left)
        keypad.move(.left)
        XCTAssertEqual(keypad.selected, .erase)
        keypad.move(.up)
        XCTAssertEqual(keypad.selected, .digit(7))
    }

    func testEraseAndValidateExactlyFourDigitsIncludingLeadingZero() {
        var keypad = ProfileKeypad(pinLength: 4)
        XCTAssertNil(keypad.press(.erase))
        XCTAssertFalse(keypad.canValidate)
        XCTAssertNil(keypad.press(.validate))
        XCTAssertNil(keypad.press(.digit(0)))
        XCTAssertNil(keypad.press(.digit(1)))
        XCTAssertNil(keypad.press(.erase))
        XCTAssertNil(keypad.press(.digit(-1)))
        XCTAssertNil(keypad.press(.digit(10)))
        XCTAssertEqual(keypad.count, 1)
        XCTAssertNil(keypad.press(.digit(2)))
        XCTAssertNil(keypad.press(.digit(3)))
        XCTAssertNil(keypad.press(.digit(4)))
        XCTAssertTrue(keypad.canValidate)
        XCTAssertNil(keypad.press(.digit(5)))
        XCTAssertEqual(keypad.press(.validate), "0234")
        XCTAssertEqual(keypad.count, 0)
        XCTAssertFalse(keypad.canValidate)
        XCTAssertNil(keypad.press(.digit(9)))
        XCTAssertEqual(keypad.count, 1)
    }

    func testValidationUsesTheInjectedLength() {
        var keypad = ProfileKeypad(pinLength: 2)
        XCTAssertNil(keypad.press(.digit(0)))
        XCTAssertFalse(keypad.canValidate)
        XCTAssertNil(keypad.press(.digit(1)))
        XCTAssertTrue(keypad.canValidate)
        XCTAssertEqual(keypad.press(.validate), "01")
    }
}
