#!/usr/bin/env python3
"""Render the real Collection and cloud assistant, and exercise empty Collection input, on the shared Debug app.

cloud_shelf_baseline.py runs the same check on e432ed20, before the fix."""
from audit_probe_host import run_host
from run_cloud_screens import capture_destination
from screen_host import ICON, header, package_name, render

SCENARIOS = r'''
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
        // Offscreen: no Drive tool from this Mac, no AppKit art layer, the still moonlight drawn now, French outside a
        // mounted hierarchy, and the assistant without Drive inspection or key watching.
        CloudLibraryModel.oortProbeNoDriveTool.withLock { $0 = true }
        SeleneArtBackground.oortProbeNoArtLayer = true
        MoonlightBackdrop.oortProbeStill = true
        MoonlightStill.oortProbeSynchronous = true
        AppLocaleDefault.oortProbeLocale.withLock { $0 = fr }
        CloudSetupAssistant.oortProbeStill = true
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let repository = CatalogRepository(store: .init(directory: data))
        let catalog = try repository.load()
        let vm = AppViewModel(settingsStore: settings,
                              catalog: catalog, repository: repository)
        vm.applyCatalog(catalog)
        let model = vm.cloudLibrary
        let router = AppRouter()
        router.setInitialRoute(.collection)
        let collection = CollectionView(viewModel: vm, router: router, settings: settings,
                                        playSessions: PlaySessionStore(), artwork: ArtworkStore())
        func capture<V: View>(_ name: String, _ view: V) throws {
            for (label, size) in [("wide", CGSize(width: 1600, height: 900)), ("narrow", CGSize(width: 960, height: 680))] {
                try render("\(name)-\(label)", output, view.environment(\.nxAppLocale, fr)
                    .environment(\.seleneButtonNames, .xbox), size: size)
            }
        }
        let before = CommandLine.arguments.contains("--before")
        var failures: [String] = []
        func expectShelf(_ expected: String) {
            if let key = collection.oortProbeShelfKey, key != expected {
                failures.append("Expected \(expected), got \(key)")
            }
        }
        vm.librarySelection.query.filter = .all
        try capture("all-empty", collection)
        if !collection.oortProbeShowsLocalImportHint { failures.append("All games must keep Add game") }
        collection.handle(.confirm)
        if router.route != .addGame { failures.append("Confirm on All games must still open Add game") }
        router.setInitialRoute(.collection)
        vm.librarySelection.query.filter = .cloud
        try capture("disabled", collection)
        expectShelf("Connect your cloud library in Settings → Porting → Cloud library.")
        if collection.oortProbeShowsLocalImportHint { failures.append("Cloud must not advertise Add game") }
        collection.handle(.confirm)
        if router.route == .addGame { failures.append("Confirm on an empty Cloud shelf must not open Add game") }
        router.setInitialRoute(.collection)

        model.configure(remote: "fixture", root: "Games", enabled: true, sourcesRoot: nil)
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            .init(status: 0, stdout: args.contains("--stat") ? #"{"IsDir":true}"# : "[]", stderr: "")
        }
        model.oortProbeInstallArchives(CloudGameArchive(backend: backend),
                                       sources: CloudGameSources(backend: backend, root: "Games/GameFiles"))
        let loading = Task<Void, Never> {}
        model.importTask = loading
        try capture("searching", collection)
        expectShelf("Looking for cloud games…")
        model.importTask = nil
        model.checkFailure = .offline
        try capture("failed", collection)
        expectShelf("Could not check the cloud library. Check your connection in Settings.")
        model.checkFailure = nil
        vm.importCloudGames()
        await model.importTask?.value
        precondition(model.lastCompleteCheck != nil && model.checkFailure == nil,
                     "Verified empty fixture: \(String(describing: model.checkFailure))")
        try capture("verified-empty", collection)
        expectShelf("No cloud games to download.")
        model.checkFailure = .incomplete
        try capture("partial", collection)
        expectShelf("Could not check the cloud library. Check your connection in Settings.")
        model.checkFailure = nil

        let manifest = try JSONDecoder().decode(CloudGameManifest.self, from: Data(
            #"{"version":1,"title_id":"0100000000004000","created_at":0,"game_name":"Lunar Observatory","artifacts":[{"kind":"app","size":4,"sha256":"fixture","md5":"fixture","unpacked_size":4,"entry_count":1,"inventory_sha256":"fixture","options":{}}]}"#.utf8))
        let imported = try vm.catalogRepository.importCloudGames([manifest], in: vm.gameAppsFolder)
        vm.applyCatalog(imported)
        let game = vm.libraryGames.first!
        model.remember { $0.personalApps.insert(game.id) }
        model.connectionCheck = .init(date: .now, failure: .offline)
        vm.librarySelection.selectedGameID = game.id
        if collection.games.map(\.id) != [game.id] { failures.append("Known game must remain on the Cloud shelf offline") }
        try capture("known-offline", collection)
        model.connectionCheck = nil
        try capture("known-recovered", collection)

        let assistant = CloudSetupAssistant(viewModel: vm, model: model, entry: .library) {}
        let archiveKey = "0100000000001000/app/" + String(repeating: "a", count: 64) + ".aar"
        let moveData = Data(#"{"source":"Games","remote":"fixture","games":1,"bytes":1000,"entries":[{"file":{"key":{"value":"\#(archiveKey)"},"size":1000,"hashes":{"md5":"c4ca4238a0b923820dcc509a6f75849b"}},"dependencies":[]}]}"#.utf8)
        let plan = try JSONDecoder().decode(CloudDriveFolders.MovePlan.self, from: moveData)
        try capture("move-confirm", assistant.oortProbeAssistant(plan: plan))
        try capture("move-conflict", assistant.oortProbeAssistant(failure: CloudDriveFolders.MoveFailure.sourceNotEmpty.localizedDescription))
        let ready = assistant.oortProbeAssistant(verified: true)
        try capture("assistant-verified", ready)
        ready.perform(.primary)
        if vm.librarySelection.query.filter != .cloud { failures.append("Finished setup must open the cloud shelf") }
        vm.settingsNotice = nil
        model.setPendingMove(.init(id: UUID(), request: .init(plan: plan, destination: "New Library"),
                                   sourcesRoot: "Games/GameFiles"))
        var didClose = false
        let paused = CloudSetupAssistant(viewModel: vm, model: model, entry: .library) { didClose = true }
            .oortProbeAssistant(paused: true)
        try capture("move-paused", paused)
        if paused.cancelTitle != "Close" || paused.focusedTarget != .cancel {
            failures.append("A paused move must focus Close")
        }
        paused.handleAssistantInput(.confirm)
        if !didClose || !model.hasPendingMove { failures.append("Closing must leave the pending move intact") }
        if !failures.isEmpty {
            print(failures.map { "FAIL: " + $0 }.joined(separator: "\n"))
            if !before { exit(1) }
        }
'''


def main():
    output = capture_destination("cloud-shelf-captures-")
    output.mkdir(parents=True, exist_ok=True)
    renderer = render().replace("SeleneCanvas(size: .init(width: 1920, height: 1080))", "SeleneCanvas(size: size)")
    run_host(header() + SCENARIOS + "    }\n" + renderer, save_model=True, capture=output, resources=(ICON,),
             package_name=package_name())


if __name__ == "__main__":
    main()
