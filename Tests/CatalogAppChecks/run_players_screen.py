#!/usr/bin/env python3
"""Verify Players input and capture real Selene views with synthetic profiles and pads."""
import os
from pathlib import Path
import shutil
import sys
import tempfile

from audit_probe_host import ROOT, run_host

HOST = r'''
import AppKit
import ArcanePorting
import CoreText
import SwiftUI
@testable import NXLibrary
import NXLibraryCore

final class PlayersFixtureSource: ControllerSource {
    var onEvent: ((ControllerSourceEvent) -> Void)?
    func start() {}
    func stop() {}
}

@MainActor final class PlayersFixture {
    var plan: PlayerPlan?
    var presses: ((GameControllerService.AssignmentEvent) -> Void)?
    var identified: [String] = []
    var failRead = false
    var failWrite = false
    var profiles = [
        LocalProfile(name: "Alex", avatar: 2, look: .init(.init())),
        LocalProfile(name: "Camille", avatar: 6, look: .init(.init())),
        LocalProfile(name: "Sam", avatar: 8, look: .init(.init())),
    ]

    init() { precondition(profiles[1].setPIN("2468")) }

    func screen() async -> PlayersScreenModel {
        let model = PlayersScreenModel(session: PlayersScreenSession(), read: {
            if self.failRead { throw CocoaError(.fileReadCorruptFile) }
            return self.plan
        }, write: {
            if self.failWrite { throw CocoaError(.fileWriteNoPermission) }
            self.plan = $0
        }, unlock: { id, pin, plan in
            plan == self.plan && self.profiles.contains { $0.id == id && $0.matchesPIN(pin) }
        }, profiles: { self.profiles }, identify: { self.identified.append($0); return true }, leaseCapture: { action in
            self.presses = action
            return { self.presses = nil }
        })
        await model.load()
        return model
    }
}

@main struct PlayersProbe {
    static let stage = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PLAYERS_STAGE"]!, isDirectory: true)
    static let known = ConnectedController(id: "connection-a", name: "Pro Controller", kind: .nintendoSwitch,
        modelKey: "pro controller", identity: .hardware("opaque-a"),
        status: .init(batteryLevel: 0.82, isCharging: false, canIdentifyWithLights: true))
    static let xbox = ConnectedController(id: "connection-b", name: "Xbox Wireless Controller", kind: .xbox,
        modelKey: "xbox wireless controller", identity: .hardware("opaque-b"), status: .init(batteryLevel: 0.57))
    static let twinA = ConnectedController(id: "twin-a", name: "DualSense", kind: .playstation,
        modelKey: "dualsense", identity: .sameModelCannotTellApart, status: .init(canIdentifyWithRumble: true))
    static let twinB = ConnectedController(id: "twin-b", name: "DualSense", kind: .playstation,
        modelKey: "dualsense", identity: .sameModelCannotTellApart, status: .init())

    @MainActor static func main() async throws {
        assertFixtureHome()
        if ProcessInfo.processInfo.environment["PLAYERS_PARENTS_ONLY"] == "1" {
            suppressProbeNotifications()
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let font = stage.appendingPathComponent("MaterialIcons.ttf")
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        if ProcessInfo.processInfo.environment["PLAYERS_PARENTS_ONLY"] == "1" {
            try checkParents()
            return
        }
        try await checkInput()
        let fixture = PlayersFixture()
        let alex = fixture.profiles[0].id
        let camille = fixture.profiles[1].id
        let sam = fixture.profiles[2].id
        var one = PlayerPlan()
        try one.set(.init(profileID: alex, controller: .init(stableID: known.stableID, modelKey: known.modelKey)), at: 1)
        var four = one
        try four.set(.init(profileID: camille, controller: .init(stableID: xbox.stableID, modelKey: xbox.modelKey)), at: 2)
        try four.set(.init(profileID: sam), at: 3)
        try four.set(.init(), at: 4)
        var twins = one
        try twins.set(.init(controller: .init(modelKey: twinA.modelKey)), at: 2)
        var merged = four
        merged.mode = .merge
        try merged.setMergePlayer(2)
        var old = one
        old.mode = .inOrder
        let sizes: [(String, CGSize)] = [("large", .init(width: 1440, height: 810)),
                                        ("etroit", .init(width: 800, height: 640))]
        let oldNote = "This game's app is too old: rebuild it to keep the order."
        let detailsOnly = ProcessInfo.processInfo.environment["PLAYERS_DETAILS_ONLY"] == "1"
        for (language, region) in [(AppLanguage.english, "US"), (.french, "FR")] {
            let locale = AppLocale(language: language, region: region)
            L10n.setContext(locale)
            for (label, size) in sizes {
                let prefix = "\(language.rawValue)-\(label)"
                let states: [(String, PlayerPlan?, [ConnectedController])] = [
                    ("01-vide", nil, []), ("02-un", one, [known]), ("03-quatre", four, [known, xbox]),
                    ("04-jumelles", twins, [known, twinA, twinB]), ("05-perdue", one, []),
                    ("06-verrouille", four, [known, xbox]), ("07-modes", four, [known, xbox]),
                    ("08-ordre", old, [known]), ("09-rejoindre", one, [known]),
                    ("10-fusion", merged, [known, xbox]), ("11-ancien", old, [known]),
                    ("12-fusion-ancien", merged, [known, xbox]), ("13-appuyer", twins, [known, twinA, twinB]),
                    ("14-cible-fusion", merged, [known, xbox]), ("15-reset", four, [known, xbox]),
                    ("16-actions", four, [known, xbox]),
                ]
                for (name, plan, pads) in states {
                    if detailsOnly && !["02-un", "03-quatre", "13-appuyer"].contains(name) { continue }
                    fixture.plan = plan
                    let model = await fixture.screen()
                    model.updatePads(pads)
                    model.showsGameLimits = ["10-fusion", "12-fusion-ancien", "14-cible-fusion"].contains(name)
                    model.supportsExtendedMerge = model.showsGameLimits && name != "12-fusion-ancien"
                    switch name {
                    case "06-verrouille":
                        model.open(.profiles(2), focus: .profile(camille))
                        model.select(.profile(camille))
                        precondition(model.pin != nil)
                    case "07-modes":
                        model.select(.modes)
                    case "13-appuyer":
                        model.open(.player(2), focus: .assign)
                        model.select(.assign)
                        precondition(model.capturePlayer == 2)
                    case "14-cible-fusion":
                        model.select(.mergeTarget)
                    case "15-reset":
                        model.select(.reset)
                    case "16-actions":
                        model.select(.player(1))
                    default: break
                    }
                    let notes = name == "11-ancien" ? [1: oldNote] : [:]
                    try render(PlayersScreen(model: model, onClose: {}, orderNotes: notes),
                               name: "\(prefix)-\(name)", size: size, locale: locale)
                    model.endCapture()
                }
                if detailsOnly { continue }
                let settings = AppSettingsStore(fileURL: AppData.supportRoot.appendingPathComponent("settings.json"))
                let controller = GameControllerService(gcSource: PlayersFixtureSource(), hidSource: PlayersFixtureSource())
                try render(VStack(alignment: .leading) {
                    Text(verbatim: L10n.text("Controllers")).seleneFont(.screenTitle)
                    SettingsControllersSection(settings: settings, onActions: { _ in }, onViewControls: {}, onOpenPlayers: {},
                                               controller: controller)
                }.padding().frame(maxWidth: 700).environment(\.seleneMinimumFont, 12),
                name: "\(prefix)-voisin-manettes", size: size, locale: locale)
            }
        }
    }

    @MainActor static func checkInput() async throws {
        let f = PlayersFixture()
        let m = await f.screen()
        var closed = 0
        let screen = PlayersScreen(model: m, onClose: { closed += 1 })
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                         windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                         isARepeat: false, keyCode: code)!
            precondition(screen.handleKey(event) == nil)
        }
        func settled() async {
            for _ in 0..<300 where m.saving { await Task.yield() }
            precondition(!m.saving)
        }
        precondition(m.rows == [.modes, .add] && m.focusedRow == .modes)
        key(48)
        precondition(m.focusedRow == .add)
        key(48, .shift)
        precondition(m.focusedRow == .modes)
        screen.handleController(.navigateDown)
        precondition(m.focusedRow == .add)
        screen.handleController(.confirm)
        await settled()
        precondition(m.focusedRow == .player(1) && f.plan?.slot(1) == .init())
        key(48)
        key(36)
        await settled()
        precondition(m.focusedRow == .player(2))
        screen.handleController(.confirm)
        precondition(m.focusedRow == .profiles)
        key(125)
        precondition(m.focusedRow == .assign)
        m.updatePads([twinA, twinB])
        screen.handleController(.confirm)
        precondition(m.capturePlayer == 2 && m.hasIdenticalPads)
        screen.handleController(.profiles)
        screen.handleController(.cancel)
        precondition(m.capturePlayer == 2 && closed == 0)
        f.presses?(.button(twinB.id))
        await settled()
        precondition(m.capturePlayer == nil && m.connectedPad(2)?.id == twinB.id)
        precondition(f.plan?.slot(2)?.controller?.stableID == nil && f.plan?.slot(2)?.controller?.modelKey == twinB.modelKey)
        m.updatePads([twinA])
        precondition(m.resolution.slots[2] == .needsConfirmation([twinA.id]))
        screen.handleController(.confirm)
        precondition(!m.rows.contains(.identify))
        m.select(.assign)
        f.presses?(.timedOut)
        precondition(m.capturePlayer == nil && m.message != nil)
        m.select(.assign)
        key(53)
        precondition(m.capturePlayer == nil && f.presses == nil)
        m.select(.assign)
        f.presses?(.cancelled)
        precondition(m.capturePlayer == nil)
        m.select(.assign)
        f.presses?(.button(twinA.id))
        await settled()
        m.select(.player(2))
        m.select(.identify)
        precondition(f.identified == [twinA.id])
        m.select(.profiles)
        let locked = f.profiles[1]
        m.select(.profile(locked.id))
        precondition(m.pin != nil && m.submitPIN("1234") == "Incorrect code.")
        precondition(m.submitPIN("2468") == nil)
        await settled()
        precondition(m.access(for: 2) == .ready(locked))
        m.select(.player(2))
        m.select(.swap)
        m.select(.swapWith(1))
        await settled()
        precondition(m.connectedPad(1)?.id == twinA.id && m.access(for: 1) == .locked)
        m.select(.player(2))
        m.select(.remove)
        await settled()
        precondition(m.numbers == [1])
        m.select(.modes)
        precondition(m.rows == [.mode(.inOrder), .mode(.pressToJoin), .mode(.merge)])
        screen.handleController(.navigateDown)
        screen.handleController(.confirm)
        await settled()
        m.showsGameLimits = true
        m.select(.mergeTarget)
        precondition(m.rows == [.target(1)])
        m.supportsExtendedMerge = true
        precondition(m.rows.count == 8)
        m.select(.target(8))
        await settled()
        precondition(f.plan?.mergeTarget == 8)
        m.supportsExtendedMerge = false
        precondition(m.mergeTarget == 1 && f.plan?.mergeTarget == 8)
        m.select(.reset)
        precondition(m.confirmsReset && m.resetFocus == .cancel)
        screen.handleController(.confirm)
        precondition(!m.confirmsReset && !m.numbers.isEmpty)
        m.select(.reset)
        key(123)
        screen.handleController(.confirm)
        await settled()
        precondition(m.numbers.isEmpty && m.plan.mode == .pressToJoin)
        f.failWrite = true
        m.select(.add)
        await settled()
        precondition(m.numbers.isEmpty && m.message != nil)
        f.failRead = true
        await m.load()
        precondition(m.rows == [.retry] && m.focusedRow == .retry)
        screen.handleController(.cancel)
        precondition(closed == 1)
        print("Players: keyboard and controller focus, capture, twins, identify, PIN, swap, removal, merge and failure handling")
    }

    @MainActor static func checkParents() throws {
        let locale = AppLocale(language: .french, region: "FR")
        L10n.setContext(locale)
        let settings = AppSettingsStore(fileURL: AppData.supportRoot.appendingPathComponent("settings.json"))
        settings.settings.checkEngineAtLaunch = false
        settings.settings.refreshLibraryAtLaunch = false
        settings.settings.animatedBackground = false
        let profiles = LocalProfileStore(directory: AppData.supportRoot, settings: settings.settings, name: "Alex")
        AppData.preferences.set(true, forKey: AppViewModel.StorageKeys.setupCompleted)
        AppData.preferences.set(AppData.supportRoot.appendingPathComponent("Apps").path,
                                forKey: AppViewModel.StorageKeys.savedLibraryFolder)
        let game = PortedGame(name: "Sunny Coast", url: AppData.supportRoot.appendingPathComponent("Fixture.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: "0100000000000001")
        let vm = AppViewModel(settingsStore: settings,
                              catalog: .init(sources: [.init(integration: .nxnative, isEnabled: true)],
                                             games: [.init(nxnative: game)]),
                              repository: .init(store: .init(directory: AppData.supportRoot)), localProfiles: profiles)
        let router = AppRouter(settings: settings)
        let artwork = ArtworkStore()
        let size = CGSize(width: 1440, height: 810)
        func send(_ input: Notification.Name, _ actions: GamepadAction...) {
            for action in actions {
                NotificationCenter.default.post(name: input, object: action)
                RunLoop.main.run(until: Date().addingTimeInterval(0.035))
            }
        }
        func wallpaper(_ name: String, _ colors: [[UInt8]]) throws -> (String, URL) {
            let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 68,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for y in 0..<68 {
                let color = colors[(y / 14) % colors.count]
                for x in 0..<120 {
                    let offset = y * image.bytesPerRow + x * 4
                    for channel in 0..<4 { image.bitmapData![offset + channel] = color[channel] }
                }
            }
            let url = stage.appendingPathComponent(name + ".png")
            try image.representation(using: .png, properties: [:])!.write(to: url)
            return (try ThemeStore.shared.importWallpaper(from: url), url)
        }
        let bright = try wallpaper("fixture-sunny", [[87, 193, 230, 255], [255, 223, 122, 255],
                                                       [247, 245, 236, 255], [106, 191, 143, 255]])
        let dark = try wallpaper("fixture-dark", [[0, 0, 0, 255]])
        try FileManager.default.createDirectory(at: game.url, withIntermediateDirectories: true)
        let sessions = PlaySessionStore()
        let running = RunningGameMonitor()
        let storeHost = ModStoreHost()
        vm.homeSeen = true
        vm.spotlight.select(.game(game.id))

        for (name, fixture) in [("clair", bright), ("sombre", dark)] {
            settings.settings.settingsWallpaperID = fixture.0
            settings.settings.wallpaperID = fixture.0
            let backdrop = SeleneBackdropStyle(palette: ThemeStore.shared.palette, wallpaperURL: fixture.1,
                                               animated: false, brightness: .bright)
            router.openSettings(.controllers)
            let players = try withHost(SettingsView(initialSection: .controllers, viewModel: vm, settings: settings,
                                                      router: router, artwork: artwork),
                                       size: size, locale: locale, backdrop: backdrop) { host in
                let input = Notification.Name.nxSettingsGamepadAction
                try capture(host, "reglages-\(name)")
                send(input, .navigateRight, .navigateDown, .navigateDown, .navigateDown, .confirm)
                let players = try capture(host, "reglages-\(name)-joueurs")
                send(input, .cancel)
                if name == "clair" {
                    send(input, .navigateUp, .navigateUp, .confirm)
                    try capture(host, "reglages-clair-disposition")
                    send(input, .cancel)
                }
                return players
            }
            if name == "clair" {
                for (id, label) in [("appLanguage", "langue"), ("appRegion", "region")] {
                    router.openSettings(.startUp, rowID: id)
                    try withHost(SettingsView(initialSection: .startUp, viewModel: vm, settings: settings,
                                              router: router, artwork: artwork),
                                 size: size, locale: locale, backdrop: backdrop) { host in
                        send(.nxSettingsGamepadAction, .confirm)
                        _ = try capture(host, "reglages-clair-\(label)")
                    }
                }
                router.openSettings(.cloudSaves)
                try withHost(CloudSavesSettingsFixture(viewModel: vm, settings: settings, router: router, artwork: artwork),
                             size: size, locale: locale, backdrop: backdrop) { host in
                    send(.nxSettingsGamepadAction, .navigateRight, .confirm)
                    precondition(vm.settingsNotice != nil)
                    try capture(host, "reglages-clair-sauvegardes-cloud")
                    // Never choose an option: it would write game preferences.
                    vm.settingsNotice = nil
                }
            }
            router.navigate(to: .library)
            vm.gameForSettingsSheet = game
            let options = try withHost(ZStack {
                SeleneBackdrop().still(true)
                SpotlightView(viewModel: vm, router: router, settings: settings, playSessions: sessions,
                              runningGames: running, artwork: artwork, storeHost: storeHost)
                    .blur(radius: SeleneOverlayStyle.options.backdropBlur)
                    .seleneOverlayOwnership(false)
                GameOptionsView(viewModel: vm, game: game, origin: .spotlight, onClose: {}, onShowBuild: {}, onMove: {})
            }, size: size, locale: locale, backdrop: backdrop) { host in
                let input = Notification.Name.nxGameOptionsGamepadAction
                try capture(host, "jeu-\(name)-options")
                send(input, .navigateDown, .confirm)
                let players = try capture(host, "jeu-\(name)-joueurs")
                send(input, .cancel)
                if name == "clair" {
                    send(input, .navigateDown, .confirm)
                    try capture(host, "jeu-clair-edit-details")
                    send(input, .confirm)
                    try capture(host, "jeu-clair-illustrations")
                    send(input, .cancel, .navigateDown, .confirm)
                    try capture(host, "jeu-clair-metadonnees")
                    send(input, .cancel, .cancel)
                    for label in ["triches", "mods", "sauvegardes"] {
                        send(input, .navigateDown, .confirm)
                        try capture(host, "jeu-clair-\(label)")
                        send(input, .cancel)
                    }
                }
                return players
            }
            vm.gameForSettingsSheet = nil
            for (parent, image) in [("reglages", players), ("jeu", options)] {
                // Sample unoccupied canvas on both sides, outside the foreground page's content.
                let edge = [(32, 300), (1400, 180), (1400, 620)]
                let pixels = edge.flatMap { x, y in
                    Array(UnsafeBufferPointer(start: image.bitmapData! + y * image.bytesPerRow + x * 4, count: 4))
                }
                if name == "clair" {
                    referencePixels[parent] = pixels
                } else if pixels != referencePixels[parent] {
                    fputs("Players still shows the \(parent) backdrop\n", stderr)
                    leaks = true
                }
            }
        }
        if leaks { exit(1) }
        print("Players: real Controllers and Game Options routes hide both bright and dark backdrops")
    }

    @MainActor static var referencePixels: [String: [UInt8]] = [:]
    @MainActor static var leaks = false

    @MainActor static func render<V: View>(_ view: V, name: String, size: CGSize, locale: AppLocale) throws {
        try withHost(ZStack { SeleneBackdrop().still(true); view }, size: size, locale: locale) { host in
            _ = try capture(host, name)
        }
    }

    @MainActor static func withHost<V: View, Result>(_ view: V, size: CGSize, locale: AppLocale,
        backdrop: SeleneBackdropStyle = .init(), _ inspect: (NSView) throws -> Result) rethrows -> Result {
        let host = NSHostingView(rootView: view.environment(\.nxAppLocale, locale)
            .environment(\.seleneReduceMotion, true).environment(\.seleneBackdropStyle, backdrop).seleneCanvasRoot())
        host.frame.size = size
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        window.layoutIfNeeded()
        return try inspect(host)
    }

    @MainActor @discardableResult static func capture(_ host: NSView, _ name: String) throws -> NSBitmapImageRep {
        for _ in 0..<6 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            host.layoutSubtreeIfNeeded()
        }
        precondition(host.window?.isVisible == false)
        let size = host.bounds.size
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        host.cacheDisplay(in: host.bounds, to: image)
        try image.representation(using: .png, properties: [:])!.write(to: stage.appendingPathComponent(name + ".png"))
        return image
    }
}

/// The shell's usual choice card over the actual Settings row, without starting the shell's services.
struct CloudSavesSettingsFixture: View {
    @ObservedObject var viewModel: AppViewModel
    let settings: AppSettingsStore
    let router: AppRouter
    let artwork: ArtworkStore

    var body: some View {
        SettingsView(initialSection: .cloudSaves, viewModel: viewModel, settings: settings, router: router, artwork: artwork)
            .seleneOverlayOwnership(viewModel.settingsNotice == nil)
            .overlay {
                if let notice = viewModel.settingsNotice {
                    SeleneOverlay(style: .dialog) {
                        SeleneChoiceDialog(title: notice.title, message: notice.message, choices: notice.choices,
                                           focus: $viewModel.settingsNoticeFocus, cancelIndex: notice.cancelIndex,
                                           details: notice.choiceDetails, onChoose: { _ in })
                    }
                }
            }
    }
}
'''

if __name__ == "__main__":
    args = sys.argv[1:]
    details_only = "--details-only" in args
    parents_only = "--parents-only" in args
    if parents_only:
        args.remove("--parents-only")
        os.environ["PLAYERS_PARENTS_ONLY"] = "1"
    if details_only:
        args.remove("--details-only")
        os.environ["PLAYERS_DETAILS_ONLY"] = "1"
    output = Path(args[0]).resolve() if len(args) == 1 else None
    with tempfile.TemporaryDirectory(prefix="players-screen-", dir="/private/tmp") as stage:
        stage = Path(stage)
        shutil.copyfile(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf", stage / "MaterialIcons.ttf")
        os.environ["PLAYERS_STAGE"] = str(stage)
        try:
            run_host(HOST, save_model=True)
        finally:
            captures = sorted(p for p in stage.glob("*.png") if not p.name.startswith("fixture-"))
            if output:
                output.mkdir(parents=True, exist_ok=True)
                for capture in captures:
                    shutil.copyfile(capture, output / capture.name)
        assert parents_only or len(captures) == (12 if details_only else 68), len(captures)
        print(f"Rendered {len(captures)} captures" + (f": {output}" if output else ""))
