#!/usr/bin/env python3
"""Render the real Selene help bar with injected controller identities, without opening a window."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / ".build/debug"
VIEWS = ROOT / "Sources/NXLibrary/Views"

HOST = r'''
import AppKit
import CoreText
import SwiftUI
import NXLibraryCore

final class AppViewModel {
    var isGameOptionsOpen = false
    var profileOwnsInput = false
}
final class GameControllerService: ObservableObject {
    static let shared = GameControllerService()
    var isGamepadConnected = true
    var activeBrand = GamepadBrand.generic
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
        let font = root.appendingPathComponent("Resources/Selene/Fonts/MaterialIcons-Regular.ttf")
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
            (.zl, .jumpToStart), (.zr, .jumpToEnd), (.r3, .rightStickPress),
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
                for button in [ControllerButton.l3, .capture] {
                    precondition(layout.binding(button, browsing: browsing) == nil)
                }
            }
            for hasHome in [false, true] {
                let hints = HintItem.homeGlobals(other: "Spotlight", onOther: {}, onMenu: {}, onSearch: {},
                                                onProfiles: {}, layout: layout, hasHome: hasHome)
                let options = HintItem.browsingOptions(layout, "Options", hasHome: hasHome)
                let visible = SeleneHintsBar(left: hints).visibleLeft(style: .nintendo, connected: .nintendo) + [options]
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
        let catalogURL = root.appendingPathComponent("Sources/NXLibraryCore/Resources/Localizable.xcstrings")
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
            (nil, .generic),
        ] {
            GameControllerService.shared.activeBrand = brand ?? .generic
            GameControllerService.shared.isGamepadConnected = brand != nil
            let left = HintItem.homeGlobals(other: "Spotlight", onOther: {}, onMenu: {}, onSearch: {}, onProfiles: {})
            let right = [HintItem(.a, "Play"), HintItem(.x, "Details"), HintItem(.y, "Game options"),
                         HintItem(.rs, "Sort", hold: "Recent")]
            let bar = SeleneHintsBar(left: left, right: right)
            let active = ConnectedPad(connected: brand != nil, brand: brand ?? .generic)
            precondition(bar.visibleLeft(style: .automatic, connected: active).map(\.button)
                         == (brand == nil ? [.view, .menu, .search, .home] : [.view, .menu, .home]))
            // A chosen button style is a controller too, even with none connected: no ⌘F keycap beside View.
            precondition(bar.visibleLeft(style: .xbox, connected: .none).map(\.button) == [.view, .menu, .home])
            let buttons = (bar.visibleLeft(style: .automatic, connected: active) + right).compactMap(\.button)
            precondition(Set(buttons).count == buttons.count)
            precondition(ButtonPrompts.keyboardKey(.rs) == .text("F3"))
            precondition(left.first?.hold == "Hold: Search")
            let withoutSwitch = HintItem.homeGlobals(other: "Spotlight", onOther: nil, onMenu: {}, onSearch: {}, onProfiles: {})
            let alternateBar = SeleneHintsBar(left: withoutSwitch)
            precondition(alternateBar.visibleLeft(style: .automatic, connected: active).map(\.button)
                         == (brand == nil ? [.menu, .search, .home] : [.view, .menu, .home]))
            for style: ButtonNameStyle in [.xbox, .nintendo, .playstation] {
                precondition(ButtonPrompts.symbol(.home, style: style, connected: .none)
                    .flatMap(SelenePromptBadge.filled) != nil, "Missing Home glyph for \(style)")
            }
            let pad = active
            // Every controller token must render a glyph or a labeled keycap.
            for style in ButtonNameStyle.allCases {
                for button in PromptButton.allCases {
                    if button == .search || ButtonPrompts.usesKeyboard(style: style, connected: pad) {
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
        print("Verified both binding tables, browsing hints and every hint token; rendered four Selene help bars.")
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
        "Theme/SeleneFonts.swift", "Theme/SeleneTheme.swift",
        "Components/SeleneBottomScrim.swift", "Components/SeleneHomeChrome.swift",
        "OortUI/SeleneHintsBar.swift", "OortUI/SelenePromptBadge.swift",
    ]
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-I", BIN, swift,
                    ROOT / "Sources/NXLibrary/Models/GamepadType.swift",
                    *(VIEWS / p for p in paths), BIN / "NXLibraryCore.o", BIN / "OortCore.o", "-o", binary], check=True)
    output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else scratch / "screens"
    subprocess.run([binary, ROOT, output], check=True,
                   env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
