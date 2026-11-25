#!/usr/bin/env python3
"""Render the screens that show Nextendo player counts, for each "Online players" choice.

usage: run_online_players.py [--before] [OUTPUT]
Real Spotlight, Collection, game page and Settings views in a window that is never shown, with synthetic games and
counts: no account, no network. --before renders a build without the setting.
Run the debug Swift suite first.
"""
from pathlib import Path
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

@main struct OnlinePlayersProbe {
    static let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!, isDirectory: true)
        .appendingPathComponent("captures", isDirectory: true)
    static let french = AppLocale(language: .french, region: "FR")

    @MainActor static func main() async throws {
        assertFixtureHome()
        suppressProbeNotifications()
        let resources = Bundle.main.resourceURL!
        let selene = resources.appendingPathComponent("Selene", isDirectory: true)
        try FileManager.default.createDirectory(at: selene, withIntermediateDirectories: true)
        let palettes = selene.appendingPathComponent("palettes.json")
        if !FileManager.default.fileExists(atPath: palettes.path) {
            try FileManager.default.copyItem(atPath: "__ROOT__/Resources/Selene/palettes.json", toPath: palettes.path)
        }
        precondition(CTFontManagerRegisterFontsForURL(
            URL(fileURLWithPath: "__ROOT__/Resources/Selene/Fonts/MaterialIcons-Regular.ttf") as CFURL, .process, nil))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        L10n.setContext(french)
        let data = AppData.supportRoot
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        settings.settings.interfaceSounds = false
        settings.settings.soundVolume = 0
        SoundEffectService.shared.bind(to: settings)
        settings.settings.appLanguage = .french
        settings.settings.introAnimation = false
        settings.settings.showClock = false
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        // White, dark and busy covers: the dot must read on each.
        let covers: [(String, [Color])] = [("Observatoire blanc", [.white, .white]),
                                           ("Observatoire nuit", [.black, .black]),
                                           ("Observatoire prairie", [.green, .yellow]),
                                           ("Observatoire calme", [.blue, .purple])]
        let artwork = ArtworkStore(cacheDirectory: data.appendingPathComponent("art"))
        var games: [PortedGame] = []
        for (index, cover) in covers.enumerated() {
            let app = data.appendingPathComponent("Fixture\(index).app")
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"),
                                                    withIntermediateDirectories: true)
            var game = PortedGame(name: cover.0, url: app, platform: .macApp, sizeBytes: 1_000_000_000,
                                  modificationDate: Date(timeIntervalSince1970: 1_790_000_000),
                                  titleId: String(format: "010%013X", index + 1))
            // A ready app: a game still to build or find shows that mark in the corner instead.
            game.status = .built
            games.append(game)
            let face = ImageRenderer(content: LinearGradient(colors: cover.1, startPoint: .topLeading,
                endPoint: .bottomTrailing).frame(width: 460, height: 460)).cgImage!
            let image = NSImage(cgImage: face, size: .init(width: 460, height: 460))
            TileArtMemo.store(image, for: "nxnative|\(game.id)" as NSString)
            CoverArtMemo.shared.setObject(image, forKey: CoverArtMemo.key(game.id, revision: ArtworkPicks.shared.revision))
            let hero = artwork.cacheDirectory.appendingPathComponent(CatalogGame(nxnative: game).personalizationKey)
                .appendingPathComponent("hero.png")
            try FileManager.default.createDirectory(at: hero.deletingLastPathComponent(), withIntermediateDirectories: true)
            try NSBitmapImageRep(cgImage: face).representation(using: .png, properties: [:])!.write(to: hero)
        }
        vm.homeSeen = true
        vm.applyCatalog(.init(sources: [.init(integration: .nxnative, isEnabled: true)],
                              games: games.map { CatalogGame(nxnative: $0) }))
        // The last game has nobody online: no dot, no line.
        let counts = [games[0].titleId!.lowercased(): 128, games[1].titleId!.lowercased(): 12,
                      games[2].titleId!.lowercased(): 3]
        let history = PlaySessionStore(fileURL: data.appendingPathComponent("history.json"))
        let selected = games[0]
        vm.spotlight.selectedKey = SpotlightItem.game(selected.id).key
        vm.spotlight.startingTabApplied = true
        vm.librarySelection.selectedGameID = selected.id

        /*VARIANTS*/
        for (suffix, mode) in variants {
            func shot<V: View>(_ name: String, _ view: V, size: CGSize = .init(width: 1440, height: 810),
                               after: [GamepadAction] = []) throws {
                try capture(name + suffix, view
                    .environment(\.onlinePlayersByTitle, counts)
                    /*DISPLAY*/, size: size, after: after)
            }
            vm.librarySelection.selectedGameID = selected.id
            vm.spotlight.selectedKey = SpotlightItem.game(selected.id).key
            func home() -> SpotlightView {
                SpotlightView(viewModel: vm, router: AppRouter(), settings: settings, playSessions: history,
                              runningGames: RunningGameMonitor(), artwork: artwork, storeHost: ModStoreHost())
            }
            try shot("spotlight", home())
            // The same game's details on the Spotlight page, down to its Details column.
            _ = vm.spotlight.showGameDetails()
            vm.spotlight.focus = .actions
            try shot("spotlight-details", home())
            vm.spotlight.focus = .row
            try shot("collection", CollectionView(viewModel: vm, router: AppRouter(), settings: settings,
                playSessions: history, artwork: artwork))
            func page() -> GameDetailView {
                GameDetailView(viewModel: vm, setup: vm.setup, store: vm.store, router: AppRouter(), settings: settings,
                               playSessions: history, runningGames: RunningGameMonitor(), artwork: artwork, game: selected)
            }
            try shot("fiche", page())
            // Down twice: past the screenshots to the Details block.
            try shot("fiche-details", page(), after: [.navigateDown, .navigateDown])
            /*SETTINGS*/
        }
        /*PALETTES*/
        print("Online players screens rendered.")
    }

    @MainActor static func capture<V: View>(_ name: String, _ view: V, size: CGSize,
                                            after: [GamepadAction] = []) throws {
        let host = NSHostingView(rootView: ZStack { SeleneBackdrop().still(true); view }
            .environment(\.nxAppLocale, french)
            .environment(\.seleneReduceMotion, true)
            .environment(\.seleneButtonNames, .xbox)
            .seleneCanvasRoot())
        host.frame.size = size
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        window.layoutIfNeeded()
        func settle(_ turns: Int) {
            for _ in 0..<turns {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
            }
        }
        settle(30)
        for action in after {
            NotificationCenter.default.post(name: .nxDetailGamepadAction, object: action)
            settle(10)
        }
        precondition(host.window?.isVisible == false)
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        host.cacheDisplay(in: host.bounds, to: image)
        try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
    }
}
'''

SETTINGS = r'''
            settings.settings.onlinePlayersDisplay = mode
            try shot("reglages", SettingsView(initialSection: .multiplayer, viewModel: vm, settings: settings,
                                              router: AppRouter(), artwork: artwork))
            settings.settings.onlinePlayersDisplay = .dot
'''

PALETTES = r'''
        for palette in ["oort", "catppuccin-latte", "white"] {
            ThemeStore.shared.apply(id: palette)
            try capture("point-palette-\(palette)", CollectionCoverRow(
                games: games.map { CatalogGame(nxnative: $0) }, selectedID: selected.id, artwork: artwork,
                boxArt: vm.boxArt, boxArtIndexVersion: 0, officialName: { _ in nil }, needsMetadata: { _ in },
                cloud: vm.cloudLibrary, showsCloudBadges: true, onSelect: { _ in }, onActivate: { _ in })
                .environment(\.onlinePlayersByTitle, counts), size: .init(width: 960, height: 400))
        }
'''

if __name__ == "__main__":
    args = sys.argv[1:]
    before = "--before" in args
    if before:
        args.remove("--before")
    host = HOST.replace("__ROOT__", str(ROOT))
    if before:
        host = (host.replace("/*VARIANTS*/", 'let variants = [("-avant", 0)]')
                .replace("for (suffix, mode) in variants", "for (suffix, _) in variants")
                .replace("/*DISPLAY*/", "")
                .replace("/*SETTINGS*/", 'try shot("reglages", SettingsView(initialSection: .multiplayer, viewModel: vm, '
                         'settings: settings, router: AppRouter(), artwork: artwork))')
                .replace("/*PALETTES*/", ""))
    else:
        host = (host.replace("/*VARIANTS*/", 'let variants: [(String, OnlinePlayersDisplay)] = '
                             '[("-A-point", .dot), ("-B-jeu-choisi", .selectedGame), '
                             '("-C-fiche", .gamePage), ("-D-jamais", .never)]')
                .replace("/*DISPLAY*/", r".environment(\.onlinePlayersDisplay, mode)")
                .replace("/*SETTINGS*/", SETTINGS)
                .replace("/*PALETTES*/", PALETTES))
    with tempfile.TemporaryDirectory(prefix="online-players-", dir="/private/tmp") as temp:
        output = Path(args[0]).resolve() if args else Path(temp)
        run_host(host, save_model=True, capture=output)
        count = len(list(output.glob("*-avant.png" if before else "*-[ABCD]-*.png")))
        assert count == (6 if before else 24), count
        print(f"{count} captures: {output}")
