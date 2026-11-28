import XCTest
@testable import OortCore

final class ScreenTests: XCTestCase {
    private let back = Screen.Gesture(.init("Back"), .back)

    private func sample(initialFocus: String? = nil) -> Screen {
        let open = Screen.Gesture(.init("Open"), .open("one"))
        let question = Screen.Question(title: .init("Delete?"), message: .init("It leaves."), confirm: .init("Delete"), cancel: .init("Cancel"))
        return Screen(id: "sample", title: .init("Sample"), blocks: [
            .section("s", .init("Section"), [
                .row("one", icon: "steam", title: .init("One"), status: .init(.init("Ready"), tone: .working), on: true, a: open,
                     x: .init(.init("Turn off"), .toggle("one"))),
                .row("two", icon: nil, title: .init("Two"), a: nil),
            ], note: .init("Coming later")),
            .box("b", .init("Box"), [.text(.init("Hello")), .button("delete", .init("Delete"), a: .init(.init("Delete"), .owner("clear")), question: question)]),
        ], initialFocus: initialFocus, back: back)
    }

    func testFocusOrderIsTheFocusableNodesInDrawingOrderAndStartsOnTheFirst() {
        let screen = sample()
        XCTAssertEqual(screen.focusOrder, ["one", "two", "delete"])
        XCTAssertEqual(screen.initialFocus, "one")
        XCTAssertEqual(sample(initialFocus: "two").initialFocus, "two")
    }

    func testFocusMovesInThePublishedOrderAndFallsBackWhenItsNodeIsGone() {
        let screen = sample()
        XCTAssertEqual(screen.moved(from: "one", by: 1), "two")
        XCTAssertEqual(screen.moved(from: "delete", by: 1), "delete", "it stops at the end")
        XCTAssertEqual(screen.moved(from: "one", by: -1), "one", "and at the start")
        XCTAssertEqual(screen.focus("gone"), "one", "an identity that disappeared goes back to the initial focus")
        XCTAssertEqual(screen.focus(nil), "one")
        XCTAssertEqual(screen.moved(from: "gone", by: 1), "two")
    }

    func testGesturesAreRolesAndARefusedWhereANodeHasNone() {
        let screen = sample()
        XCTAssertEqual(screen.gesture(.a, at: "one")?.intent, .open("one"))
        XCTAssertEqual(screen.gesture(.x, at: "one")?.intent, .toggle("one"))
        XCTAssertNil(screen.gesture(.a, at: "two"), "focusable without A: A is refused")
        XCTAssertNil(screen.gesture(.x, at: "two"), "X only where a switch is drawn")
        XCTAssertEqual(screen.gesture(.b, at: "two")?.intent, .back)
    }

    func testTheBarIsBOnTheLeftThenXAndAOnTheRight() {
        let screen = sample()
        let hints = screen.hints(at: "one")
        XCTAssertEqual(hints.left.map(\.key), [.b])
        XCTAssertEqual(hints.right.map(\.key), [.x, .a])
        XCTAssertEqual(screen.hints(at: "two").right.map(\.key), [])
        XCTAssertEqual(screen.hints(at: "delete").right.map(\.key), [.a])
    }

    func testAQuestionShowsCancelFirstWithTheFocusAndItsMessageWhole() throws {
        let question = try XCTUnwrap(sample().node("delete")?.question)
        XCTAssertEqual(question.choices.map(\.role), [.cancel, .destructive])
        XCTAssertEqual(question.focus, 0)
        XCTAssertTrue(question.message.whole)
    }

    func testAScreenEncodesAndDecodesAsItIs() throws {
        let screen = sample()
        let decoded = try JSONDecoder().decode(Screen.self, from: JSONEncoder().encode(screen))
        XCTAssertEqual(decoded, screen)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Screen.Intent.owner("settings"))) as? [String: String]
        XCTAssertEqual(json, ["intent": "owner", "id": "settings"])
        XCTAssertThrowsError(try JSONDecoder().decode(Screen.Intent.self, from: Data(#"{"intent":"leave"}"#.utf8)), "no fifth intent")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(screen)) as? [String: Any])
        object["focusOrder"] = ["two", "one", "delete"]
        XCTAssertThrowsError(try JSONDecoder().decode(Screen.self, from: JSONSerialization.data(withJSONObject: object)),
                             "a published order that is not the nodes' own")
        object["focusOrder"] = nil
        object["initialFocus"] = "gone"
        XCTAssertThrowsError(try JSONDecoder().decode(Screen.self, from: JSONSerialization.data(withJSONObject: object)),
                             "an initial focus on no node")
    }

    func testTheTreeListsPiecesTextsAndFocusInOrder() throws {
        let tree = ScreenTree(sample()) { $0.key }
        XCTAssertEqual(tree.structure.pieces.map(\.piece), [.row, .dot, .switch, .row, .pill])
        XCTAssertEqual(tree.structure.pieces[1], .init(.dot, text: "Ready", tone: .working))
        XCTAssertEqual(tree.structure.focus.map(\.piece), [0, 3, 4])
        XCTAssertEqual(tree.structure.focus[0].a, .init("Open", "open one"))
        XCTAssertEqual(tree.structure.focus[2].question, ["Delete?", "It leaves.", "cancel Cancel", "destructive Delete"])
        XCTAssertEqual(tree.structure.texts.map(\.role), [.screen, .heading, .row, .status, .row, .quiet, .card, .body, .button])
        XCTAssertEqual(tree.hints[0], .init(left: ["b Back"], right: ["x Turn off", "a Open"]))
        XCTAssertEqual(tree.structure.initialFocus, 0)
    }
}
