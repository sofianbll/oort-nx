import XCTest
@testable import OortLibrary

final class OnScreenKeyboardTests: XCTestCase {
    func testEveryPageHasTenWideRowsAndTheSameLastOne() {
        var keyboard = OnScreenKeyboard()
        var typed: Set<String> = []
        for _ in OnScreenKeyboard.Page.allCases {
            XCTAssertEqual(keyboard.rows.map(\.count), [10, 10, 10, 9, 5])
            XCTAssertEqual(keyboard.rows.last, [.shift, .page, .space, .erase, .done])
            let letters = keyboard.rows.dropLast().joined().compactMap { keyboard.text($0) }
            XCTAssertEqual(Set(letters).count, letters.count, "\(keyboard.page) repeats a key")
            typed.formUnion(letters)
            keyboard.turnPage()
        }
        XCTAssertEqual(keyboard.page, .letters)
        // A link, a key, a mail address, a date and a name in each language can be written.
        for text in ["https://gamebanana.com/mods/1?a=b&c", "a1b2_c3-d4", "moi@exemple.fr", "2026-11-25", "sw-0000-0000-0000",
                     "élodie", "straße", "niño", "perché", "ação", "lætitia"] {
            for letter in text { XCTAssertTrue(typed.contains(String(letter)), "\(letter) in \(text)") }
        }
        let last = keyboard.rows[4].reduce(0) { $0 + OnScreenKeyboard.width($1) } + 4 * OnScreenKeyboard.gap
        XCTAssertEqual(last, OnScreenKeyboard.width)
    }

    func testShiftTypesCapitalsUntilItIsPressedAgain() {
        var keyboard = OnScreenKeyboard()
        XCTAssertEqual(keyboard.text(.text("Q")), "q")
        keyboard.toggleShift()
        XCTAssertEqual(keyboard.text(.text("Q")), "Q")
        XCTAssertEqual(keyboard.text(.space), " ")
        XCTAssertNil(keyboard.text(.done))
        keyboard.toggleShift()
        XCTAssertEqual(keyboard.text(.text("É")), "é")
    }

    func testTheFocusFollowsTheKeysUnderIt() {
        var keyboard = OnScreenKeyboard()
        XCTAssertEqual(keyboard.focused, .text("Q"))
        XCTAssertFalse(keyboard.move(.left))
        XCTAssertTrue(keyboard.move(.up))
        XCTAssertEqual(keyboard.focused, .text("1"))
        XCTAssertFalse(keyboard.move(.up))
        for _ in 0..<4 { keyboard.move(.down) }
        XCTAssertEqual(keyboard.focused, .shift)
        XCTAssertFalse(keyboard.move(.down))
        for _ in 0..<4 { XCTAssertTrue(keyboard.move(.right)) }
        XCTAssertEqual(keyboard.focused, .done)
        XCTAssertFalse(keyboard.move(.right))
        keyboard.move(.up)
        XCTAssertEqual(keyboard.focused, .text("."))
        keyboard.focus(.text("G"))
        XCTAssertEqual(keyboard.focused, .text("G"))
        keyboard.move(.down)
        XCTAssertTrue([.text("V"), .text("B")].contains(keyboard.focused))
    }

    func testTurningThePageKeepsTheFocusOnAKey() {
        var keyboard = OnScreenKeyboard()
        keyboard.focus(.page)
        for _ in 0..<7 {
            keyboard.turnPage()
            XCTAssertEqual(keyboard.focused, .page)
        }
        keyboard.turnPage(-1)
        XCTAssertEqual(keyboard.page, .letters)
        XCTAssertEqual(keyboard.nextPage, .symbols)
    }
}
