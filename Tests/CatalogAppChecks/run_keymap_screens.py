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
        print("Verified every hint token and rendered four Selene help bars without a window.")
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
