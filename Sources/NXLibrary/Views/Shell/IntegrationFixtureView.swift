#if DEBUG
import AppKit
import SwiftUI
import NXLibraryCore
import ArcanePorting

/// No startup importer, app model, network client or real Play command is mounted in the fixture.
struct IntegrationFixtureView: View {
    @StateObject private var router = AppRouter()
    @State private var sample = 0
    @State private var french = ProcessInfo.processInfo.arguments.contains("--fixture-fr")
    @State private var onboarding = false
    @State private var steamOn = false
    @State private var setupFocus = FirstRunSetup.Focus.initialOnFound
    @State private var profileFocused = false

    static let steam: [CatalogSourceStatus] = [.disabled, .idle, .scanning, .ready, .partial, .cancelled, .failed]
    static let sampleCount = IntegrationOverview.Drive.allCases.count + 1

    static func example(_ index: Int) -> IntegrationOverview {
        var data = IntegrationOverview()
        if index == 0 {
            data.engine = .detected
            data.steam = .ready
            data.drive = .transferring
            data.nextendo = .unavailable
            data.steamGridDB = true
            data.igdb = true
            data.saves = .iCloudDrive
        } else {
            data.engine = IntegrationOverview.Engine.allCases[index % IntegrationOverview.Engine.allCases.count]
            data.steam = steam[index % steam.count]
            data.steamGameCount = 3
            data.drive = IntegrationOverview.Drive.allCases[index % IntegrationOverview.Drive.allCases.count]
            data.nextendo = IntegrationOverview.Account.allCases[index % IntegrationOverview.Account.allCases.count]
            data.steamGridDB = index & 1 != 0
            data.igdb = index & 2 != 0
            if index.isMultiple(of: 3) { data.saves = .folder("/fixture/saves") }
        }
        return data
    }

    private var locale: AppLocale { french ? .init(language: .french, region: "FR") : .init(language: .english, region: "US") }

    var body: some View {
        let data = Self.example(sample)
        ZStack(alignment: .topTrailing) {
            Group {
                if onboarding {
                    FoundGamesSetupContent(findings: .init(steamGameCount: 2, portedAppCount: 0),
                        steamOn: steamOn, focus: setupFocus, move: { setupFocus = $0 }, activate: setup)
                } else {
                    switch router.route {
                    case .integrations: IntegrationsView(overview: data, router: router)
                    case .settings(let section):
                        VStack(spacing: 12) {
                            Text(L10n.text(section.title, context: locale)).font(.title)
                            Text(L10n.text(SettingsCatalog.all.first { $0.id == router.settingsRowID }?.title ?? "", context: locale))
                            Text("Fixture · no settings or service is opened").foregroundStyle(.secondary)
                            Button(L10n.text("Back", context: locale), action: router.back)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(SeleneBackdrop(still: true))
                    default: Self.home(data, router: router)
                    }
                }
            }
            HStack {
                Button(french ? "EN" : "FR") { french.toggle() }
                Button("Fixture \(sample + 1)/\(Self.sampleCount)") { sample = (sample + 1) % Self.sampleCount }
                Button(onboarding ? "Home" : "Onboarding") { onboarding.toggle() }
            }
            .buttonStyle(.bordered)
            .padding(.trailing, 18)
            .padding(.top, 24)
        }
        .environment(\.nxAppLocale, locale)
        .environment(\.locale, locale.formatLocale)
        .environment(\.seleneReduceMotion, true)
        .environment(\.seleneBackdropStyle, .init(palette: ThemeStore.shared.palette, animated: false))
        .environment(\.colorScheme, .dark)
        .seleneCanvasRoot()
        .onChange(of: locale, initial: true) { L10n.setContext(locale) }
        .onAppear { GameControllerService.shared.onAction = input }
        .onDisappear { GameControllerService.shared.onAction = nil }
        .focusable()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .space, .escape]) { key in
            switch key.key {
            case .upArrow: input(.navigateUp)
            case .downArrow: input(.navigateDown)
            case .leftArrow: input(.navigateLeft)
            case .rightArrow: input(.navigateRight)
            case .escape: input(.cancel)
            default: input(.confirm)
            }
            return .handled
        }
    }

    private func setup(_ choice: FirstRunSetup.Focus) {
        setupFocus = choice
        if choice == .steamToggle { steamOn.toggle() }
        if choice == .openLibrary { onboarding = false }
    }

    private func input(_ action: GamepadAction) {
        if onboarding {
            switch action {
            case .navigateUp: setupFocus = setupFocus.movedOnFound(.up, hasSteam: true)
            case .navigateDown: setupFocus = setupFocus.movedOnFound(.down, hasSteam: true)
            case .confirm: setup(setupFocus)
            case .cancel: onboarding = false
            default: break
            }
            return
        }
        let data = Self.example(sample)
        switch router.route {
        case .integrations: IntegrationsView(overview: data, router: router).handle(action)
        case .settings: if action == .cancel { router.back() }
        default: _ = router.handleIntegrationBar(action, profileFocused: &profileFocused, hasProfile: false)
        }
    }

    static func home(_ data: IntegrationOverview, router: AppRouter) -> some View {
        IntegrationFixtureHome(data: data, router: router)
    }

    @MainActor static func capture(to output: URL, soundOnly: Bool = false) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        SeleneFonts.register()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let router = AppRouter()
        let data = example(0)
        for (language, region) in [(AppLanguage.english, "US"), (.french, "FR")] {
            let locale = AppLocale(language: language, region: region)
            L10n.setContext(locale)
            for (name, size) in [("wide", CGSize(width: 1440, height: 900)), ("narrow", CGSize(width: 780, height: 740))] {
                let canvas = SeleneCanvas(size: size)
                let prefix = "\(language.rawValue)-\(name)"
                func render<V: View>(_ view: V, as suffix: String, height: CGFloat = size.height) throws {
                    let palette = ThemeStore.shared.palette
                    let host = NSHostingView(rootView: view
                        .frame(width: size.width, height: height)
                        .environment(\.seleneSharesBackdrop, true)
                        .background {
                            ZStack {
                                Color(hex: palette.scrim)
                                Rectangle().fill(SeleneTheme.baseGradient(for: palette)).opacity(0.6)
                                MoonlightBackdrop(accent: SeleneTheme.glyph, ink: SeleneTheme.ink,
                                                  moving: false, asImage: true, surface: palette.surface)
                            }
                        }
                        .environment(\.seleneCanvas, canvas)
                        .environment(\.nxAppLocale, locale)
                        .environment(\.locale, locale.formatLocale)
                        .environment(\.seleneReduceMotion, true)
                        .environment(\.colorScheme, .dark))
                    host.frame = CGRect(x: 0, y: 0, width: size.width, height: height)
                    // The AppKit-backed scroll view needs a window to lay out. Never order it onscreen.
                    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = host
                    defer { window.contentView = nil }
                    window.layoutIfNeeded()
                    for _ in 0..<10 {
                        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                        host.layoutSubtreeIfNeeded()
                    }
                    precondition(!window.isVisible)
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                    try png.write(to: output.appendingPathComponent("\(prefix)-\(suffix).png"))
                }
                if soundOnly {
                    let store = AppSettingsStore()
                    let library = SoundPackLibrary()
                    if name == "wide", let pack = try library.load("pollen") {
                        try captureAlert(SettingsSoundSection.importAlert(pack.manifest, locale: locale),
                                         to: output.appendingPathComponent("\(prefix)-sound-import.png"))
                        try captureAlert(SettingsSoundSection.removalAlert(pack.manifest.name, locale: locale),
                                         to: output.appendingPathComponent("\(prefix)-sound-remove.png"))
                    }
                    for (key, suffix) in [("selene", "default"), ("oort", "oort")] {
                        store.settings.soundPackID = key
                        try render(ScrollView {
                            SettingsSoundSection(settings: store, onActions: { _ in }, soundPackLibrary: library)
                                .padding(canvas.u(24))
                                .frame(maxWidth: 950)
                                .frame(maxWidth: .infinity)
                        }, as: "sound-\(suffix)")
                    }
                    continue
                }
                router.showLibrary()
                try render(home(data, router: router), as: "home")
                router.openIntegrations()
                let page = IntegrationsView(overview: data, router: router)
                try render(page, as: "page")
                try render(page, as: "all-rows", height: max(size.height, canvas.u(2500)))
                router.integrationFocus = .saves
                try render(page, as: "page-bottom")
                for enabled in [false, true] {
                    try render(FoundGamesSetupContent(findings: .init(steamGameCount: 2, portedAppCount: 0),
                        steamOn: enabled, focus: .openLibrary, move: { _ in }, activate: { _ in }),
                        as: enabled ? "steam-on" : "steam-off")
                }
            }
        }
    }

    @MainActor private static func captureAlert(_ alert: NSAlert, to file: URL) throws {
        alert.layout()
        let window = alert.window
        guard !window.isVisible, let view = window.contentView else { throw CocoaError(.fileWriteUnknown) }
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: file)
    }
}

private struct IntegrationFixtureHome: View {
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject var router: AppRouter
    let data: IntegrationOverview

    init(data: IntegrationOverview, router: AppRouter) { self.data = data; self.router = router }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpotlightTopBar(filter: .all, sort: .recent, showClock: false)
                .environment(\.integrationBar, AnyView(IntegrationBar(rows: data.rows, focused: router.integrationBarFocused,
                                                                     open: router.openIntegrations)))
            VStack(alignment: .leading, spacing: canvas.u(20)) {
                Text("Lunar Observatory").seleneFont(.screenTitle, .semibold)
                SelenePillButton(title: "Play", focused: !router.integrationBarFocused) {}
            }
            .padding(.leading, canvas.u(80))
            .padding(.top, canvas.u(280))
            Spacer()
        }
        .foregroundStyle(SeleneTheme.ink)
        .background(SeleneBackdrop(still: true))
    }
}
#endif
