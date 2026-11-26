import AppKit
import SwiftUI
import NXLibraryCore
import ArcanePorting

extension ProfileScreenProbe {
    @MainActor static func checkMacShortcuts(in out: URL, refs: URL) async throws {
        let data = AppData.supportRoot.appendingPathComponent("MacShortcutProbe", isDirectory: true)
        let fm = FileManager.default
        let original = data.appendingPathComponent("Paper Racer.app", isDirectory: true)
        let contents = original.appendingPathComponent("Contents", isDirectory: true)
        let executable = contents.appendingPathComponent("MacOS/Fixture")
        let icon = contents.appendingPathComponent("Resources/Fixture.icns")
        let marker = out.appendingPathComponent("mac-launch-marker.txt")
        try fm.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: icon.deletingLastPathComponent(), withIntermediateDirectories: true)
        let source = data.appendingPathComponent("fixture.c")
        try Data("""
            #include <stdio.h>
            #include <unistd.h>
            int main(void) {
                FILE *f = fopen(FIXTURE_MARKER, "w");
                if (!f) return 1;
                fputs("paper-racer-launch-services\\n", f);
                fclose(f);
                usleep(250000);
                return 0;
            }
            """.utf8).write(to: source)
        func tool(_ path: String, _ args: [String]) throws {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: path)
            child.arguments = args
            try child.run()
            child.waitUntilExit()
            precondition(child.terminationStatus == 0, "Failed: \(path)")
        }
        try tool("/usr/bin/clang", [source.path, "-DFIXTURE_MARKER=\"\(marker.path)\"", "-o", executable.path])
        let png = data.appendingPathComponent("icon.png")
        try save(bitmap(ZStack {
            RoundedRectangle(cornerRadius: 58).fill(.indigo.gradient)
            Image(systemName: "paperplane.fill").font(.system(size: 142, weight: .semibold)).foregroundStyle(.white)
        }.padding(10).frame(width: 256, height: 256)), to: png)
        try tool("/usr/bin/sips", ["-s", "format", "icns", png.path, "--out", icon.path])
        let info: [String: Any] = [
            "CFBundlePackageType": "APPL", "CFBundleExecutable": "Fixture", "CFBundleDisplayName": "Paper Racer",
            "CFBundleIdentifier": "example.oort.paper-racer.\(UUID())", "CFBundleIconFile": "Fixture.icns",
            "CFBundleVersion": "1", "LSBackgroundOnly": true,
        ]
        let plist = contents.appendingPathComponent("Info.plist")
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        let paths = ["Contents/Info.plist", "Contents/MacOS/Fixture", "Contents/Resources/Fixture.icns"]
        let originalBytes = try paths.map { try Data(contentsOf: original.appendingPathComponent($0)) }

        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        settings.settings.visibleSpotlightCards = [.collection]
        let profiles = LocalProfileStore(directory: data, settings: settings.settings, name: "Player fixture")
        let owner = profiles.active!
        let repo = CatalogRepository(store: .init(directory: data))
        let vm = AppViewModel(settingsStore: settings, catalog: try repo.load(), repository: repo)
        vm.localProfiles = profiles
        let history = PlaySessionStore(fileURL: data.appendingPathComponent("sessions.json"))
        vm.playSessionStore = history
        let art = ArtworkStore(cacheDirectory: data.appendingPathComponent("art"))
        let sources = CatalogSourcesModel(repository: repo, initialConfiguration: .init(integration: .steam)) { _ in }
        vm.homeSeen = true
        vm.spotlight.startingTabApplied = true
        vm.librarySelection.query.filter = .all
        let router = AppRouter()
        router.setInitialRoute(.library)
        vm.router = router

        var sent: [URL] = []
        var complete: (@MainActor (Bool) -> Void)?
        vm.macShortcuts = MacShortcutAdapter(app: vm) { url, done in sent.append(url); complete = done }
        precondition(!vm.macShortcuts.acceptDrop([source]))
        let broken = data.appendingPathComponent("Not really an app.app", isDirectory: true)
        try fm.createDirectory(at: broken, withIntermediateDirectories: true)
        expect(!vm.macShortcuts.acceptDrop([broken]) && vm.visibleCatalogGames.isEmpty,
               "A drop rejected by application validation must not report success")
        vm.settingsNotice = nil
        precondition(vm.macShortcuts.acceptDrop([original]))
        let game = vm.visibleCatalogGames.first!
        vm.macShortcuts.add(at: original)
        precondition(vm.visibleCatalogGames.map(\.id) == [game.id])
        let reloaded = try repo.load()
        precondition(reloaded.games == [game])
        vm.spotlight.select(.game(game.id))
        vm.librarySelection.selectedGameID = game.id
        func spotlight() -> SpotlightView {
            SpotlightView(viewModel: vm, router: router, settings: settings, playSessions: history,
                          runningGames: RunningGameMonitor(), artwork: art, storeHost: ModStoreHost())
        }
        func collection() -> CollectionView {
            CollectionView(viewModel: vm, router: router, settings: settings, playSessions: history, artwork: art)
        }
        let row = spotlight()
        precondition(row.selectedPillCount == 2)
        vm.spotlight.setPillLimit(row.selectedPillCount)
        row.handle(.navigateDown)
        row.handle(.navigateRight)
        row.handle(.navigateRight)
        precondition(vm.spotlight.focus == .pills && vm.spotlight.pillIndex == 1, "No third invisible control")
        row.handle(.confirm)
        precondition(vm.settingsNotice?.title == "Tile options")
        vm.settingsNotice = nil
        row.handle(.navigateUp)
        row.handle(.confirm)
        precondition(sent.count == 1 && sent[0] == game.macShortcut?.url)
        precondition(vm.play(game) == .refused(.launchInProgress))
        complete?(true); complete = nil
        router.setInitialRoute(.collection)
        collection().handle(.confirm)
        precondition(sent.count == 2)
        complete?(true); complete = nil
        collection().handle(.contextAction)
        precondition(vm.settingsNotice?.title == "Tile options")
        vm.settingsNotice = nil
        router.setInitialRoute(.library)

        vm.profileOwnsInput = true
        precondition(vm.play(game) == .refused(.profileLocked))
        precondition(!vm.macShortcuts.acceptDrop([original]))
        vm.profileOwnsInput = false
        precondition(profiles.beginGuest(.init(name: "Guest fixture", look: owner.look)))
        precondition(vm.play(game) == .refused(.guestUnsupported) && sent.count == 2)
        precondition(!vm.macShortcuts.acceptDrop([original]))
        precondition(profiles.choose(owner.id))
        vm.settingsNotice = nil
        var events: [PlayEvent] = []
        precondition(vm.play(game) { events.append($0) } == .accepted(.pending))
        complete?(false); complete = nil
        precondition(events == [.result(.refused(.handoffRejected))] && vm.settingsNotice?.title == "Could not open the Mac app")
        vm.settingsNotice = nil

        let variants: [(String, AppLocale, CGSize, ButtonNameStyle)] = [
            ("en-wide", .init(language: .english, region: "US"), .init(width: 1440, height: 810), .xbox),
            ("fr-wide", .init(language: .french, region: "FR"), .init(width: 1440, height: 810), .xbox),
            ("en-narrow", .init(language: .english, region: "US"), .init(width: 900, height: 780), .automatic),
            ("fr-narrow", .init(language: .french, region: "FR"), .init(width: 900, height: 780), .automatic),
        ]
        func dialog(_ notice: SettingsNotice) -> some View {
            ZStack {
                spotlight().seleneOverlayOwnership(false)
                SeleneOverlay(style: .dialog) {
                    SeleneChoiceDialog(title: notice.title, message: notice.message, answers: notice.answers,
                                       focus: .constant(notice.defaultAnswer), onCancel: {}, onAnswer: { _ in })
                }
            }
        }
        for (label, locale, size, buttons) in variants {
            L10n.setContext(locale)
            func shot(_ name: String, _ view: some View) throws {
                try render("mac-\(name)-\(label)", view.environment(\.nxAppLocale, locale),
                           in: out, refs, "none", names: buttons, size: size)
            }
            try shot("sources", SettingsView(initialSection: .sources, viewModel: vm, settings: settings,
                                             router: AppRouter(), artwork: art).environmentObject(sources))
            try shot("spotlight", spotlight())
            try shot("collection", collection())
            vm.macShortcuts.showTileOptions(game)
            let options = vm.settingsNotice!
            try shot("options", dialog(options))
            vm.settingsNotice = nil
            precondition(options.choices == ["Remove tile", "Back", "Choose image…"] && options.defaultAnswer == .retry)
            options.runAnswer(options.answers.first { $0.role == .destructive }!.id)
            precondition(vm.visibleCatalogGames.isEmpty && vm.settingsNotice == nil)
            let offer = vm.undoOffers.offer!
            try shot("removed", UndoNotice(message: offer.message, onUndo: {}))
            precondition(vm.undoOffers.perform() && vm.visibleCatalogGames.map(\.id) == [game.id])
        }

        let personalImage = data.appendingPathComponent("manual.png")
        try save(bitmap(ZStack {
            LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "sparkles").font(.system(size: 94)).foregroundStyle(.white)
        }.frame(width: 360, height: 480)), to: personalImage)
        let picks = ArtworkPicks.shared
        let pick = try picks.save(Data(contentsOf: personalImage), titleID: game.personalizationKey, slot: .cover)
        let picked = await GameArtLoader.decode(at: pick, maxPixelSize: 900)
        precondition(picked != nil)
        // ImageRenderer does not run view tasks; seed the same decoded image read by the real tile on first draw.
        TileArtMemo.store(picked!, for: "mac|\(game.personalizationKey)|\(picks.revision)" as NSString)
        let (_, locale, size, buttons) = variants.last!
        try render("mac-collection-custom-fr-narrow", collection().environment(\.nxAppLocale, locale),
                   in: out, refs, "none", names: buttons, size: size)

        let moved = data.appendingPathComponent("Moved Paper Racer.app", isDirectory: true)
        try fm.moveItem(at: original, to: moved)
        for (label, locale, size, buttons) in variants {
            L10n.setContext(locale)
            let before = sent.count
            precondition(vm.play(game) == .refused(.installationMissing) && sent.count == before)
            let locate = vm.settingsNotice!
            precondition(locate.actionTitle == "Locate the app…")
            try render("mac-locate-\(label)", dialog(locate).environment(\.nxAppLocale, locale),
                       in: out, refs, "none", names: buttons, size: size)
            vm.settingsNotice = nil
        }
        vm.macShortcuts.relink(game.id, at: moved)
        let sameTile = vm.visibleCatalogGames.first!
        precondition(sameTile.id == game.id && sameTile.personalizationKey == game.personalizationKey)
        let handedOff = await CheckMacHandoff.openOnlyFixture(vm, game: sameTile, marker: marker)
        precondition(handedOff)
        precondition(history.sessions.isEmpty && history.totalDuration(for: game.id) == 0 && history.lastPlayed(for: game.id) == nil)
        precondition(vm.launchOverlay == nil && vm.launchingGameId == nil && vm.runningGameMonitor == nil)
        vm.macShortcuts.showTileOptions(sameTile)
        let options = vm.settingsNotice!
        vm.settingsNotice = nil
        options.runAnswer(options.answers.first { $0.role == .destructive }!.id)
        precondition(vm.visibleCatalogGames.isEmpty && vm.settingsNotice == nil)
        let unchanged = try paths.map { try Data(contentsOf: moved.appendingPathComponent($0)) }
        precondition(unchanged == originalBytes)
        print("Mac shortcut checks passed: selection, controller, profile refusals, relink, local art, real handoff, no session and unchanged bundle")
    }
}

@MainActor private enum CheckMacHandoff {
    static func openOnlyFixture(_ vm: AppViewModel, game: CatalogGame, marker: URL) async -> Bool {
        guard let shortcut = game.macShortcut,
              shortcut.bundleIdentifier.hasPrefix("example.oort.paper-racer."),
              shortcut.url.lastPathComponent == "Moved Paper Racer.app",
              !FileManager.default.fileExists(atPath: marker.path) else { return false }
        vm.playRouter = GamePlay([MacShortcutAdapter(app: vm)])
        var events: [PlayEvent] = []
        guard vm.play(game, observe: { events.append($0) }) == .accepted(.pending) else { return false }
        let deadline = ContinuousClock.now + .seconds(8)
        while ContinuousClock.now < deadline {
            if !events.isEmpty,
               (try? String(contentsOf: marker, encoding: .utf8)) == "paper-racer-launch-services\n" {
                return events == [.result(.accepted(.handedOff))]
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        print("Mac fixture handoff \(events); marker exists: \(FileManager.default.fileExists(atPath: marker.path))")
        return false
    }
}
