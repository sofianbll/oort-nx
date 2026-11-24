#!/usr/bin/env python3
"""Exercise pause through the real view model and render the French Selene rows."""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from run_cloud_screens import HOST, ROOT, change

SCENARIO = r'''
        let fm = FileManager.default
        let remote = data.appendingPathComponent("remote")
        let destination = data.appendingPathComponent("destination")
        for dir in [remote, destination] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        let repository = CatalogRepository(store: .init(directory: data))
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let ids = ["A000000000000001", "A000000000000002"]
        let games = zip(ids, ["Observatoire lunaire", "Jardin orbital"]).map { title, name in
            var game = PortedGame(name: name, url: destination.appendingPathComponent("\(title).app"),
                                  platform: .macApp, sizeBytes: 0, modificationDate: .now,
                                  bundleId: "local.arcane.pause.\(title)", titleId: title)
            game.status = .appMissing
            return game
        }
        _ = try repository.mergeNXNative(scanned: games, enableSource: true)
        let rclone = try require(RcloneStorageBackend.findExecutable(), "Local rclone fixture unavailable")
        let config = data.appendingPathComponent("rclone.conf")
        try Data().write(to: config)
        let scope = CloudDriveScope(remote: "fixture", account: "account-a", library: .init(path: "Games", id: "folder-a"))
        let transport = OSAllocatedUnfairLock(initialState: (hold: false, offline: false, copies: 0))
        let backend = RcloneStorageBackend(remote: ":local:", root: remote.path, executable: rclone, config: config) {
            tool, args, _ in
            func canonical(_ path: String) -> String {
                let path = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
                return path.hasPrefix("/private/tmp/") ? String(path.dropFirst("/private".count)) : path
            }
            let remotes = args.filter { $0.contains(":") && !$0.hasPrefix("--") }
            precondition(!remotes.isEmpty && remotes.allSatisfy {
                let prefix = $0.hasPrefix(":local,links=true:") ? ":local,links=true:" : ":local:"
                guard $0.hasPrefix(prefix + "/") else { return false }
                return canonical(String($0.dropFirst(prefix.count))).hasPrefix(canonical(data.path) + "/")
            }, "Probe refused a command outside its local fixture: \(remotes)")
            if args.first == "copy" {
                transport.withLock { $0.copies += 1 }
                while transport.withLock({ $0.hold }) { try await Task.sleep(for: .milliseconds(20)) }
                if transport.withLock({ $0.offline }) {
                    return .init(status: 1, stdout: "", stderr: "connection reset")
                }
            }
            var localArgs = args
            if let index = localArgs.firstIndex(of: "--password-command") { localArgs.removeSubrange(index...index + 1) }
            return try await SystemCommandRunner().runCancellable(tool, localArgs, environment: [:])
        }
        for game in games {
            let app = data.appendingPathComponent("fixture-\(game.titleId!).app")
            let exec = app.appendingPathComponent("Contents/MacOS/Fixture")
            try fm.createDirectory(at: exec.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: exec)
            let plist = ["CFBundleIdentifier": game.bundleId!, "CFBundleExecutable": "Fixture",
                         "CFBundlePackageType": "APPL", "DMTitleID": game.titleId!]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--force", "--sign", "-", app.path]
            try sign.run()
            sign.waitUntilExit()
            precondition(sign.terminationStatus == 0)
            _ = try await CloudGameArchive(backend: backend).upload(
                .init(titleID: game.titleId!, locations: [.app: app]), kinds: [.app], progress: nil)
        }
        func reopen() async throws -> AppViewModel {
            let catalog = try repository.load()
            let vm = AppViewModel(settingsStore: settings, catalog: catalog, repository: repository)
            vm.applyCatalog(catalog)
            try vm.cloudLibrary.installPauseFixture(backend, scope: scope)
            await vm.restoreActivity()
            vm.restoreCloudQueue()
            try await until("Restoring the queue") { vm.cloudLibrary.hasRestoredQueue && !vm.cloudLibrary.isRestoringQueue }
            return vm
        }
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
        func activity(_ name: String, _ vm: AppViewModel, _ row: ActivityCenterFocus.Row, command: String?) throws {
            var focus = ActivityCenterFocus()
            focus.selected = row
            let view = ActivityCenterView(viewModel: vm, porting: vm.porting, cloudLibrary: vm.cloudLibrary, focus: focus,
                onFocus: { _ in }, onOpen: { vm.activateCloudActivityRow($0) }, onCancel: { _ in }, onBack: {}, onOutside: {})
            precondition(view.pauseCommandForProbe(row) == command)
            try render(name, output, view.environment(\.nxAppLocale, fr), size: .init(width: 1440, height: 820))
        }
        var vm = try await reopen()
        var model = vm.cloudLibrary
        let ordered = vm.libraryGames.sorted { $0.titleId! < $1.titleId! }
        let a = ordered[0], b = ordered[1]
        let initialCopies = transport.withLock { $0.hold = true; return $0.copies }
        vm.performCloudLibrary(.restore(.app), for: a)
        vm.performCloudLibrary(.restore(.app), for: b)
        let head = try require(model.active?.request.token, "A was not started")
        let next = try require(model.queue.first?.token, "B was not queued")
        try await until("A downloading", diagnostic: {
            "active=\(String(describing: model.active?.request.name)) phase=\(String(describing: model.states[a.id]?.progress?.phase)) copies=\(transport.withLock { $0.copies }) issue=\(String(describing: model.states[a.id]?.issue)) results=\(vm.activityResults.entries.map(\.outcome))"
        }) { model.canPause(head) && transport.withLock { $0.copies > initialCopies } }
        let livePanel = CloudLibraryPanel(viewModel: vm, model: model, game: a)
        livePanel.requirePauseCommandForProbe("Pause")
        try activity("activite-telechargement-fr", vm, .cloud(head), command: "Pause")
        try render("fiche-telechargement-fr", output, livePanel.environment(\.nxAppLocale, fr),
                   size: .init(width: 1440, height: 920))
        livePanel.activatePauseCommandForProbe()
        try await until("A paused") { model.active == nil && model.queue.first?.isUserPaused == true }
        let firstSnapshot = transport.withLock { $0.copies }
        let saved = model.queue.first!.entry
        precondition(saved.approvedDestination == [a.url.resolvingSymlinksInPath().standardizedFileURL.path] &&
                     model.queue.map(\.token) == [head, next])
        precondition(!vm.activityResults.entries.contains { $0.id == head }, "Pause is not cancellation")
        await model.stopForQuit()?.value

        vm = try await reopen()
        model = vm.cloudLibrary
        transport.withLock { $0.hold = false }
        precondition(model.active == nil && model.queue.map(\.token) == [head, next])
        vm.retryCloudCheck()
        precondition(model.active == nil && model.queue.first?.entry == saved &&
                     transport.withLock { $0.copies } == firstSnapshot,
                     "A restored network must not resume a user-paused download")
        let pausedPanel = CloudLibraryPanel(viewModel: vm, model: model, game: a)
        pausedPanel.requirePauseCommandForProbe("Resume")
        try render("fiche-en-pause-fr", output, pausedPanel.environment(\.nxAppLocale, fr),
                   size: .init(width: 1440, height: 920))
        try activity("activite-en-pause-fr", vm, .queuedCloud(head), command: "Resume")
        let tileState = try require(model.states[a.id], "No paused tile state")
        precondition(tileState.coverLook(.toDownload) == .toDownload)
        try render("tuile-en-pause-fr", output,
            CollectionCoverRow(games: [.init(nxnative: a)], selectedID: a.id,
                artwork: ArtworkStore(), boxArt: vm.boxArt, boxArtIndexVersion: 0, officialName: { _ in nil },
                needsMetadata: { _ in }, tileLook: { _ in .toDownload }, cloud: model, showsCloudBadges: true,
                onSelect: { _ in }, onActivate: { _ in })
            .environment(\.nxAppLocale, fr), size: .init(width: 1440, height: 810),
            crop: CGRect(x: 24, y: 242, width: 212, height: 326))

        let unapproved = RcloneStorageBackend(remote: ":local:", root: remote.path,
            executable: URL(fileURLWithPath: "/usr/bin/true")) { _, _, _ in preconditionFailure("Used unapproved tool") }
        try model.installPauseFixture(unapproved, scope: scope)
        vm.resumeCloudTransfer(head)
        precondition(vm.settingsNotice != nil && model.active == nil && model.queue.first?.entry == saved)
        vm.settingsNotice = nil
        let changedScope = CloudDriveScope(remote: "fixture", account: "account-b", library: scope.library)
        try model.installPauseFixture(backend, scope: changedScope)
        vm.resumeCloudTransfer(head)
        precondition(vm.settingsNotice != nil && model.active == nil && model.queue.first?.entry == saved)
        vm.settingsNotice = nil
        try model.installPauseFixture(backend, scope: scope)

        // Simulate a Finder launch without launching a game or writing any game preferences.
        RunningGameMonitor.pauseProbeRunning.withLock { $0 = a.bundleId }
        vm.activateCloudActivityRow(.queuedCloud(head))
        try await until("A waiting to install") { model.states[a.id]?.progress?.phase == .readyToInstall }
        vm.pauseCloudTransfer(head)
        precondition(model.active?.request.isUserPaused == false && model.queue.map(\.token) == [next])
        try activity("activite-installation-fr", vm, .cloud(head), command: nil)
        RunningGameMonitor.pauseProbeRunning.withLock { $0 = nil }
        model.appInstallWake?.yield()
        try await until("Finish A then B") { model.active == nil && model.queue.isEmpty }
        precondition(fm.fileExists(atPath: a.url.path) && fm.fileExists(atPath: b.url.path))
        precondition(vm.activityResults.entries.filter { $0.id == head || $0.id == next }.map(\.id) == [next, head])
        precondition(vm.activityResults.entries.filter { $0.id == head || $0.id == next }.allSatisfy { $0.outcome == .succeeded })

        try fm.removeItem(at: a.url)
        try fm.removeItem(at: b.url)
        let changed = destination.appendingPathComponent("changed.app")
        _ = try repository.updateNXNative(id: a.id) { $0.url = changed; $0.status = .appMissing }
        var old = saved
        old.approvedDestination = nil
        let queued = CloudTransferQueue.Entry(id: b.id, action: .restore(.app), token: UUID(),
            storage: saved.storage, driveScope: saved.driveScope, toolIdentity: saved.toolIdentity)
        model.queueStore.save([old, queued])
        await model.stopForQuit()?.value
        vm = try await reopen()
        model = vm.cloudLibrary
        vm.resumeCloudTransfer(head)
        precondition(vm.settingsNotice?.retry != nil && model.active == nil && model.queue.first?.token == head,
                     "A legacy pause must ask for the current destination before starting")
        vm.settingsNotice = nil
        model.queueStore.save([saved, queued])
        await model.stopForQuit()?.value
        vm = try await reopen()
        model = vm.cloudLibrary
        vm.resumeCloudTransfer(head)
        try await until("Reject the changed destination") { model.active == nil && vm.settingsNotice != nil }
        precondition(model.queue.first?.entry == saved && !fm.fileExists(atPath: changed.path) && !fm.fileExists(atPath: b.url.path))

        vm.settingsNotice = nil
        transport.withLock { $0.offline = true }
        vm.cancelQueuedCloudLibrary(head)
        try await until("B is interrupted by network, not user") { model.queuePause != nil }
        try await until("B returned to the queue") { model.active == nil }
        precondition(model.queue.first?.token == queued.token && model.queue.first?.isUserPaused == false)
        try activity("activite-hors-ligne-fr", vm, .queuedCloud(queued.token!), command: "Resume")
        transport.withLock { $0.offline = false }
        vm.resumeCloudTransfer(queued.token!)
        try await until("B succeeds after cancelling A") { model.active == nil && model.queue.isEmpty }
        precondition(fm.fileExists(atPath: b.url.path) && !fm.fileExists(atPath: changed.path))
        await model.stopForQuit()?.value
        print("Pause persistence, FIFO, legacy consent, changed destination, cancellation, installation guard and offline checked.")
    }

    static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CocoaError(.fileReadUnknown, userInfo: [NSDebugDescriptionErrorKey: message]) }
        return value
    }

    @MainActor static func until(_ message: String, diagnostic: () -> String = { "" }, _ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CocoaError(.fileReadUnknown, userInfo: [NSDebugDescriptionErrorKey: message + " " + diagnostic()])
    }
'''


def main():
    output = Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    home = Path(os.environ["HOME"]).resolve()
    assert home == Path(os.environ["CFFIXED_USER_HOME"]).resolve()
    assert home != Path(os.environ["ORIGINAL_HOME"]).resolve()
    with tempfile.TemporaryDirectory(prefix="pause-command-", dir=home) as temp:
        package = Path(temp)
        shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
        shutil.copytree(ROOT / "Sources", package / "Sources")
        for target in ("NXLibraryCoreTests", "ArcanePortingTests", "OortCoreTests"):
            path = package / "Tests" / target
            path.mkdir(parents=True)
            (path / "Empty.swift").touch()
        app = package / "Sources/NXLibrary"
        change(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        change(app / "ViewModels/AppViewModel.swift", r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        change(app / "ViewModels/AppViewModel.swift", r"        applyCatalog\(catalog\).*?\n    }\n\n    // MARK: - Dynamic",
               "    }\n\n    // MARK: - Dynamic")
        model = app / "ViewModels/AppViewModel+CloudLibrary.swift"
        change(model, r"        let defaults = AppData\.preferences.*?(?=        rebuildArchive\(\))",
               '        preference = .init(storage: "fixture:Games", enabled: true, sourcesRoot: nil)\n'
               '        chosenExecutable = nil\n        needsDriveToolChoice = true\n')
        with model.open("a") as swift:
            swift.write(r'''
extension CloudLibraryModel {
    @MainActor func installPauseFixture(_ fixture: RcloneStorageBackend, scope: CloudDriveScope) throws {
        scopeTask?.cancel()
        scopeTask = nil
        AppData.preferences.set(preference.storage, forKey: CloudLibraryPreference.storageKey)
        AppData.preferences.set(true, forKey: CloudLibraryPreference.enabledKey)
        AppData.preferences.set(try JSONEncoder().encode(scope), forKey: Self.scopeKey)
        installScope(scope, backend: fixture)
    }
}
''')
        profile = package / "Sources/NXLibraryCore/App/AppDataProfile.swift"
        change(profile, r"public static let profile = [^\n]*",
               'public static let profile = AppDataProfile(home: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!), isDevelopment: true)')
        change(profile, r"public static var preferences: UserDefaults \{ [^\n]+ \}",
               'public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        activity = app / "Views/Shell/ActivityCenterView.swift"
        change(activity, r"                ScrollViewReader \{ scroll in\n                    ScrollView \{\n", "")
        change(activity, r"                    }\n                    \.padding\(EdgeInsets.*?\.onChange\(of: focused\)[^\n]*\n                }\n", "")
        change(activity, r"        LazyVStack\(", "        VStack(")
        with activity.open("a") as swift:
            swift.write('''
extension ActivityCenterView {
    func pauseCommandForProbe(_ row: ActivityCenterFocus.Row) -> String? { hints(row).first { $0.button == .a }?.label }
}
''')
        panel = app / "Views/Detail/CloudLibraryPanel.swift"
        change(panel, r"        \.task\(id: ReadRequest.*?\n", "")
        with panel.open("a") as swift:
            swift.write('''
extension CloudLibraryPanel {
    func requirePauseCommandForProbe(_ expected: String) {
        precondition(actionHints.first?.label == expected,
                     "Expected \\(expected); hints: \\(actionHints.map(\\.label)); controls: \\(controls); availability: \\(String(describing: unavailable)); archive: \\(model.archive != nil); pausable: \\(String(describing: pausable)); action: \\(String(describing: state.action)); focus: \\(String(describing: focus))")
    }
    func activatePauseCommandForProbe() { handle(.confirm) }
}
''')
        monitor = app / "Services/RunningGameMonitor.swift"
        change(monitor, r"import AppKit", "import AppKit\nimport os")
        change(monitor, r"    nonisolated static func runningApplication\(bundleID: String\).*?\n    }", '''
    nonisolated static let pauseProbeRunning = OSAllocatedUnfairLock<String?>(initialState: nil)
    nonisolated static func runningApplication(bundleID: String) -> NSRunningApplication? {
        pauseProbeRunning.withLock { $0 == bundleID } ? .current : nil
    }'''.lstrip("\n"))
        change(app / "Views/Components/SwitchBoxArtCover.swift",
               r"        \.task\(id: coverKey.*?\n        \.task\(id: game.id[^\n]*\n", "")
        header = HOST.split("        // SCENARIO")[0].replace("import SwiftUI", "import SwiftUI\nimport os")
        render = HOST[HOST.index("    @MainActor static func render<V: View>"):]
        render = render.replace("SeleneCanvas(size: .init(width: 1920, height: 1080))", "SeleneCanvas(size: size)")
        render = render.replace("height: 1000)) throws", "height: 1000), crop: CGRect? = nil) throws")
        render = render.replace("guard let image = renderer.cgImage,", "guard let frame = renderer.cgImage,\n"
                                "              let image = crop.map({ frame.cropping(to: $0) }) ?? frame,")
        (app / "CloudScreenProbe.swift").write_text(header + SCENARIO + render)
        fixture_home = package / "profile"
        fixture_home.mkdir()
        subprocess.run(["swift", "run", "--jobs", "4", "--package-path", str(package), "NXLibrary", str(output),
                        str(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"),
                        str(ROOT / "Resources/AppIcon-Light.png")], check=True,
                       env=dict(os.environ, HOME=str(fixture_home), CFFIXED_USER_HOME=str(fixture_home)))


if __name__ == "__main__":
    main()
