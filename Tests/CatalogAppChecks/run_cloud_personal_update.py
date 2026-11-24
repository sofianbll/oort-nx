#!/usr/bin/env python3
"""Render and exercise the real personal-update flow, using two profiles and local-only storage."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from run_cloud_screens import HOST, ROOT, capture_destination, change, isolate_cloud_init, isolate_startup

SCENARIO = r'''
        let fm = FileManager.default
        let remote = data.appendingPathComponent("personal-storage")
        try fm.createDirectory(at: remote, withIntermediateDirectories: true)
        let config = data.appendingPathComponent("empty-rclone.conf")
        try Data().write(to: config)
        let title = "FEDCBA9876543210", bundleID = "local.oort.personal-update-fixture"
        guard let rclone = RcloneStorageBackend.findExecutable() else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSDebugDescriptionErrorKey: "rclone fixture tool is not available"])
        }
        let offline = OSAllocatedUnfairLock(initialState: false)
        let backend = RcloneStorageBackend(remote: ":local:", root: remote.path, executable: rclone, config: config) { tool, args, _ in
            // No named remote, OAuth, reference commands or writes outside the fixture.
            let remotes = args.filter { $0.contains(":") && !$0.hasPrefix("--") }
            func canonical(_ path: String) -> String {
                let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
                // Foundation may retain or strip /private while resolving different children of /tmp.
                return resolved.hasPrefix("/private/tmp/") ? String(resolved.dropFirst("/private".count)) : resolved
            }
            precondition(!remotes.isEmpty && remotes.allSatisfy {
                let bundle = ":local,links=true:", personal = ":local:"
                let prefix = $0.hasPrefix(bundle) ? bundle : personal
                guard $0.hasPrefix(prefix + "/") else { return false }
                let root = canonical((prefix == bundle ? data : remote).path)
                let path = canonical(String($0.dropFirst(prefix.count)))
                return path == root || path.hasPrefix(root + "/")
            }, "Probe rejected fixture command \(args.first ?? "?"): \(remotes)")
            if args.first == "copy", offline.withLock({ $0 }) {
                return .init(status: 1, stdout: "", stderr: "connection reset")
            }
            var localArgs = args
            if let password = localArgs.firstIndex(of: "--password-command") {
                localArgs.removeSubrange(password...password + 1)
            }
            return try await SystemCommandRunner().runCancellable(tool, localArgs, environment: [:])
        }
        let scope = CloudDriveScope(remote: "fixture", account: "account-fixture",
                                    library: .init(path: "Games", id: "folder-fixture"))
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)

        func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try value() else {
                throw CocoaError(.fileReadUnknown, userInfo: [NSDebugDescriptionErrorKey: message])
            }
        }
        func until(_ predicate: () -> Bool) async throws {
            for _ in 0..<1000 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            try require(false, "Timed out waiting for the cloud transfer")
        }
        func version(_ app: URL) throws -> String? {
            let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            return (try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])?["CFBundleShortVersionString"]
        }
        func sign(_ app: URL, version: String) throws {
            let metadata = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": "Fixture", "CFBundleName": "Observatoire lunaire",
                            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version, "DMTitleID": title]
            try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--force", "--sign", "-", app.path]
            try sign.run()
            sign.waitUntilExit()
            try require(sign.terminationStatus == 0, "Could not sign the synthetic bundle")
        }
        func profile(_ name: String, installed: Bool) throws -> (AppViewModel, URL) {
            let root = data.appendingPathComponent(name)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let app = root.appendingPathComponent("Observatoire lunaire.app", isDirectory: true)
            if installed {
                try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
                try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: app.appendingPathComponent("Contents/MacOS/Fixture"))
                try sign(app, version: "1.0")
            }
            var game = PortedGame(name: "Observatoire lunaire", url: app, platform: .macApp, sizeBytes: 0,
                                  modificationDate: .now, bundleId: bundleID, titleId: title)
            game.status = installed ? .builtSourcesMissing : .appMissing
            let repository = CatalogRepository(store: .init(directory: root))
            let catalog = try repository.mergeNXNative(scanned: [game], enableSource: true)
            let vm = AppViewModel(settingsStore: .init(fileURL: root.appendingPathComponent("settings.json")),
                                  catalog: catalog, repository: repository)
            try vm.cloudLibrary.installPersonalProbe(backend, scope: scope, profile: root)
            return (vm, app)
        }
        func finish(_ vm: AppViewModel) async throws {
            let model = vm.cloudLibrary
            try require(model.active != nil, "Expected a transfer: \(model.states.values.first?.issue?.message ?? "no reason")")
            await model.active?.task.value
            await model.queueStore.flush()
        }
        func snapshot(_ vm: AppViewModel) async -> PortedGame {
            let game = vm.libraryGames.first!
            await vm.refreshCloudLibrary(game)
            return game
        }

        let (publisher, publishedApp) = try profile("publisher", installed: true)
        publisher.restoreCloudQueue()
        try await until { publisher.cloudLibrary.hasRestoredQueue }
        publisher.performCloudLibrary(.upload(.app), for: await snapshot(publisher))
        try await finish(publisher)
        let firstReceipt = publisher.cloudLibrary.personalAppReceipts.receipt(titleID: title, scope: scope)
        try require(firstReceipt != nil, "No witness after personal publication")

        let (receiver, app) = try profile("receiver", installed: false)
        let model = receiver.cloudLibrary
        try require(model.personalAppReceipts.receipt(titleID: title, scope: scope) == nil, "Profiles are sharing a witness")
        receiver.restoreCloudQueue()
        try await until { model.hasRestoredQueue }
        receiver.performCloudLibrary(.restore(.app), for: await snapshot(receiver))
        try await finish(receiver)
        try require(try version(app) == "1.0", model.states.values.first?.issue?.message ?? "Version A was not restored")
        let restoredReceipt = model.personalAppReceipts.receipt(titleID: title, scope: scope)
        try require(restoredReceipt?.inventorySHA256 == firstReceipt?.inventorySHA256, "No witness for the restored app")
        let save = try receiver.defaultSaveLocation(for: receiver.libraryGames.first!).directory(.account)
        try fm.createDirectory(at: save, withIntermediateDirectories: true)
        let sentinel = save.appendingPathComponent("sentinel")
        let originalSave = Data("synthetic save".utf8)
        try originalSave.write(to: sentinel)

        try await Task.sleep(for: .seconds(1.1)) // Publications have whole-second display dates.
        try sign(publishedApp, version: "2.0")
        publisher.performCloudLibrary(.upload(.app), for: await snapshot(publisher))
        try await finish(publisher)
        let game = await snapshot(receiver)
        guard case .update(let offer) = model.states[game.id]?.personalAppComparison else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSDebugDescriptionErrorKey: "No offer for a verified A → B"])
        }
        try require(offer.downloadBytes > 0, "Expected a priced offer")
        let panel = CloudLibraryPanel(viewModel: receiver, model: model, game: game)
        let header = SpotlightGameInfoView(game: game, logo: nil,
            presentation: .init(game: game, metadata: nil, totalPlaytime: 0, lastPlayed: nil),
            isRunning: false, focusedPill: 0, onPill: { _ in }, onHoverPill: { _ in },
            cloud: model, showsCloudPill: true)
        let s07 = output.appendingPathComponent("s07"), s08 = output.appendingPathComponent("s08")
        for path in [s07, s08] { try fm.createDirectory(at: path, withIntermediateDirectories: true) }
        let sizes = [(CGSize(width: 1440, height: 800), "wide"), (CGSize(width: 1100, height: 700), "narrow")]
        model.update(game.id) { $0.personalAppComparison = nil; $0.completedItem = nil }
        for (size, width) in sizes {
            try render("before-\(width)", s07, header.environment(\.nxAppLocale, fr), size: size)
            try render("before-\(width)", s08, panel.environment(\.nxAppLocale, fr), size: size)
        }
        model.update(game.id) { $0.personalAppComparison = .update(offer) }
        for (size, width) in sizes {
            try render("available-\(width)", s07, header.environment(\.nxAppLocale, fr), size: size)
            try render("available-\(width)", s08, panel.environment(\.nxAppLocale, fr), size: size)
        }

        receiver.performCloudLibrary(.restore(.app), for: game)
        try await finish(receiver)
        try require(try version(app) == "1.0" && model.states[game.id]?.previousApp == nil,
                    "Generic restore must not replace the local app")
        _ = await snapshot(receiver)

        func approve(cancel: Bool = false, capture: Bool = false) throws {
            receiver.reviewPersonalAppUpdate(for: game)
            guard let notice = receiver.settingsNotice else {
                throw CocoaError(.fileReadUnknown, userInfo: [NSDebugDescriptionErrorKey: "Expected an update confirmation"])
            }
            try require(notice.choices == ["Update app", "Cancel"] && receiver.settingsNoticeFocus == notice.cancelIndex,
                        "Cancel must be the default")
            if capture {
                for (size, width) in sizes {
                    try renderNotice("confirm-\(width)", s08, notice, width: size.width)
                }
            }
            receiver.settingsNotice = nil
            notice.runChoice(cancel ? notice.cancelIndex : 0)
        }
        try approve(cancel: true, capture: true)
        try require(try model.active == nil && version(app) == "1.0", "Cancel started a replacement")

        offline.withLock { $0 = true }
        try approve()
        try await finish(receiver)
        try require(try version(app) == "1.0" && model.queue.isEmpty && model.queuePause == nil,
                    "A failed personal update must not be replayed")
        offline.withLock { $0 = false }
        _ = await snapshot(receiver)

        func startWhileRunning() async throws {
            RunningGameMonitor.screenRunning.withLock { $0 = bundleID }
            try approve()
            try require(model.active?.request.entry.storage == nil && model.active?.request.sourceReference == nil,
                        "Approval must remain personal and must not survive a restart")
            try await until { model.states[game.id]?.progress?.phase == .readyToInstall }
            try require(try version(app) == "1.0" && model.states[game.id]?.previousApp == nil,
                        "An app was replaced while the game was running")
        }
        func closeFixtureGame() {
            RunningGameMonitor.screenRunning.withLock { $0 = nil }
            model.appInstallWake?.yield(())
        }
        try await startWhileRunning()
        let parked = app.deletingLastPathComponent().appendingPathComponent("Parked.app")
        try fm.moveItem(at: app, to: parked)
        try fm.copyItem(at: parked, to: app)
        let edit = app.appendingPathComponent("Contents/local-change")
        let localChange = Data("keep this local edit".utf8)
        try localChange.write(to: edit)
        closeFixtureGame()
        try await finish(receiver)
        try require(try version(app) == "1.0" && Data(contentsOf: edit) == localChange, "The changed local app was lost")
        _ = await snapshot(receiver)
        try require(model.states[game.id]?.personalAppComparison == .different, "Modified app still offers replacement")
        try require(model.states[game.id]?.issue?.message ==
                    L10n.text("The update could not be verified again. The installed app was kept.", context: fr),
                    "The stale-confirmation message must explain why the current app was kept")
        for (size, width) in sizes {
            try render("different-\(width)", s08, panel.environment(\.nxAppLocale, fr), size: size)
        }
        try fm.removeItem(at: app) // Only the test copy; the original fixture was parked.
        try fm.moveItem(at: parked, to: app)
        _ = await snapshot(receiver)

        try await startWhileRunning()
        for (size, width) in sizes {
            try render("waiting-\(width)", s08, panel.environment(\.nxAppLocale, fr), size: size)
        }
        closeFixtureGame()
        try await finish(receiver)
        let backup = model.states[game.id]?.previousApp
        try require(try version(app) == "2.0" && backup.flatMap { try version($0) } == "1.0",
                    model.states[game.id]?.issue?.message ?? "Expected B installed and A recoverable")
        try require(try Data(contentsOf: sentinel) == originalSave && fm.contentsOfDirectory(atPath: save.path) == ["sentinel"],
                    "The save sentinel was modified")
        let ready = await snapshot(receiver)
        try require(ready.isPlayableLocally && model.states[game.id]?.personalAppComparison == .current,
                    "The restored app must remain playable and match the personal cloud")
        for (size, width) in sizes {
            try render("kept-\(width)", s08, panel.environment(\.nxAppLocale, fr), size: size)
        }
        print("Personal A → B: consent, refusal, failure, changed copy, wait, recovery and unchanged save verified.")
    }
'''


def main():
    output = capture_destination("personal-update-captures-")
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="personal-update-") as temporary:
        package = Path(temporary)
        shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
        shutil.copytree(ROOT / "Sources", package / "Sources")
        for name in ("NXLibraryCoreTests", "ArcanePortingTests", "OortCoreTests"):
            folder = package / "Tests" / name
            folder.mkdir(parents=True)
            (folder / "Empty.swift").touch()
        app = package / "Sources/NXLibrary"
        change(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        vm = app / "ViewModels/AppViewModel.swift"
        change(vm, r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        change(vm, r"let root = SystemDetector.shared.resolveRootDirectory\(\)", "let root = AppData.profile.home")
        isolate_startup(app, keep_catalog=True)
        profile = package / "Sources/NXLibraryCore/App/AppDataProfile.swift"
        change(profile, r"public static let profile = [^\n]*",
               'public static let profile = AppDataProfile(home: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!), isDevelopment: true)')
        change(profile, r"public static var preferences: UserDefaults \{ [^\n]+ \}",
               'public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        model = app / "ViewModels/AppViewModel+CloudLibrary.swift"
        change(model, r"let personalAppReceipts = ", "var personalAppReceipts = ")
        isolate_cloud_init(model,
               '        preference = .init(storage: "fixture:Games", enabled: true, sourcesRoot: nil)\n'
               '        chosenExecutable = nil\n        needsDriveToolChoice = true\n')
        with model.open("a") as swift:
            swift.write(r'''
extension CloudLibraryModel {
    @MainActor func installPersonalProbe(_ fixture: RcloneStorageBackend, scope: CloudDriveScope, profile: URL) throws {
        AppData.preferences.set(preference.storage, forKey: CloudLibraryPreference.storageKey)
        AppData.preferences.set(preference.enabled, forKey: CloudLibraryPreference.enabledKey)
        AppData.preferences.set(try JSONEncoder().encode(scope), forKey: Self.scopeKey)
        installScope(scope, backend: fixture)
        personalAppReceipts = .init(in: profile)
    }
}
''')
        monitor = app / "Services/RunningGameMonitor.swift"
        change(monitor, r"import AppKit", "import AppKit\nimport os")
        change(monitor, r"    nonisolated static func runningApplication\(bundleID: String\).*?\n    }", '''
    nonisolated static let screenRunning = OSAllocatedUnfairLock<String?>(initialState: nil)
    nonisolated static func runningApplication(bundleID: String) -> NSRunningApplication? {
        screenRunning.withLock { $0 == bundleID } ? .current : nil
    }'''.lstrip("\n"))
        change(app / "Views/Detail/CloudLibraryPanel.swift", r"        \.task\(id: ReadRequest.*?\n", "")
        change(app / "Views/Spotlight/SpotlightInfoView.swift",
               r'        \.onAppear \{ reveal\(\) \}\n        \.onChange\(of: game.id\) \{ reveal\(\) \}\n', "")
        preamble = HOST.split("        // SCENARIO", 1)[0].replace("import SwiftUI", "import SwiftUI\nimport os")
        renderer = HOST[HOST.index("    @MainActor static func renderNotice"):]
        renderer = renderer.replace("/* NOTICE_LAYOUT */", "cancelIndex: notice.cancelIndex,")
        renderer = renderer.replace("SeleneCanvas(size: .init(width: 1920, height: 1080))", "SeleneCanvas(size: size)")
        renderer = renderer.replace("Color(red: 0.09, green: 0.13, blue: 0.20)", "SeleneTheme.baseGradient")
        (app / "PersonalUpdateScreenProbe.swift").write_text(preamble + SCENARIO + renderer)
        home = package / "fixture-home"
        home.mkdir()
        subprocess.run(["swift", "run", "--jobs", "4", "--package-path", str(package), "NXLibrary", str(output),
                        str(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"), str(ROOT / "Resources/AppIcon-Light.png")],
                       check=True, env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))


if __name__ == "__main__":
    main()
