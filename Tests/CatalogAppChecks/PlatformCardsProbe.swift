import AppKit
import SwiftUI
import NXLibraryCore
import ArcanePorting
@testable import NXLibrary

@main
@MainActor struct PlatformCardsProbe {
    static let locale = AppLocale(language: .french, region: "FR")

    static func main() throws {
        assertFixtureHome()
        suppressProbeNotifications()
        AppData.preferences.register(defaults: [AppViewModel.StorageKeys.setupCompleted: true])
        L10n.setContext(locale)
        SeleneFonts.register()
        let root = AppData.profile.home
        let output = root.appendingPathComponent("captures", isDirectory: true)
        let frames = output.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let wallpaper = root.appendingPathComponent("Clair.png")
        try picture(.init(width: 1440, height: 810), [.white, .cyan, .yellow]).write(to: wallpaper)
        let samples = try games(in: root)
        precondition(L10n.count("%lld games", 1, context: locale) == "1 jeu")
        precondition(L10n.count("%lld games", 3, context: locale) == "3 jeux")

        for (name, size, reduced) in [
            ("grand", CGSize(width: 1440, height: 810), false),
            ("étroit", CGSize(width: 780, height: 650), true)
        ] {
            let fixture = try Screen(samples, root: root, wallpaper: wallpaper, name: name, size: size, reduced: reduced)
            precondition(fixture.profiles.active != nil && fixture.app.visibleCatalogGames.count == 4)
            fixture.press(.jumpToEnd)
            precondition(fixture.app.spotlight.selectedGameID != nil,
                         "Closed input: alert \(String(describing: fixture.app.alertMessage)), notice \(String(describing: fixture.app.settingsNotice?.title)), locked \(fixture.app.profileOwnsInput)")
            fixture.press(.jumpToStart)
            try fixture.save("\(name)-fermé", to: output)
            fixture.press(.confirm)
            precondition(fixture.app.spotlight.selectedKey == SpotlightItem.platform.key)
            fixture.press(.navigateRight)   // Only Up/Down, A and B affect the open card.
            precondition(fixture.app.spotlight.selectedKey == SpotlightItem.platform.key)
            fixture.press(.navigateDown)    // Switch
            fixture.advance(0.24)           // Still images show the landed rail.
            try fixture.save("\(name)-ouvert-switch", to: output)
            fixture.press(.navigateDown)    // Steam
            fixture.advance(0.24)
            try fixture.save("\(name)-ouvert-steam", to: output)
            fixture.press(.navigateDown)    // Mac
            fixture.advance(0.24)
            try fixture.save("\(name)-ouvert-mac", to: output)
            precondition(fixture.profiles.active?.spotlightPlatform == nil)
            fixture.press(.cancel)
            precondition(fixture.profiles.active?.spotlightPlatform == .macShortcut,
                         "Closing should save Mac; saved: \(String(describing: fixture.profiles.active?.spotlightPlatform)), failure: \(fixture.profiles.failed)")
            precondition(fixture.app.spotlight.selectedKey == SpotlightItem.platform.key)
            try fixture.save("\(name)-fermé-mac", to: output)
            fixture.press(.jumpToEnd)
            precondition(fixture.app.spotlight.selectedGameID == samples.first { $0.integration == .macShortcut }?.id)
            try fixture.save("\(name)-fiche-mac", to: output)
            fixture.press(.jumpToStart)
            for _ in 0..<3 { fixture.press(.tabNext, settle: 0.06) }   // Favorites
            precondition(fixture.app.librarySelection.query.filter == .favorites)
            try fixture.save("\(name)-filtre-vide", to: output)
            fixture.press(.jumpToEnd)
            precondition(fixture.app.spotlight.selectedKey == SpotlightItem.card(.addGame).key)
            fixture.press(.jumpToStart)
            fixture.press(.confirm)
            fixture.press(.navigateUp, settle: 0)
            fixture.press(.confirm)     // Close before the debounce; Steam is committed immediately.
            precondition(fixture.profiles.active?.spotlightPlatform == .steam)
            precondition(fixture.app.spotlight.selectedKey == SpotlightItem.platform.key)

            fixture.app.applyCatalog(fixture.document(samples.filter { $0.integration != .steam }))
            fixture.advance()
            for _ in 0..<3 { fixture.press(.tabPrevious, settle: 0.06) }
            fixture.press(.jumpToEnd)
            precondition(fixture.app.spotlight.selectedGameID != nil)
            precondition(fixture.profiles.active?.spotlightPlatform == .steam, "The fallback does not overwrite the preference")
        }

        for (name, games) in [("sans-jeu", []), ("une-plateforme", samples.filter { $0.integration == .nxnative })] {
            let fixture = try Screen(games, root: root, wallpaper: wallpaper, name: name, size: .init(width: 780, height: 650))
            fixture.press(.confirm)
            fixture.press(.navigateDown)
            try fixture.save(name, to: output)
            fixture.press(.confirm)
            precondition(fixture.profiles.active?.spotlightPlatform == (games.isEmpty ? nil : .nxnative))
        }

        let video = try Screen(samples, root: root, wallpaper: wallpaper, name: "motion", size: .init(width: 960, height: 540))
        video.press(.confirm)
        var bitmaps: [NSBitmapImageRep] = []
        for index in 0..<43 {
            if index == 5 || index == 9 { video.press(.navigateDown, settle: 0) }
            if index == 25 { video.press(.navigateDown, settle: 0) }
            if index == 37 { video.press(.confirm, settle: 0) }
            video.advance(1.0 / 24)
            bitmaps.append(try video.bitmap())
        }
        for (index, bitmap) in bitmaps.enumerated() {
            try png(bitmap).write(to: frames.appendingPathComponent(String(format: "%02d.png", index)))
        }
        // The rightmost Steam art is still drawn just after the press, but not in Steam's scoped row.
        func endOfRail(_ frame: Int) -> NSColor? {
            bitmaps[frame].colorAt(x: 550, y: 100)?.usingColorSpace(.sRGB)
        }
        precondition(endOfRail(4) != nil && endOfRail(4) == endOfRail(6),
                     "An intermediate cursor must not replace the covers")
        precondition(endOfRail(4) != endOfRail(24), "The settled choice must replace the covers")
        precondition(ButtonPrompts.keyboardKey(.vertical) == .text("↑ ↓"))
        print("Spotlight: mixed/empty/single source, modal input, separate filters, debounce then immediate close, removal fallback; French PNGs and video frames.")
    }

    @MainActor final class Screen {
        let app: AppViewModel
        let profiles: LocalProfileStore
        let size: CGSize
        let host: NSHostingView<AnyView>
        let window: NSWindow
        private let root: URL

        init(_ games: [CatalogGame], root: URL, wallpaper: URL, name: String, size: CGSize, reduced: Bool = false) throws {
            self.root = root.appendingPathComponent(name, isDirectory: true)
            self.size = size
            let settings = AppSettingsStore(fileURL: self.root.appendingPathComponent("settings.json"))
            settings.settings.interfaceSounds = false
            settings.settings.showClock = false
            settings.settings.gameInboxEnabled = false
            settings.settings.refreshLibraryAtLaunch = false
            settings.settings.checkEngineAtLaunch = false
            settings.settings.visibleSpotlightCards = [.addGame]
            settings.settings.librarySort = .name
            SoundEffectService.shared.bind(to: settings)
            profiles = LocalProfileStore(directory: self.root, settings: settings.settings, name: "Pilote")
            app = AppViewModel(settingsStore: settings, catalog: Self.document(games, root: root),
                               repository: .init(store: .init(directory: self.root)), localProfiles: profiles)
            app.homeSeen = true
            app.showSetupCheck = false
            app.spotlight.select(.platform)
            let router = AppRouter(settings: settings)
            router.setInitialRoute(.library)
            let view = SpotlightView(viewModel: app, router: router, settings: settings, playSessions: PlaySessionStore(),
                                     runningGames: RunningGameMonitor(), artwork: ArtworkStore(), storeHost: ModStoreHost())
                .environment(\.nxAppLocale, locale)
                .environment(\.seleneBackdropStyle, .init(palette: ThemeStore.shared.palette, wallpaperURL: wallpaper,
                                                          animated: false, brightness: .bright))
                .environment(\.seleneReduceMotion, reduced)
                .environment(\.seleneShowButtonHints, true)
                .environment(\.seleneButtonNames, name == "grand" || name == "motion" ? .nintendo : .automatic)
                .environment(\.colorScheme, .dark)
                .seleneCanvasRoot()
                .frame(width: size.width, height: size.height)
            host = NSHostingView(rootView: AnyView(view))
            host.frame.size = size
            window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.layoutIfNeeded()
            advance()
        }

        static func document(_ games: [CatalogGame], root: URL) -> CatalogDocument {
            .init(sources: [.init(integration: .nxnative, isEnabled: true),
                            .init(integration: .steam, isEnabled: true, rootURL: root),
                            .init(integration: .macShortcut, isEnabled: true)], games: games)
        }

        func document(_ games: [CatalogGame]) -> CatalogDocument { Self.document(games, root: root) }

        func press(_ action: GamepadAction, settle: TimeInterval = 0.38) {
            NotificationCenter.default.post(name: .nxSpotlightGamepadAction, object: action)
            if settle > 0 { advance(settle) }
        }

        func advance(_ seconds: TimeInterval = 0.38) {
            let end = Date().addingTimeInterval(seconds)
            repeat {
                _ = host.fittingSize
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: min(end, .now.addingTimeInterval(0.01)))
            } while Date() < end
        }

        func bitmap() throws -> NSBitmapImageRep {
            precondition(!window.isVisible)
            guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: image)
            return image
        }

        func save(_ name: String, to folder: URL) throws {
            try png(bitmap()).write(to: folder.appendingPathComponent("\(name).png"))
        }
    }

    static func games(in root: URL) throws -> [CatalogGame] {
        let square = CGSize(width: 256, height: 256)
        let names = ["Aurore", "Éclipse", "Secret"]
        let switchGames = try names.enumerated().map { index, name in
            var game = PortedGame(name: name, url: root.appendingPathComponent("\(name).app"), platform: .macApp,
                                  sizeBytes: 0, modificationDate: .now, titleId: String(format: "010000000000%04d", index))
            game.isFavorite = index == 0
            game.isHidden = index == 2
            try ArtworkPicks.shared.save(picture(square, [index == 0 ? .purple : .blue, .black], symbol: "moon.stars"),
                                        titleID: game.titleId!, slot: .icon)
            return CatalogGame(nxnative: game)
        }
        var steam = SteamCatalogGame(appID: 4_200_001, name: "Station Boréale")
        steam.hasBeenRecognized = true
        let steamKey = CatalogGame(steam: steam).personalizationReference.key
        try SteamPersonalizations.shared.artwork.save(fields: [:],
            images: [.icon: picture(square, [.blue, .black], symbol: "sparkles")], automatic: [], titleID: steamKey)
        let id = UUID()
        let macFile = root.appendingPathComponent("Atlas.app")
        let mac = try JSONDecoder().decode(MacShortcutRecord.self, from: JSONSerialization.data(withJSONObject: [
            "id": id.uuidString, "name": "Atlas", "bundleIdentifier": "local.synthetic.atlas",
            "url": macFile.absoluteString, "isFavorite": false, "isHidden": false
        ]))
        let macKey = "mac-\(id.uuidString.lowercased())"
        try ArtworkPicks.shared.save(picture(square, [.orange, .black], symbol: "sun.max"), titleID: macKey, slot: .cover)
        return switchGames + [CatalogGame(steam: steam), CatalogGame(record: mac, personalizationKey: macKey)]
    }

    static func picture(_ size: CGSize, _ colors: [Color], symbol: String? = nil) throws -> Data {
        let renderer = ImageRenderer(content: LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay { if let symbol { Image(systemName: symbol).resizable().scaledToFit().padding(60).foregroundStyle(.white) } }
            .frame(width: size.width, height: size.height))
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        return try png(NSBitmapImageRep(cgImage: image))
    }

    static func png(_ image: NSBitmapImageRep) throws -> Data {
        guard let data = image.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
