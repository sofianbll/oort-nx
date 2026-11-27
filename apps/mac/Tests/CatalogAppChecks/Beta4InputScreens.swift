import AppKit
import SwiftUI
@testable import NXLibrary
import NXLibraryCore

@main struct Beta4InputScreens {
    private final class HiddenWindow: NSWindow {
        override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {}
        override func orderFrontRegardless() {}
        override func makeKeyAndOrderFront(_ sender: Any?) {}
    }

    @MainActor static func main() throws {
        assertFixtureHome()
        suppressProbeNotifications()
        SeleneFonts.register()
        let output = AppData.profile.home.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let french = AppLocale(language: .french, region: "FR")
        L10n.setContext(french)
        var ok = true
        for mode in Mode.requested {
            switch mode {
            case .palette: if !palette(french) { ok = false }
            case .launch: if try !launch(french, output) { ok = false }
            case .cursor: if !cursor() { ok = false }
            }
        }
        if !ok { exit(1) }
    }

    enum Mode: String {
        case palette, launch, cursor
        static let requested: [Mode] = [.palette, .launch, .cursor]
    }

    private final class TestSource: ControllerSource {
        var onEvent: ((ControllerSourceEvent) -> Void)?
        var preferredID: ObjectIdentifier?
        func start() {}
        func stop() {}
        func refresh() {}
    }

    @MainActor private static func cursor() -> Bool {
        let gc = TestSource()
        let pad = ControllerIdentity(id: ObjectIdentifier(gc), name: "Test pad", brand: .xbox)
        gc.preferredID = pad.id
        let controller = GameControllerService(gcSource: gc, hidSource: TestSource())
        gc.onEvent?(.connected(pad, claimedByGC: false))
        var state = CursorIdleState()
        let hand = CursorWindowView.controllerActivity(controller).sink { state.controllerUsed() }
        defer { hand.cancel() }
        func press() {
            gc.onEvent?(.input(pad.id, .button(.a, true)))
            gc.onEvent?(.input(pad.id, .button(.a, false)))
        }
        press()
        let first = state.update(now: 1, eligible: true, fullscreen: false)
        state.mouseActivity(now: 2)
        let inactive = state.update(now: 2, eligible: false, fullscreen: false)
        press()
        let returned = state.update(now: 3, eligible: true, fullscreen: false)
        print("Windowed cursor: first press hides=\(first), focus lost restores=\(!inactive), next press hides=\(returned)")
        return first && !inactive && returned
    }

    @MainActor private static func palette(_ locale: AppLocale) -> Bool {
        let palette = CommandPalette()
        let items = ["Moon", "Comet"].map { PaletteItem(id: $0, kind: .game, title: $0, primary: "Play", secondary: "Options") }
        palette.open(items: items, recents: [], suggestions: items.map(\.id), symbols: [:])
        var heard: [String] = []
        let host = NSHostingView(rootView: CommandPaletteView(palette: palette, postAnnouncement: { heard.append($0) })
            .environment(\.nxAppLocale, locale).seleneCanvasRoot().environment(\.seleneReduceMotion, true))
        let window = offscreen(host)
        defer { window.contentView = nil }
        settle(host)
        let start = heard.count
        palette.handle(.navigateDown)
        settle(host)
        let action = L10n.text("Play", context: locale)
        let arrowAnnounced = heard.count > start && heard.last?.contains("Comet") == true && heard.last?.contains(action) == true
        palette.type("Moon")
        settle(host)
        let one = heard.count
        palette.type("Comet")
        settle(host)
        let replacementAnnounced = heard.count > one && heard.last?.contains("Comet") == true && heard.last?.contains(action) == true
        palette.type("zzzzzzzz")
        settle(host)
        let emptyAnnounced = heard.last?.contains(L10n.text("Nothing matches. Try another word.", context: locale)) == true
        print("Palette announcement: arrow=\(arrowAnnounced), same count=\(replacementAnnounced), no matches=\(emptyAnnounced)")
        return arrowAnnounced && replacementAnnounced && emptyAnnounced
    }

    @MainActor private static func launch(_ locale: AppLocale, _ output: URL) throws -> Bool {
        let repository = CatalogRepository(store: CatalogStore(directory: AppData.supportRoot))
        let settings = AppSettingsStore()
        settings.settings.launchStyle = .minimal
        let model = AppViewModel(settingsStore: settings, catalog: try repository.load(),
                                 repository: repository, registerNotifications: false)
        let game = PlayedGame.steam(CatalogGame(steam: .init(appID: 1, name: "Observatoire lunaire")))
        let state = LaunchOverlayState(game: game)
        model.launchOverlay = state
        let artwork = ArtworkStore()
        let hosts = [false, true].map { hints in
            NSHostingView(rootView: LaunchScreenView(state: state, viewModel: model, store: model.store, artwork: artwork,
                                                     settings: settings.settings, reduceMotion: true)
                .seleneCanvasRoot()
                .environment(\.nxAppLocale, locale)
                .environment(\.seleneShowButtonHints, hints)
                .environment(\.seleneReduceMotion, true))
        }
        let windows = hosts.map(offscreen)
        defer { windows.forEach { $0.contentView = nil } }
        settle(hosts[0])
        precondition(!NSApp.isActive && !model.launchOverlay!.offersExit)
        RunLoop.main.run(until: Date().addingTimeInterval(LaunchExit.offerDelay + 0.6))
        precondition(model.launchOverlay?.offersExit == true, "The inactive launch screen reached the click-only offer")
        var images: [Data] = []
        for (index, host) in hosts.enumerated() {
            settle(host)
            precondition(!windows[index].isVisible && !NSApp.isActive)
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = bitmap.representation(using: .png, properties: [:])!
            try image.write(to: output.appendingPathComponent(index == 0 ? "lancement-indications-masquees.png" : "lancement-indications-affichees.png"))
            images.append(image)
        }
        let same = images[0] == images[1]
        print("Inactive launch: same existing close control with hints hidden or shown = \(same)")
        return same
    }

    @MainActor private static func offscreen(_ host: NSView) -> NSWindow {
        let frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
        let window = HiddenWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        host.frame = frame
        window.contentView = host
        window.layoutIfNeeded()
        return window
    }

    @MainActor private static func settle(_ host: NSView) {
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
