#!/usr/bin/env python3
"""Exercise pause through the real view model and render the French Selene rows. On the shared Debug app, with the pinned local rclone (OORT_PROBE_RCLONE)."""

from audit_probe_host import run_host
from run_cloud_screens import capture_destination
from screen_host import ICON, header, package_name, rclone, render

SCENARIO = r'''
        let fm = FileManager.default
        ActivityCenterView.oortProbeRendersFlat = true
        // The cloud library the player chose, saved as the app saves it.
        AppData.preferences.set("fixture:Games", forKey: CloudLibraryPreference.storageKey)
        AppData.preferences.set(true, forKey: CloudLibraryPreference.enabledKey)
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
        let rclone = try require(RcloneStorageBackend.findExecutable(
            preferred: ProcessInfo.processInfo.environment["OORT_PROBE_RCLONE"].map {
                $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent($0)
            }),
            "Local rclone fixture unavailable")
        let config = data.appendingPathComponent("rclone.conf")
        try Data().write(to: config)
        let scope = CloudDriveScope(remote: "fixture", account: "account-a", library: .init(path: "Games", id: "folder-a"))
        let transport = OSAllocatedUnfairLock(initialState: (hold: false, offline: false, copies: 0))
        let backend = RcloneStorageBackend(remote: ":local:", root: remote.path, executable: rclone, config: config) {
            tool, args, _ in
            func canonical(_ path: String) -> String {
                let path = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
                // macOS APIs disagree on whether temporary paths include /private.
                return path.hasPrefix("/private/tmp/") || path.hasPrefix("/private/var/")
                    ? String(path.dropFirst("/private".count)) : path
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
            // What the copied app's patches imposed: the chosen library, the Drive tool still to choose.
            precondition(vm.cloudLibrary.preference.storage == "fixture:Games" && vm.cloudLibrary.needsDriveToolChoice)
            try vm.cloudLibrary.oortProbeInstallScope(backend, scope: scope)
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
            precondition(view.oortProbeConfirmCommand(row) == command)
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
        precondition(livePanel.oortProbePrimaryCommand() == "Pause", livePanel.oortProbeDiagnostic())
        try activity("activite-telechargement-fr", vm, .cloud(head), command: "Pause")
        try render("fiche-telechargement-fr", output, livePanel.environment(\.nxAppLocale, fr),
                   size: .init(width: 1440, height: 920))
        livePanel.oortProbeConfirm()
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
        precondition(pausedPanel.oortProbePrimaryCommand() == "Resume", pausedPanel.oortProbeDiagnostic())
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
        try model.oortProbeInstallScope(unapproved, scope: scope)
        vm.resumeCloudTransfer(head)
        precondition(vm.settingsNotice != nil && model.active == nil && model.queue.first?.entry == saved)
        vm.settingsNotice = nil
        let changedScope = CloudDriveScope(remote: "fixture", account: "account-b", library: scope.library)
        try model.oortProbeInstallScope(backend, scope: changedScope)
        vm.resumeCloudTransfer(head)
        precondition(vm.settingsNotice != nil && model.active == nil && model.queue.first?.entry == saved)
        vm.settingsNotice = nil
        try model.oortProbeInstallScope(backend, scope: scope)

        // Simulate a Finder launch without launching a game or writing any game preferences.
        RunningGameMonitor.oortProbeRunning.withLock { $0 = a.bundleId }
        vm.activateCloudActivityRow(.queuedCloud(head))
        try await until("A waiting to install") { model.states[a.id]?.progress?.phase == .readyToInstall }
        vm.pauseCloudTransfer(head)
        precondition(model.active?.request.isUserPaused == false && model.queue.map(\.token) == [next])
        try activity("activite-installation-fr", vm, .cloud(head), command: nil)
        RunningGameMonitor.oortProbeRunning.withLock { $0 = nil }
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
    output = capture_destination("cloud-pause-captures-")
    output.mkdir(parents=True, exist_ok=True)
    renderer = render().replace("SeleneCanvas(size: .init(width: 1920, height: 1080))", "SeleneCanvas(size: size)")
    renderer = renderer.replace("height: 1000)) throws", "height: 1000), crop: CGRect? = nil) throws")
    renderer = renderer.replace("guard let image = renderer.cgImage,", "guard let frame = renderer.cgImage,\n"
                                "              let image = crop.map({ frame.cropping(to: $0) }) ?? frame,")
    resources, environment = rclone()
    run_host(header().replace("import SwiftUI", "import SwiftUI\nimport os") + SCENARIO + renderer, save_model=True,
             capture=output, resources=(ICON, *resources), environment=environment, package_name=package_name())


if __name__ == "__main__":
    main()
