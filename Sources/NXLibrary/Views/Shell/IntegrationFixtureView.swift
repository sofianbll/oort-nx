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
                    let findings = FirstRunFindings(steamGameCount: 2, portedAppCount: 0)
                    FoundGamesSetupContent(findings: findings, steam: SteamSourceEntries.found(findings, inForce: steamOn, waiting: nil),
                        focus: setupFocus, move: { setupFocus = $0 }, activate: setup)
                } else {
                    switch router.route {
                    case .integrations: IntegrationsView(overview: data, router: router)
                    case .settings(let section):
                        VStack(spacing: SeleneTokens.Space.small) {
                            Text(L10n.text(section.title, context: locale)).seleneFont(.heading)
                            Text(L10n.text(SettingsCatalog.all.first { $0.id == router.settingsRowID }?.title ?? "", context: locale))
                            Text("Fixture · no settings or service is opened").foregroundStyle(SeleneTheme.ink60)
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
            .padding(.trailing, SeleneTokens.Space.control)
            .padding(.top, SeleneTokens.Space.large)
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

    @MainActor static func capture(to output: URL, soundOnly: Bool = false, onboardingOnly: Bool = false) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        SeleneFonts.register()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let router = AppRouter()
        let data = example(0)
        let languages: [(AppLanguage, String)] = onboardingOnly ? [(.french, "FR")] : [(.english, "US"), (.french, "FR")]
        let onboarding = try onboardingOnly ? fixtureOnboardingState() : nil
        for (language, region) in languages {
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
                                if CommandLine.arguments.contains("--fixture-bright") {
                                    OortGalleryWallpaper()
                                } else if onboardingOnly {
                                    LinearGradient(colors: [.yellow, .white, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                } else {
                                    Color(hex: palette.scrim)
                                    Rectangle().fill(SeleneTheme.baseGradient(for: palette)).opacity(SeleneTokens.Alpha.muted)
                                    MoonlightBackdrop(accent: SeleneTheme.glyph, ink: SeleneTheme.ink,
                                                      moving: false, asImage: true, surface: palette.surface)
                                }
                            }
                        }
                        .environment(\.seleneCanvas, canvas)
                        .environment(\.nxAppLocale, locale)
                        .environment(\.locale, locale.formatLocale)
                        .environment(\.seleneButtonNames, .xbox)
                        .environment(\.seleneReduceMotion, true)
                        .environment(\.colorScheme, .dark))
                    try captureWindow(host, size: CGSize(width: size.width, height: height),
                                      to: output.appendingPathComponent("\(prefix)-\(suffix).png"))
                }
                if let (model, settings, profiles, sources) = onboarding {
                    model.reopenOnboarding()
                    GameControllerService.shared.activeControllerName = "DualSense"
                    GameControllerService.shared.isGamepadConnected = true
                    for page in FirstRunSetup.Page.tour {
                        try render(OnboardingView(viewModel: model, settings: settings, profiles: profiles, sources: sources,
                                                  finish: {}, openSettings: { _, _ in }), as: page.rawValue)
                        model.moveOnboarding(1)
                    }
                    try render(OnboardingNewsView(onExit: { _ in }), as: "news")
                    try render(OnboardingCopyOffer(choose: { _ in }), as: "copy")
                    continue
                }
                if soundOnly {
                    let store = AppSettingsStore()
                    let library = SoundPackLibrary()
                    if name == "wide", let pack = try library.load("pollen") {
                        for (question, suffix) in [(SettingsSoundSection.importQuestion(pack.manifest, locale: locale), "import"),
                                                   (SettingsSoundSection.removalQuestion(pack.manifest.name, locale: locale), "remove")] {
                            try render(SeleneOverlay(style: .dialog) {
                                SeleneChoiceDialog(title: question.title, message: question.message,
                                                   choices: suffix == "remove" ? [question.action, "Cancel"] : ["Cancel", question.action],
                                                   focus: .constant(suffix == "remove" ? 1 : 0), cancelIndex: suffix == "remove" ? 1 : 0,
                                                   destructive: suffix == "remove" ? [0] : [],
                                                   onCancel: {}, onChoose: { _ in })
                            }, as: "sound-\(suffix)")
                        }
                    }
                    // A pack of the player's own, made up here, so Other has one to hold.
                    if !library.choices().contains(where: { $0.key == "custom.lagon" }) {
                        try library.install(fixtureSoundPack())
                    }
                    if name == "wide", language == .french { try probeSoundPackRow(library, canvas: canvas) }
                    let page = SettingsPage.category(.sound)
                    for (key, suffix, row) in [("selene", "default", "Sound pack"), ("oort", "oort", "Sound pack"),
                                               ("frost", "frost", "Sound pack"), ("mist", "mist", "Sound pack"),
                                               ("nucleus", "nucleus", "Sound pack"), ("pollen", "pollen", "Sound pack"),
                                               ("custom.lagon", "imported", "Other pack")] {
                        store.settings.soundPackID = key
                        try render(OortSettingsShell(title: page.title(in: locale), onBack: nil) {
                            SettingsSidebar(selection: page, isFocused: false, query: .constant(""), searchFieldRequest: 0,
                                            onSelect: { _ in }, onSearchFocus: {}, onSubmit: {})
                        } detail: {
                            ScrollView {
                                SettingsSoundSection(settings: SettingsEditor(store), onActions: { _ in }, soundPackLibrary: library)
                                    .environment(\.seleneFocusedRowID, row)
                            }
                            .scrollIndicators(.hidden)
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
                for integration in IntegrationID.allCases {
                    router.showIntegrationDetail(integration)
                    try render(page, as: "detail-\(integration)")
                    router.backFromIntegration()
                }
                for enabled in [false, true] {
                    let findings = FirstRunFindings(steamGameCount: 2, portedAppCount: 0)
                    try render(FoundGamesSetupContent(findings: findings,
                        steam: SteamSourceEntries.found(findings, inForce: enabled, waiting: nil),
                        focus: .openLibrary, move: { _ in }, activate: { _ in }),
                        as: enabled ? "steam-on" : "steam-off")
                }
            }
        }
    }

    /// Drives the pack rows through the actions Left and Right use, from a controller or the keyboard. Nothing plays.
    @MainActor private static func probeSoundPackRow(_ library: SoundPackLibrary, canvas: SeleneCanvas) throws {
        let store = AppSettingsStore()
        let saved = store.settings.soundPackID
        // As on the page: changes go to a draft until the player saves, so the captures keep their settings.
        store.beginDraft(fields: [.init("interfaceSounds", \.interfaceSounds) { "\($0)" },
                                  .init("soundPack", \.soundPackID, previews: true) { $0 }])
        store.editingSettings.interfaceSounds = false
        store.editingSettings.soundPackID = "pollen"
        var actions: [SettingsRowAction] = []
        let host = NSHostingView(rootView: SettingsSoundSection(settings: SettingsEditor(store),
                                                               onActions: { actions = $0 }, soundPackLibrary: library)
            .environment(\.seleneCanvas, canvas))
        host.frame = CGRect(x: 0, y: 0, width: canvas.size.width, height: canvas.size.height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func settle() {
            for _ in 0..<10 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                host.layoutSubtreeIfNeeded()
            }
        }
        var steps = 0
        func press(_ id: String, _ delta: Int, expect key: String) {
            guard let cycle = actions.first(where: { $0.id == id })?.cycle else { preconditionFailure("no \(id) row") }
            cycle(delta)
            settle()
            steps += 1
            let chosen = store.editingSettings.soundPackID
            precondition(chosen == key, "\(id) \(delta): \(chosen), not \(key)")
            let ids = actions.map(\.id)
            let other = SoundPackRow.value(for: key) == SoundPackRow.other
            precondition(ids.contains("soundPackOther") == other, "Other pack row for \(key)")
            if other { precondition(ids.firstIndex(of: "soundPackOther") == ids.firstIndex(of: "soundPack").map { $0 + 1 }) }
        }
        window.layoutIfNeeded()
        settle()
        precondition(store.editingSettings.soundPackID == "pollen" && actions.contains { $0.id == "soundPackOther" })
        press("soundPack", 1, expect: "oort")
        press("soundPack", -1, expect: "pollen")
        for key in ["umbra", "impulsion", "custom.lagon", "selene", "pollen", "selene"] {
            press("soundPackOther", key == "selene" && store.editingSettings.soundPackID == "pollen" ? -1 : 1, expect: key)
        }
        for key in ["nucleus", "mist", "frost", "oort", "selene"] { press("soundPack", -1, expect: key) }
        precondition(!window.isVisible && store.settings.soundPackID == saved, "nothing saved without Save")
        print("Sound pack row probe: \(steps) steps passed")
    }

    private static func fixtureSoundPack() throws -> SoundPack {
        let folder = AppData.profile.home.appendingPathComponent("lagon", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = #"{"format":1,"id":"lagon","name":"Lagon","author":"Fixture","license":"CC0-1.0","version":"1.0.0","events":{"select":["tone.wav"]}}"#
        // 10 ms of silence: 24 kHz, 16-bit mono.
        let wave = Data([82, 73, 70, 70, 4, 2, 0, 0, 87, 65, 86, 69, 102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
                         192, 93, 0, 0, 128, 187, 0, 0, 2, 0, 16, 0, 100, 97, 116, 97, 224, 1, 0, 0]) + Data(repeating: 0, count: 480)
        try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
        try wave.write(to: folder.appendingPathComponent("tone.wav"))
        return try SoundPack.read(folder)
    }

    @MainActor static func fixtureOnboardingState() throws
        -> (AppViewModel, AppSettingsStore, LocalProfileStore, CatalogSourcesModel) {
        precondition(AppData.integrationFixtureHome != nil)
        let home = AppData.profile.home
        let apps = home.appendingPathComponent("Applications", isDirectory: true)
        let files = home.appendingPathComponent("Game files", isDirectory: true)
        let fm = FileManager.default
        for (name, id) in [("Aube lunaire", "0100000000011000"), ("Rivage de verre", "0100000000012000")] {
            let app = apps.appendingPathComponent("\(name).app")
            let contents = app.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: [
                "CFBundleIdentifier": "org.nxnative.\(id)", "DMTitleID": id, "CFBundleName": name
            ], format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        try fm.createDirectory(at: files, withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: files.appendingPathComponent("Traverse [0100000000013000].xci"))
        try Data("synthetic".utf8).write(to: files.appendingPathComponent("Brume.xci"))
        AppData.preferences.set(files.path, forKey: AppViewModel.StorageKeys.savedGameFolder)
        let repository = CatalogRepository(store: CatalogStore(directory: AppData.supportRoot))
        let installed = OnboardingInventory.read(apps: [apps], files: nil, existing: [])
        var catalog = try repository.load()
        if let game = installed.entries.first?.game { catalog = try repository.mergeNXNative(scanned: [game], enableSource: true) }
        let settings = AppSettingsStore()
        settings.settings.appLanguage = .french
        let profiles = LocalProfileStore(settings: settings.settings, name: "Camille")
        let model = AppViewModel(settingsStore: settings, catalog: catalog, repository: repository,
                                 localProfiles: profiles, registerNotifications: false)
        model.libraryFolder = apps
        let sources = CatalogSourcesModel(repository: repository, initialConfiguration: .init(integration: .steam)) { _ in }
        return (model, settings, profiles, sources)
    }

    @MainActor static func captureWindow(_ host: NSView, size: CGSize, to file: URL) throws {
        host.frame = CGRect(origin: .zero, size: size)
        // AppKit-backed scroll views need a window to lay out. Never order it onscreen.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        window.layoutIfNeeded()
        for _ in 0..<10 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
        }
        precondition(!window.isVisible)
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
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
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.panel)) {
                Text("Lunar Observatory").seleneFont(.screen, .semibold)
                SelenePillButton(title: "Play", focused: !router.integrationBarFocused) {}
            }
            .padding(.leading, canvas.u(SeleneTokens.Space.chromeGutter + SeleneTokens.Space.medium))
            .padding(.top, canvas.u(SeleneTokens.Space.stageHeader + SeleneTokens.Space.stageGutter + SeleneTokens.Space.group))
            Spacer()
        }
        .foregroundStyle(SeleneTheme.ink)
        .background(SeleneBackdrop(still: true))
    }
}
#endif
