import XCTest
@testable import NXLibraryCore

final class ButtonPromptsTests: XCTestCase {
    func testAutomaticFollowsPad() {
        XCTAssertEqual(ButtonPrompts.label(.lb, style: .automatic, connected: .nintendo), "L")
        XCTAssertEqual(ButtonPrompts.label(.view, style: .automatic, connected: .nintendo), "−")
        XCTAssertEqual(ButtonPrompts.label(.a, style: .automatic, connected: .playstation), "✕")
        XCTAssertEqual(ButtonPrompts.label(.lb, style: .automatic, connected: .none), "LB")
        XCTAssertEqual(ButtonPrompts.label(.lb, style: .automatic, connected: .other), "LB")
    }

    func testExplicitStyleOverridesPad() {
        XCTAssertEqual(ButtonPrompts.label(.lb, style: .xbox, connected: .nintendo), "LB")
        XCTAssertEqual(ButtonPrompts.label(.menu, style: .playstation, connected: .xbox), "Options")
    }

    func testAllButtonsHaveLabelsInAllStyles() {
        for style in ButtonNameStyle.allCases {
            for button in PromptButton.allCases {
                XCTAssertFalse(ButtonPrompts.label(button, style: style, connected: .none).isEmpty)
            }
        }
    }

    func testOldSettingsDecodeToAutomaticButtonNames() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.buttonNames, .automatic)
    }

    func testAutomaticWithoutControllerKeepsTextLabels() {
        XCTAssertNil(ButtonPrompts.symbol(.a, style: .automatic, connected: .none))
    }

    func testAutomaticPrefersWhatTheControllerReports() {
        let symbol = ButtonPrompts.symbol(.a, style: .automatic, connected: .nintendo,
                                          reported: [.a: "a.circle"])
        XCTAssertEqual(symbol, "a.circle")
    }

    func testAutomaticIgnoresGenericReportedGlyphs() {
        let viewSym = ButtonPrompts.symbol(.view, style: .automatic, connected: .playstation,
                                           reported: [.view: "circle"])
        XCTAssertNil(viewSym)

        let menuSym = ButtonPrompts.symbol(.menu, style: .automatic, connected: .playstation,
                                           reported: [.menu: "circle.fill"])
        XCTAssertNil(menuSym)
    }

    func testStickClickIsNeverTheBareRShoulderGlyph() {
        let shoulders = Set([PromptButton.lb, .rb].flatMap { button in
            [ButtonNameStyle.nintendo, .xbox, .playstation].compactMap { ButtonPrompts.symbol(button, style: $0, connected: .none) }
        })
        for style in [ButtonNameStyle.nintendo, .xbox, .playstation] {
            let symbol = ButtonPrompts.symbol(.rs, style: style, connected: .none)
            XCTAssertNotNil(symbol)
            XCTAssertFalse(symbol!.hasPrefix("r.joystick"), "\(style)")
            XCTAssertFalse(shoulders.contains(symbol!), "\(style)")
        }
        XCTAssertEqual(ButtonPrompts.symbol(.rs, style: .xbox, connected: .none), "rsb.button.angledbottom.horizontal.right")
        XCTAssertEqual(ButtonPrompts.symbol(.rs, style: .playstation, connected: .none), "r3.button.angledbottom.horizontal.right")
        // A pad that reports the bare "R" stick disc gets its family's glyph instead.
        XCTAssertEqual(ButtonPrompts.symbol(.rs, style: .automatic, connected: .xbox,
                                            reported: [.rs: "r.joystick.press.down"]),
                       "rsb.button.angledbottom.horizontal.right")
    }

    func testGenericShapeDetection() {
        XCTAssertTrue(ButtonPrompts.isGenericShape("circle"))
        XCTAssertTrue(ButtonPrompts.isGenericShape("circle.fill"))
        XCTAssertTrue(ButtonPrompts.isGenericShape("capsule"))
        XCTAssertTrue(ButtonPrompts.isGenericShape("square"))
        XCTAssertFalse(ButtonPrompts.isGenericShape("xmark.circle"))
        XCTAssertFalse(ButtonPrompts.isGenericShape("square.and.arrow.up.circle"))
        XCTAssertFalse(ButtonPrompts.isGenericShape("line.3.horizontal.circle"))
    }

    func testAutomaticPlayStationRejectsDecoratedShapePlaceholders() {
        for name in ["capsule.portrait", "capsule.portrait.fill", "oval.portrait.fill",
                     "rectangle.portrait.fill", "rectangle.roundedtop.fill", "button.horizontal.fill"] {
            XCTAssertTrue(ButtonPrompts.isGenericShape(name), name)
            XCTAssertNil(ButtonPrompts.symbol(.view, style: .automatic, connected: .playstation,
                                             reported: [.view: name]), name)
            XCTAssertNil(ButtonPrompts.symbol(.menu, style: .automatic, connected: .playstation,
                                             reported: [.menu: name]), name)
        }
        XCTAssertEqual(ButtonPrompts.symbol(.view, style: .automatic, connected: .xbox,
                                           reported: [.view: "capsule.portrait"]), "rectangle.on.rectangle.circle")
        XCTAssertEqual(ButtonPrompts.symbol(.menu, style: .automatic, connected: .nintendo,
                                           reported: [.menu: "button.horizontal.fill"]), "plus.circle")
    }

    func testGeometricFaceButtonsAndMeaningfulReportedGlyphsArePreserved() {
        for name in ["circle.circle", "circle.circle.fill", "square.circle", "square.circle.fill",
                     "rectangle.on.rectangle.circle", "square.and.arrow.up.circle.fill",
                     "l1.rectangle.roundedbottom", "triangle.circle.fill"] {
            XCTAssertFalse(ButtonPrompts.isGenericShape(name), name)
            XCTAssertEqual(ButtonPrompts.symbol(.a, style: .automatic, connected: .playstation,
                                               reported: [.a: name]), name)
        }
    }

    func testAutomaticFallsBackToTheBrandTable() {
        XCTAssertEqual(ButtonPrompts.symbol(.a, style: .automatic, connected: .playstation), "xmark.circle")
        XCTAssertEqual(ButtonPrompts.symbol(.lt, style: .automatic, connected: .nintendo), "zl.rectangle.roundedtop")
        XCTAssertEqual(ButtonPrompts.symbol(.menu, style: .automatic, connected: .other), "line.3.horizontal.circle")
    }

    func testChosenStyleIgnoresTheReportedGlyph() {
        let symbol = ButtonPrompts.symbol(.b, style: .playstation, connected: .xbox,
                                          reported: [.b: "b.circle"])
        XCTAssertEqual(symbol, "circle.circle")
    }

    func testEveryButtonHasASymbolInEveryStyle() {
        for style in ButtonNameStyle.allCases where style != .automatic {
            for button in PromptButton.allCases where button != .search
                && (style != .playstation || (button != .view && button != .menu)) {
                XCTAssertNotNil(ButtonPrompts.symbol(button, style: style, connected: .none))
            }
        }
    }

    func testNoControllerShowsKeyboardKeys() {
        XCTAssertTrue(ButtonPrompts.usesKeyboard(.none))
        for pad: ConnectedPad in [.nintendo, .xbox, .playstation, .other] { XCTAssertFalse(ButtonPrompts.usesKeyboard(pad)) }
        XCTAssertEqual(ButtonPrompts.keyboardKey(.a), .symbol("return"))
        XCTAssertEqual(ButtonPrompts.keyboardKey(.b), .text("esc"))
        XCTAssertEqual(ButtonPrompts.keyboardKey(.view), .text("V"))
        XCTAssertEqual(ButtonPrompts.keyboardKey(.rb), .text("E"))
        XCTAssertEqual(ButtonPrompts.keyboardKey(.rs), .text("F3"))
        XCTAssertEqual(ButtonPrompts.keyboardKey(.search), .text("⌘F"))
    }

    func testFaceAndMenuLabelsByFamily() {
        let buttons: [PromptButton] = [.a, .b, .x, .y, .lb, .rb, .lt, .rt, .view, .menu]
        let families: [(ConnectedPad, [String])] = [
            (.xbox, ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "View", "Menu"]),
            (.nintendo, ["A", "B", "X", "Y", "L", "R", "ZL", "ZR", "−", "+"]),
            (.playstation, ["✕", "○", "□", "△", "L1", "R1", "L2", "R2", L10n.text("Touchpad"), "Options"]),
        ]
        for (pad, expected) in families {
            XCTAssertEqual(buttons.map { ButtonPrompts.label($0, style: .automatic, connected: pad) }, expected)
        }
    }

    func testGenericControllerUsesXboxGlyphs() {
        XCTAssertEqual(ButtonPrompts.symbol(.lb, style: .automatic, connected: .other), "lb.rectangle.roundedbottom")
    }

    func testNoKeyboardKeyShowsWhileAControllerIsActive() {
        let pads: [ConnectedPad] = [.nintendo, .xbox, .playstation, .other, .none]
        for pad in pads {
            let active = !ButtonPrompts.usesKeyboard(pad)
            for controllerOnly in [false, true] {
                // ⌘F is the keyboard's search: a controller holds View for it instead.
                XCTAssertEqual(ButtonPrompts.showsHint(.search, controllerOnly: controllerOnly, inHand: pad),
                               !active && !controllerOnly, "\(pad)")
                XCTAssertEqual(ButtonPrompts.showsHint(.view, controllerOnly: controllerOnly, inHand: pad),
                               active || !controllerOnly, "\(pad)")
            }
        }
    }
}
