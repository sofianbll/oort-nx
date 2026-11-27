#if DEBUG
import AppKit
import ArcanePorting
import OortLibrary
import SwiftUI

/// Presses every key and button of the palette, then draws each state without opening a window.
enum CommandPaletteProbe {
    private static let games = ["Lunar Observatory", "Forêt Étoilée", "Comet Racer", "Orbit Z-A", "Aurora Station", "Tidal Garden", "Comète Bleue"]

    @MainActor private static func model(_ locale: AppLocale, query: String = "") -> CommandPalette {
        let kinds: [PlatformKind] = [.switch2, .switch1, .steam, .mac]
        var symbols: [String: CommandPalette.Symbol] = [:]
        var items = games.enumerated().map { index, name in
            let kind = kinds[index % kinds.count]
            symbols["game:\(index)"] = .platform(kind)
            return PaletteItem(id: "game:\(index)", kind: .game, title: name, detail: L10n.text(kind.rawValue, context: locale),
                               primary: kind == .mac ? "Open" : "Play", secondary: "Options")
        }
        for action in PaletteAction.allCases { symbols[action.itemID] = .icon(action.icon) }
        items += PaletteAction.allCases.map { $0.item(in: locale) }
        items += SettingsCatalog.visible(supportsNextendo: false, hasProfileAccount: false, cloudConfigured: false).map { row in
            symbols["setting:\(row.id)"] = .icon(row.group.icon)
            return PaletteItem(id: "setting:\(row.id)", kind: .setting, title: L10n.text(row.title, context: locale),
                               detail: SettingsDescriptorList.path(row.group), section: SettingsCategory(section: row.group)?.title(in: locale),
                               aliases: [row.title], notes: [L10n.text(row.about, context: locale)])
        }
        let palette = CommandPalette()
        palette.open(query: query, items: items, recents: ["game:1", "action:theme", "setting:soundPack"],
                     suggestions: ["game:0"] + PaletteAction.suggested.map(\.itemID), symbols: symbols)
        return palette
    }

    @MainActor private static func checkInput(_ locale: AppLocale) {
        let keys: [(UInt16, NSEvent.ModifierFlags, GamepadAction?)] = [
            (125, [], .navigateDown), (126, [], .navigateUp), (48, [], .tabNext), (48, [.shift], .tabPrevious),
            (115, [], .jumpToStart), (119, [], .jumpToEnd), (36, [], .confirm), (76, [], .confirm),
            (36, [.command], .contextAction), (53, [], .cancel), (123, [], nil), (124, [], nil), (49, [], nil),
            (16, [], nil), (40, [.command], nil), (43, [.command], nil), (125, [.shift], nil),
        ]
        for (code, modifiers, action) in keys {
            precondition(CommandPalette.action(keyCode: code, modifiers: modifiers) == action, "key \(code)")
        }
        precondition(CommandPalette.action(keyCode: 125, modifiers: [.numericPad, .function]) == .navigateDown, "arrows carry flags")

        let palette = model(locale)
        var chosen: [(String, Bool)] = []
        var closed = 0
        palette.onChoose = { chosen.append(($0.id, $1)) }
        palette.onClose = { closed += 1 }
        precondition(palette.groups.map(\.id) == [.recents, .suggestions, .browse])
        precondition(palette.focusedItem?.id == "game:1")
        palette.handle(.confirm)
        palette.handle(.contextAction)
        palette.handle(.menu)
        precondition(chosen.map(\.0) == ["game:1", "game:1", "game:1"] && chosen.map(\.1) == [false, true, true])
        palette.handle(.navigateDown)
        palette.handle(.contextAction)
        precondition(chosen.count == 3, "an action has no second action")
        palette.handle(.tabNext)
        precondition(palette.focusedItem?.id == "game:0")
        palette.handle(.jumpToEnd)
        palette.handle(.navigateDown)
        precondition(palette.focusedItem == nil && palette.focusedRow != nil)
        palette.handle(.confirm)
        precondition(palette.state.scope == .setting && chosen.count == 3)
        palette.handle(.cancel)
        precondition(palette.state.scope == nil && closed == 0 && palette.state.focus == palette.rows.count - 1)
        palette.handle(.cancel)
        precondition(closed == 1)
        palette.type("comete")
        precondition(palette.focusedItem?.title == "Comète Bleue" && palette.state.focus == 0)
        palette.type("observatroy")
        precondition(palette.focusedItem?.title == "Lunar Observatory")
        palette.type("qqqqqq")
        precondition(palette.rows.isEmpty && palette.focusedRow == nil)
        let before = chosen.count
        palette.handle(.confirm)
        palette.handle(.contextAction)
        palette.handle(.navigateDown)
        precondition(chosen.count == before)
        palette.type("")
        palette.press(2)
        precondition(chosen.last?.0 == "setting:soundPack")
        palette.update(items: [], symbols: [:])
        precondition(palette.rows.isEmpty && palette.focusedRow == nil)

        let first = PaletteItem(id: "a", kind: .game, title: "Comet A")
        let second = PaletteItem(id: "b", kind: .game, title: "Comet B", secondary: "Options")
        let third = PaletteItem(id: "c", kind: .game, title: "Comet C")
        palette.open(query: "comet", items: [second, third], recents: [], suggestions: [], symbols: [:])
        palette.update(items: [first, second, third], symbols: [:])
        palette.handle(.confirm)
        precondition(chosen.last?.0 == "b", "refresh must not move activation to the new row")
        let afterRefresh = chosen.count
        palette.update(items: [first, third], symbols: [:])
        palette.handle(.confirm)
        palette.handle(.contextAction)
        precondition(chosen.count == afterRefresh && palette.focusedRow == nil, "removed focus must not activate a replacement")
        palette.handle(.navigateDown)
        palette.handle(.confirm)
        precondition(chosen.last?.0 == "a", "navigation must restore selection")
    }

    @MainActor static func capture(to output: URL) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        SeleneFonts.register()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let french = AppLocale(language: .french, region: "FR")
        L10n.setContext(french)
        checkInput(french)
        print("palette input: ok")

        func draw(_ name: String, _ locale: AppLocale, size: CGSize = CGSize(width: 1440, height: 900), zoom: CGFloat = 1,
                  names: ButtonNameStyle = .automatic, white: Bool = false, _ content: some View) throws {
            // A pad plugged into this Mac must not choose the prompts.
            GameControllerService.shared.isGamepadConnected = false
            let view = content
                .frame(width: size.width, height: size.height)
                .background { if white { Rectangle().fill(SeleneTheme.artInk) } else { Rectangle().fill(SeleneTheme.baseGradient) } }
                .environment(\.seleneCanvas, SeleneCanvas(size: size, zoom: zoom))
                .environment(\.nxAppLocale, locale)
                .environment(\.locale, locale.formatLocale)
                .environment(\.seleneButtonNames, names)
                .environment(\.seleneReduceMotion, true)
                .environment(\.seleneSharesBackdrop, true)
                .preferredColorScheme(.dark)
            try IntegrationFixtureView.captureWindow(NSHostingView(rootView: view), size: size,
                                                     to: output.appendingPathComponent(name + ".png"))
        }

        func draw(_ name: String, _ locale: AppLocale, size: CGSize = CGSize(width: 1440, height: 900), zoom: CGFloat = 1,
                  names: ButtonNameStyle = .automatic, white: Bool = false, palette: CommandPalette) throws {
            try draw(name, locale, size: size, zoom: zoom, names: names, white: white, CommandPaletteView(palette: palette))
        }

        for look in ["oort", "catppuccin-latte"] {
            ThemeStore.shared.apply(id: look)
            for (code, locale) in [("fr", french), ("en", AppLocale(language: .english, region: "US")),
                                   ("de", AppLocale(language: .german, region: "DE"))] {
                L10n.setContext(locale)
                try draw("\(look)-\(code)-empty", locale, palette: model(locale))
                try draw("\(look)-\(code)-results", locale, palette: model(locale, query: "so"))
                try draw("\(look)-\(code)-none", locale, palette: model(locale, query: "qqqqqq"))
                let actions = model(locale)
                actions.handle(.jumpToEnd)
                actions.handle(.navigateUp)
                actions.handle(.confirm)
                try draw("\(look)-\(code)-actions", locale, palette: actions)
                let settings = model(locale)
                settings.handle(.jumpToEnd)
                settings.handle(.confirm)
                (0..<9).forEach { _ in settings.handle(.navigateDown) }
                try draw("\(look)-\(code)-settings", locale, palette: settings)
            }
        }
        ThemeStore.shared.apply(id: "oort")
        L10n.setContext(french)
        try draw("oort-fr-fault", french, palette: model(french, query: "observatroy"))
        try draw("oort-fr-pad", french, names: .xbox, palette: model(french))
        try draw("oort-fr-white", french, white: true, palette: model(french, query: "son"))
        // The two other places that name the palette.
        let (app, _, _, _) = try IntegrationFixtureView.fixtureOnboardingState()
        for (suffix, names) in [("keys", ButtonNameStyle.automatic), ("pad", .xbox)] {
            try draw("oort-fr-find-\(suffix)", french, names: names,
                     FindGameView(router: AppRouter(), viewModel: app, playSessions: PlaySessionStore(), artwork: ArtworkStore()))
        }
        try draw("oort-fr-controls", french, size: CGSize(width: 1440, height: 1900), ControlsView(layout: .oort, canHandleInput: { true }) {})
        let german = AppLocale(language: .german, region: "DE")
        L10n.setContext(german)
        for zoom in [0.8, 1.25] as [CGFloat] {
            try draw("oort-de-small-\(Int(zoom * 100))", german, size: CGSize(width: 1100, height: 700), zoom: zoom,
                     palette: model(german, query: "ein"))
        }
    }
}
#endif
