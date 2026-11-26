import AppKit
import SwiftUI
import NXLibraryCore
import ArcanePorting
@testable import NXLibrary

/// Settings › About and its credits, with the controller, in both languages. No window, no network, no link opened.
@main
@MainActor struct CreditsProbe {
    static func main() throws {
        assertFixtureHome()
        suppressProbeNotifications()
        AppData.preferences.register(defaults: [AppViewModel.StorageKeys.setupCompleted: true])
        SeleneFonts.register()
        let root = AppData.profile.home
        let output = root.appendingPathComponent("captures", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (language, region) in [(AppLanguage.french, "FR"), (.english, "US"), (.german, "DE")] {
            let locale = AppLocale(language: language, region: region)
            L10n.setContext(locale)
            let model = try Model(root.appendingPathComponent(language.rawValue, isDirectory: true))
            for (name, size) in [("page", CGSize(width: 1440, height: 1500)), ("720", CGSize(width: 1280, height: 720)), ("1440", CGSize(width: 1440, height: 900))] {
                let host = model.settings(locale, size: size)
                try host.save("about-\(language.rawValue)-\(name)", to: output)
            }
            #if CREDITS
            try model.check(locale, output: output)
            #endif
        }
        print("Settings › About: French, English and German captures.")
    }

    @MainActor struct Model {
        let app: AppViewModel
        let store: AppSettingsStore
        let router: AppRouter

        init(_ root: URL) throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            store = AppSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
            store.settings.interfaceSounds = false
            store.settings.refreshLibraryAtLaunch = false
            store.settings.checkEngineAtLaunch = false
            SoundEffectService.shared.bind(to: store)
            app = AppViewModel(settingsStore: store,
                               catalog: .init(sources: [.init(integration: .nxnative, isEnabled: true)], games: []),
                               repository: .init(store: .init(directory: root)),
                               localProfiles: LocalProfileStore(directory: root, settings: store.settings, name: "Pilote"))
            router = AppRouter(settings: store)
        }

        func settings(_ locale: AppLocale, size: CGSize) -> Host {
            Host(view(SettingsView(initialSection: .about, viewModel: app, settings: store, router: router, artwork: ArtworkStore()), locale), size: size)
        }

        func view(_ content: some View, _ locale: AppLocale) -> AnyView {
            AnyView(content
                .environmentObject(AppUpdater())
                .environment(\.nxAppLocale, locale)
                .environment(\.locale, locale.formatLocale)
                .environment(\.seleneReduceMotion, true)
                .environment(\.seleneButtonNames, .xbox)
                .environment(\.colorScheme, .dark)
                .background(SeleneTheme.pageSurface)
                .seleneCanvasRoot())
        }

        #if CREDITS
        func check(_ locale: AppLocale, output: URL) throws {
            let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            precondition(icon.flatMap { NSImage(contentsOf: $0) } != nil, "Missing Oort NX app icon")
            let credits = Credits.bundled!
            let groups = credits.groups(for: .mac)
            let every = Set(groups.map(\.id))
            var actions: [SettingsRowAction] = []
            var openedURLs: [URL] = []
            let section = { (row: String?, button: Int) in
                view(ScrollView {
                    SettingsAboutSection(viewModel: app, setup: app.setup, opened: every) { actions = $0 }
                        .padding(24)
                        .environment(\.seleneFocusedRowID, row)
                        .environment(\.seleneFocusedButton, button)
                }.environment(\.openURL, OpenURLAction { url in
                    openedURLs.append(url)
                    return .handled
                }), locale)
            }
            let long = Host(section("credit-arcane", 1), size: CGSize(width: 1120, height: 4600))
            try long.save("credits-\(locale.language.rawValue)-tous", to: output)
            let baseView = Host(section("credit-arcane", 0), size: CGSize(width: 1120, height: 1300))
            try baseView.save("credits-\(locale.language.rawValue)-base", to: output)

            // One stop per line of cards, and every card of every group within reach of left and right.
            let base = credits.baseGroup!
            precondition(base.credits.map(\.id) == credits.base)
            let shown = [base] + groups
            let fits = actions.first { $0.rowID == "credit-arcane" }!.buttonCount
            precondition(fits == credits.columns, "\(fits) columns where three fit")
            let lines = shown.flatMap { OortCreditGroup.lines($0, credits, fitting: fits) }
            // The six fill their grid; every other group is a list.
            for group in shown {
                precondition(OortCreditGroup.lines(group, credits, fitting: fits).allSatisfy { $0.credits.count == (group.id == base.id ? fits : 1) }, group.id)
            }
            for line in lines {
                let action = actions.first { $0.rowID == line.id }!
                precondition(action.buttonCount == line.credits.count, line.id)
            }
            precondition(lines.flatMap(\.credits).count == credits.credits.filter { $0.systems.contains("mac") || credits.base.contains($0.id) }.count)
            precondition(Set(actions.map(\.id)).count == actions.count, "Two rows share an identity")
            for row in ["Open project docs", "Copy diagnostics", "credits-notice"] {
                precondition(actions.contains { $0.rowID == row }, "\(row) is out of the controller's reach")
            }
            let firstLine = actions.firstIndex { $0.rowID == "credit-arcane" }!
            let funding = actions[firstLine - 1]
            precondition(funding.rowID == "oort-funding" && funding.buttonCount == 1 && funding.isEnabled)
            precondition(!actions.contains { $0.id == "support" || $0.rowID == "credit-buymeacoffee" })
            precondition(!credits.credits.contains { $0.url.host == "buymeacoffee.com" })
            let arcane = credits.credits.first { $0.id == "arcane" }
            precondition(arcane?.author == "Bium23" && arcane?.url.absoluteString == "https://github.com/Bium23/NxLibrary")
            precondition(openedURLs.isEmpty, "Opening Settings must not open the funding page")
            funding.press(button: 0)
            precondition(openedURLs.map(\.absoluteString) == ["https://ko-fi.com/sofianbll"])
            let expected = ["fr": "Soutenir Oort NX", "en": "Support Oort NX", "de": "Oort NX unterstützen"]
            precondition(funding.title == expected[locale.language.rawValue])
            for group in groups { precondition(actions.contains { $0.rowID == "credits-\(group.id)" }) }
            // Closed, the six cards stay in sight and the others are one press away.
            _ = Host(view(SettingsAboutSection(viewModel: app, setup: app.setup) { actions = $0 }, locale), size: CGSize(width: 1120, height: 900))
            precondition(actions.contains { $0.rowID == "credit-arcane" } && !actions.contains { $0.rowID == "credit-gametdb" })
            // Where three cards are too narrow, two by three and never a hole.
            let narrow = Host(view(ScrollView {
                SettingsAboutSection(viewModel: app, setup: app.setup) { actions = $0 }.frame(width: 600)
            }, locale), size: CGSize(width: 1440, height: 1400))
            precondition(actions.first { $0.rowID == "credit-arcane" }!.buttonCount == credits.columns - 1, "Two columns where three do not fit")
            try narrow.save("about-\(locale.language.rawValue)-etroit", to: output)
            let words = credits.legal.filter { $0.systems.contains("mac") }
            precondition(words.count == credits.statements(for: .mac, in: locale.language.rawValue).count && words.count >= 7)
            precondition(credits.statements(for: .mac, in: "fr").contains { $0.contains("Nintendo") })
        }
        #endif
    }

    @MainActor final class Host {
        let host: NSHostingView<AnyView>
        let window: NSWindow

        init(_ view: AnyView, size: CGSize) {
            host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
            host.frame.size = size
            window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.layoutIfNeeded()
            let end = Date().addingTimeInterval(0.5)
            repeat {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: min(end, .now.addingTimeInterval(0.01)))
            } while Date() < end
        }

        func save(_ name: String, to folder: URL) throws {
            precondition(!window.isVisible)
            let size = host.bounds.size
            guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: image)
            try image.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
