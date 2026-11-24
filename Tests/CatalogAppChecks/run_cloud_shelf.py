#!/usr/bin/env python3
"""Render the real Collection and cloud assistant, and exercise empty Collection input."""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from run_cloud_screens import ROOT, HOST, change


SCENARIOS = r'''
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
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
            if let key = collection.shelfKeyForProbe, key != expected {
                failures.append("Expected \(expected), got \(key)")
            }
        }
        vm.librarySelection.query.filter = .all
        try capture("all-empty", collection)
        if !collection.showsLocalImportHintForProbe { failures.append("All games must keep Add game") }
        collection.handle(.confirm)
        if router.route != .addGame { failures.append("Confirm on All games must still open Add game") }
        router.setInitialRoute(.collection)
        vm.librarySelection.query.filter = .cloud
        try capture("disabled", collection)
        expectShelf("Connect your cloud library in Settings → Porting → Cloud library.")
        if collection.showsLocalImportHintForProbe { failures.append("Cloud must not advertise Add game") }
        collection.handle(.confirm)
        if router.route == .addGame { failures.append("Confirm on an empty Cloud shelf must not open Add game") }
        router.setInitialRoute(.collection)

        model.configure(remote: "fixture", root: "Games", enabled: true, sourcesRoot: nil)
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            .init(status: 0, stdout: args.contains("--stat") ? #"{"IsDir":true}"# : "[]", stderr: "")
        }
        model.shelfProbeInstall(backend)
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
        try capture("move-confirm", assistant.shelfProbeAssistant(plan: plan))
        try capture("move-conflict", assistant.shelfProbeAssistant(failure: CloudDriveFolders.MoveFailure.sourceNotEmpty.localizedDescription))
        let sources = CloudSetupAssistant(viewModel: vm, model: model, entry: .sources) {}
        try capture("sources-found", sources.shelfProbeAssistant(sources: .shelfProbeFound))
        let ready = assistant.shelfProbeAssistant(verified: true)
        try capture("assistant-verified", ready)
        ready.perform(.primary)
        if let notice = vm.settingsNotice {
            if !notice.message.contains("Bibliothèque → Cloud") || notice.choices != ["Close"] {
                failures.append("The completion notice must name the Cloud tab and offer Close")
            }
            try capture("assistant-complete", SeleneChoiceDialog(title: notice.title, message: notice.message,
                choices: notice.choices, focus: .constant(notice.initialFocus), onChoose: { _ in }))
        } else { failures.append("Finished setup must point to Cloud") }
        vm.settingsNotice = nil
        model.setPendingMove(.init(id: UUID(), request: .init(plan: plan, destination: "New Library"),
                                   sourcesRoot: "Games/GameFiles"))
        var didClose = false
        let paused = CloudSetupAssistant(viewModel: vm, model: model, entry: .library) { didClose = true }
            .shelfProbeAssistant(paused: true)
        try capture("move-paused", paused)
        if paused.shelfCancelTitleForProbe != "Close" || paused.focusedTarget != .cancel {
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
    output = Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cloud-shelf-", dir=os.environ["HOME"]) as temp:
        package = Path(temp)
        home = package / "home"
        home.mkdir()
        if "--before" in sys.argv:
            archived = subprocess.check_output(["git", "-C", str(ROOT), "archive", "e432ed20", "Sources", "Package.swift"])
            subprocess.run(["tar", "-xf", "-", "-C", str(package)], input=archived, check=True)
        else:
            shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
            shutil.copytree(ROOT / "Sources", package / "Sources")
        for name in ("NXLibraryCoreTests", "ArcanePortingTests", "OortCoreTests"):
            folder = package / "Tests" / name
            folder.mkdir(parents=True)
            (folder / "Empty.swift").touch()
        app = package / "Sources/NXLibrary"
        change(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        change(app / "ViewModels/AppViewModel.swift", r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        change(app / "ViewModels/AppViewModel.swift", r"        applyCatalog\(catalog\).*?\n    }\n\n    // MARK: - Dynamic",
               "    }\n\n    // MARK: - Dynamic")
        change(package / "Sources/NXLibraryCore/App/AppDataProfile.swift", r'public static let profile = [^\n]*',
               'public static let profile = AppDataProfile(home: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!), isDevelopment: true)')
        change(package / "Sources/NXLibraryCore/App/AppDataProfile.swift", r'public static var preferences: UserDefaults \{ [^\n]+ \}',
               'public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        cloud = app / "ViewModels/AppViewModel+CloudLibrary.swift"
        change(cloud, r'var resolvedDriveTool: URL\? \{.*?\n    }', 'var resolvedDriveTool: URL? { nil }')
        with cloud.open("a") as swift:
            swift.write('''
extension CloudLibraryModel {
    func shelfProbeInstall(_ backend: RcloneStorageBackend) {
        archive = CloudGameArchive(backend: backend)
        sourceArchive = CloudGameSources(backend: backend, root: "Games/GameFiles")
    }
}
''')
        collection = app / "Views/Collection/CollectionView.swift"
        with collection.open("a") as swift:
            swift.write('''
extension CollectionView {
    var showsLocalImportHintForProbe: Bool { contextHints(nil, record: nil).contains { $0.button == .a } }
    var shelfKeyForProbe: String? { SHELF_KEY }
}
'''.replace("SHELF_KEY", "cloudEmptyKey" if "--before" not in sys.argv else "nil"))
        # ImageRenderer substitutes a warning for the AppKit art layer. No fixture has hero art.
        change(app / "Views/Spotlight/SeleneArtBackground.swift", r"            SeleneArtLayer\(image: art,[^\n]*\n", "")
        change(app / "Views/Theme/MoonlightRenderer.swift", r"                if let image \{\n                    Image\(decorative:",
               "                if let image = engine.snapshot(width: max(w, 1), height: max(h, 1), colors: colors) {\n                    Image(decorative:")
        assistant = app / "Views/Settings/CloudSetupAssistant.swift"
        change(assistant, r'        \.onAppear \{ inspect\(\); installAssistantKeys\(\) }', '')
        with assistant.open("a") as swift:
            swift.write('''
extension CloudSetupAssistant {
    var shelfCancelTitleForProbe: String { CANCEL_TITLE }
    func shelfProbeAssistant(plan: CloudDriveFolders.MovePlan? = nil, failure: String? = nil,
                             paused: Bool = false, sources: CloudDriveFolders.Sources? = nil,
                             verified: Bool = false) -> Self {
        var view = self
        if plan != nil || paused || verified {
            var draft = CloudSetupAssistantDraft()
            draft.chooseAccount("fixture")
            draft.browse("New Library")
            if plan != nil || paused { draft.toggleMove() }
            precondition(draft.useFolder())
            draft.acceptAccessCheck(draft.ticket)
            view._draft = State(initialValue: draft)
            view._movePlan = State(initialValue: plan)
            view._confirmingMove = State(initialValue: plan != nil)
        }
        view._moveFailure = State(initialValue: failure)
        if paused { view._issue = State(initialValue: "Move paused. Close this window and choose Retry in Activity.") }
        view._sourcesSuggestion = State(initialValue: sources)
        return view
    }
}
'''.replace("CANCEL_TITLE", "cancelTitle" if "--before" not in sys.argv else '"Back"'))
        with (package / "Sources/ArcanePorting/Library/CloudDriveFolders.swift").open("a") as swift:
            swift.write('''
extension CloudDriveFolders.Sources {
    package static var shelfProbeFound: Self { .init(path: "Games/Switch/Games", games: 1) }
}
''')
        host = HOST[:HOST.index("        // SCENARIO")] + SCENARIOS + "    }\n"
        host += HOST[HOST.index("    @MainActor static func render<V:"):].replace(
            "SeleneCanvas(size: .init(width: 1920, height: 1080))",
            "SeleneCanvas(size: size)")
        (app / "CloudShelfProbe.swift").write_text(host)
        subprocess.run(["swift", "run", "--jobs", "4", "--package-path", str(package), "NXLibrary", str(output),
                        str(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"),
                        str(ROOT / "Resources/AppIcon-Light.png"), *sys.argv[2:]],
                       check=True, env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))


if __name__ == "__main__":
    main()
