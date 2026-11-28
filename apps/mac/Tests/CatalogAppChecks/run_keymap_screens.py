#!/usr/bin/env python3
"""Render the real Selene help bar with injected controller identities, without opening a window."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "scripts"))
import names  # noqa: E402  architecture/names.json
import probe_start  # noqa: E402  every probe that links the core starts in ProbeStart.swift
BIN = ROOT / ".build/debug"
VIEWS = ROOT / "apps/mac/OortMac/Views"

HOST = r'''
import AppKit
import CoreText
import SwiftUI
import OortLibrary

final class AppViewModel {
    var isGameOptionsOpen = false
    var profileOwnsInput = false
}
final class GameControllerService: ObservableObject {
    static let shared = GameControllerService()
    var isGamepadConnected = true
    var activeBrand = GamepadBrand.generic
    var usesController = true
    var pointerInHand: Bool { !usesController }
    var padInHand: ConnectedPad { ConnectedPad(connected: isGamepadConnected && usesController, brand: activeBrand) }
    var buttonSymbols: [PromptButton: String] = [:]
}
final class ThemeStore {
    static let shared = ThemeStore()
    let palette = SelenePalette.fallback
}

@main struct KeymapScreens {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let font = root.appendingPathComponent("design/Selene/Fonts/MaterialIcons-Regular.ttf")
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        let locale = AppLocale(language: .french, region: "FR")
        L10n.setContext(locale)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let expected: [(GamepadLayout, Bool, ControllerButton, GamepadAction, GamepadAction?)] = [
            (.arcane, true, .home, .profiles, nil), (.arcane, true, .menu, .menu, .menuHold),
            (.arcane, true, .y, .contextAction, nil), (.arcane, true, .view, .view, .search),
            (.oort, true, .home, .controlCenter, .fullMenu), (.oort, true, .menu, .contextAction, .controlCenter),
            (.oort, true, .y, .browseSearch, nil), (.oort, true, .view, .view, .browseSearch),
            (.oort, false, .menu, .menu, .menuHold), (.oort, false, .y, .contextAction, nil),
            (.oort, false, .home, .controlCenter, .fullMenu),
        ]
        for (layout, browsing, button, tap, hold) in expected {
            let binding = layout.binding(button, browsing: browsing)
            precondition(binding?.tap == tap && binding?.hold == hold)
        }
        precondition(GamepadLayout(AppSettings()) == .oort)
        let oldSettings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        precondition(GamepadLayout(oldSettings) == .arcane)
        precondition(GamepadLayout.oort.gameHome(.auto) == .quickAccess)
        precondition(GamepadLayout.arcane.gameHome(.auto) == .auto)
        for layout in GamepadLayout.allCases {
            precondition(layout.gameHome(.fullOverlay) == .fullOverlay && layout.gameHome(.quickAccess) == .quickAccess)
        }
        let common: [(ControllerButton, GamepadAction)] = [
            (.up, .navigateUp), (.down, .navigateDown), (.left, .navigateLeft), (.right, .navigateRight),
            (.a, .confirm), (.b, .cancel), (.x, .secondaryAction), (.l, .tabPrevious), (.r, .tabNext),
            (.zl, .jumpToStart), (.zr, .jumpToEnd), (.r3, .rightStickPress), (.l3, .search),
        ]
        let document = try String(contentsOf: root.appendingPathComponent("docs/how-it-works/keymap.md"),
                                  encoding: .utf8)
        let docsTable = document.components(separatedBy: "<!-- gamepad-layouts -->")[1]
            .components(separatedBy: "<!-- /gamepad-layouts -->")[0]
        let docsActions: [GamepadAction: String] = [
            .menu: "Centro di controllo", .menuHold: "Settings", .profiles: "Profili",
            .contextAction: "Opzioni dell'elemento", .controlCenter: "Centro di controllo", .fullMenu: "Settings",
            .search: "Cerca", .browseSearch: "Cerca", .view: "Cambia vista"
        ]
        let documentedButtons: [(ControllerButton, String)] = [(.home, "Home"), (.menu, "+"), (.y, "Y"), (.view, "−")]
        for layout in GamepadLayout.allCases {
            for (button, name) in documentedButtons {
                let binding = layout.binding(button, browsing: true)!
                let title = docsActions[binding.tap]!
                let note = button == .home && binding.tap == .controlCenter ? " (apre/chiude)" : ""
                let hold = binding.hold.flatMap { docsActions[$0] } ?? "—"
                precondition(docsTable.contains("| \(layout.title) | Libreria | \(name) | \(title)\(note) | \(hold) |"))
            }
            for browsing in [false, true] {
                for (button, action) in common {
                    precondition(layout.binding(button, browsing: browsing)?.tap == action)
                }
                for button in [ControllerButton.capture] {
                    precondition(layout.binding(button, browsing: browsing) == nil)
                }
            }
            for hasHome in [false, true] {
                let hints = HintItem.homeGlobals(other: "Spotlight", onOther: {}, onMenu: {}, onSearch: {},
                                                onProfiles: {}, layout: layout, hasHome: hasHome)
                let options = HintItem.browsingOptions(layout, "Options", hasHome: hasHome)
                let visible = SeleneHintsBar(left: hints).visibleLeft(inHand: .nintendo) + [options]
                let buttons = visible.compactMap(\.button)
                precondition(Set(buttons).count == buttons.count)
                let rows = layout.guide(hasHome: hasHome)
                precondition(buttons.allSatisfy { button in rows.contains { $0.prompt == button } })
                precondition(options.button == rows.first { $0.tap == .contextAction }?.prompt)
                for hint in visible where hint.hold != nil {
                    precondition(rows.contains { $0.prompt == hint.button && $0.hold != nil })
                }
                precondition(hasHome || !buttons.contains(.home))
                if layout == .oort && !hasHome { precondition(options.hold == "Hold: Control center") }
            }
        }
        let catalogURL = root.appendingPathComponent("core/OortLibrary/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as! [String: Any]
        let strings = catalog["strings"] as! [String: [String: Any]]
        let languages = Set(["en", "fr", "de", "es", "it", "pt-BR", "zh-Hans"])
        for key in Set(GamepadLayout.allCases.flatMap { $0.guide().flatMap { [$0.tap.guideTitle, $0.hold?.guideTitle].compactMap { $0 } } })
            .union(["Controller layout", "While browsing", "Home Button Overrides", "Hold: %@", "Hold: Close",
                    "Hold: Control center", "Home opens the Apple overlay", "Give it to Oort", "Keep Apple"]) {
            let localizations = strings[key]?["localizations"] as? [String: Any] ?? [:]
            precondition(languages.isSubset(of: Set(localizations.keys)), "Untranslated controller string: \(key)")
        }
        for (name, brand): (String?, GamepadBrand?) in [
            ("xbox", .xbox), ("switch", .nintendoSwitch), ("ps5", .playstation), ("keyboard", nil),
            ("xbox-then-keyboard", .xbox), (nil, .generic),
        ] {
            GameControllerService.shared.activeBrand = brand ?? .generic
            GameControllerService.shared.isGamepadConnected = brand != nil
            GameControllerService.shared.usesController = name != "xbox-then-keyboard"
            let left = HintItem.homeGlobals(other: "Spotlight", onOther: {}, onMenu: {}, onSearch: {}, onProfiles: {})
            let right = [HintItem(.a, "Play"), HintItem(.x, "Details"), HintItem(.y, "Game options"),
                         HintItem(.rs, "Sort", hold: "Recent")]
            let bar = SeleneHintsBar(left: left, right: right)
            let active = GameControllerService.shared.padInHand
            precondition(bar.visibleLeft(inHand: active).map(\.button)
                         == (active == .none ? [.view, .menu, .search, .home] : [.view, .menu, .home]))
            // A chosen button style names a controller's buttons: the keyboard keeps its keys whatever the style.
            precondition(bar.visibleLeft(inHand: .none).map(\.button) == [.view, .menu, .search, .home])
            // Every hint the screen can press takes a click: its own action first, else its button's.
            var pressed: [GamepadAction] = []
            let clickable = SeleneHintsBar(left: left, right: right, press: { pressed.append($0) })
            for hint in right { clickable.clickAction(hint)?() }
            precondition(pressed == [.confirm, .secondaryAction, .contextAction, .rightStickPress])
            precondition(left.allSatisfy { clickable.clickAction($0) != nil })
            precondition(clickable.clickAction(HintItem(.move, "Move")) == nil)
            let options = HintItem.browsingOptions(.oort, "Card options", hasHome: true)
            precondition(options.action == nil && options.button == .menu)
            clickable.clickAction(options)?()
            precondition(pressed.last == .contextAction, "The + of the Oort layout opens the card's options")
            precondition(SeleneHintsBar(right: right).clickAction(right[0]) == nil)
            let back = HintItem(.b, "Back") {}
            precondition(SeleneHintsBar.mouseBack(left: [], right: right + [back], pointer: true)?.label == "Back")
            precondition(SeleneHintsBar.mouseBack(left: [back], right: right, pointer: false) == nil)
            precondition(SeleneHintsBar.mouseBack(left: [], right: right, pointer: true) == nil)
            let buttons = (bar.visibleLeft(inHand: active) + right).compactMap(\.button)
            precondition(Set(buttons).count == buttons.count)
            precondition(ButtonPrompts.keyboardKey(.rs) == .text("S"))
            precondition(left.first?.hold == "Hold: Search")
            let withoutSwitch = HintItem.homeGlobals(other: "Spotlight", onOther: nil, onMenu: {}, onSearch: {}, onProfiles: {})
            let alternateBar = SeleneHintsBar(left: withoutSwitch)
            precondition(alternateBar.visibleLeft(inHand: active).map(\.button)
                         == (active == .none ? [.menu, .search, .home] : [.view, .menu, .home]))
            for style: ButtonNameStyle in [.xbox, .nintendo, .playstation] {
                precondition(ButtonPrompts.symbol(.home, style: style, connected: .none)
                    .flatMap(SelenePromptBadge.filled) != nil, "Missing Home glyph for \(style)")
            }
            let pad = active
            // Every controller token must render a glyph or a labeled keycap.
            for style in ButtonNameStyle.allCases {
                for button in PromptButton.allCases {
                    if button == .search || ButtonPrompts.usesKeyboard(pad) {
                        switch ButtonPrompts.keyboardKey(button) {
                        case .symbol(let symbol):
                            precondition(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
                        case .text(let text): precondition(!text.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else if ButtonPrompts.symbol(button, style: style, connected: pad)
                        .flatMap(SelenePromptBadge.filled) == nil {
                        precondition(!ButtonPrompts.label(button, style: style, connected: pad)
                            .trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            guard let name else { continue }
            let view = ZStack(alignment: .bottom) {
                Rectangle().fill(SeleneTheme.baseGradient)
                SeleneBottomScrim()
                bar
            }.frame(width: 1344, height: 756)
                .environment(\.seleneCanvas, SeleneCanvas(size: .init(width: 1344, height: 756)))
                .environment(\.nxAppLocale, locale)
                .frame(height: 160, alignment: .bottom)
                .clipped()
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { fatalError("Could not render \(name)") }
            try png.write(to: output.appendingPathComponent("\(name).png"))
        }
        // A right click reaches the options layer; a left click goes through it to the tile.
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
        var opened = 0
        let tile = NSHostingView(rootView: Rectangle().frame(width: 100, height: 100).oortSecondaryClick { opened += 1 }
            .environment(\.oortLivePointer, true))
        tile.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let window = NSWindow(contentRect: tile.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = tile
        tile.layoutSubtreeIfNeeded()
        for (type, flags, expected) in [(NSEvent.EventType.leftMouseDown, NSEvent.ModifierFlags(), 0),
                                        (.rightMouseDown, [], 1), (.leftMouseDown, .control, 2)] {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 50, y: 50), modifierFlags: flags, timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            NSApp.postEvent(event, atStart: true)
            let current = NSApp.nextEvent(matching: [.leftMouseDown, .rightMouseDown], until: Date().addingTimeInterval(1),
                                          inMode: .default, dequeue: true)!
            if let hit = tile.hitTest(NSPoint(x: 50, y: 50)) as? SecondaryClickView {
                if type == .rightMouseDown { hit.rightMouseDown(with: current) } else { hit.mouseDown(with: current) }
            }
            precondition(opened == expected, "\(type) opened \(opened)")
        }
        print("Verified both binding tables, browsing hints and every hint token; rendered five Selene help bars.")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="keymap-screens-") as folder:
    scratch = Path(folder)
    swift = scratch / "check.swift"
    swift.write_text(HOST)
    binary = scratch / "check"
    paths = [
        "Theme/AppLocaleEnvironment.swift", "Theme/SeleneCanvasEnvironment.swift",
        "Theme/SeleneFonts.swift", "Theme/SeleneTheme.swift", "Theme/Motion.swift",
        "Components/SeleneBottomScrim.swift", "Components/SeleneHomeChrome.swift",
        "OortUI/SeleneHintsBar.swift", "OortUI/ScreenTrace.swift", "OortUI/SelenePromptBadge.swift", "OortUI/OortSecondaryClick.swift",
    ]
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-I", BIN, swift,
                    ROOT / "apps/mac/OortMac/Models/GamepadType.swift",
                    *(VIEWS / p for p in paths), *probe_start.core(BIN, ("library", "core")), "-o", binary], check=True)
    output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else scratch / "screens"
    subprocess.run([binary, ROOT, output], check=True,
                   env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
