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
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        let repository = CatalogRepository(store: .init(directory: data))
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let ids = ["A000000000000001", "A000000000000002"]
        let games = zip(ids, ["Observatoire lunaire", "Jardin orbital"]).map { title, name in
            var game = PortedGame(name: name, url: data.appendingPathComponent("\(title).app"),
                                  platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: title)
            game.status = .appMissing
            return game
        }
        let catalog = try repository.mergeNXNative(scanned: games, enableSource: true)
        let backend = RcloneStorageBackend(remote: ":local:", root: data.path, executable: URL(fileURLWithPath: "/usr/bin/true")) {
            _, _, _ in throw URLError(.notConnectedToInternet)
        }
        let vm = AppViewModel(settingsStore: settings, catalog: catalog, repository: repository)
        vm.applyCatalog(catalog)
        let model = vm.cloudLibrary
        model.installPauseFixture(backend)
        let entries = vm.libraryGames.sorted { $0.titleId! < $1.titleId! }.map {
            CloudTransferQueue.Entry(id: $0.id, action: .restore(.app), token: UUID(),
                storage: model.preference.storage, toolIdentity: model.transferToolIdentity)
        }
        precondition(entries.count == 2 && entries[0].toolIdentity != nil)
        var head = entries[0]
        head.isUserPaused = true
        model.queueStore.save([head, entries[1]])
        await model.queueStore.flush()
        vm.restoreCloudQueue()
        for _ in 0..<500 where !model.hasRestoredQueue { try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.hasRestoredQueue && model.active == nil &&
                     model.queue.map(\.token) == entries.map { $0.token! },
                     "A previously paused head must block both downloads when the model reopens")
        vm.retryCloudCheck()
        precondition(model.active == nil && model.queue.first?.token == head.token,
                     "Retrying the connection must not resume a user-paused download")
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
               '        chosenExecutable = nil\n')
        with model.open("a") as swift:
            swift.write(r'''
extension CloudLibraryModel {
    @MainActor func installPauseFixture(_ fixture: RcloneStorageBackend) {
        AppData.preferences.set(preference.storage, forKey: CloudLibraryPreference.storageKey)
        AppData.preferences.set(true, forKey: CloudLibraryPreference.enabledKey)
        installScope(nil, backend: fixture)
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
        header = HOST.split("        // SCENARIO")[0]
        render = HOST[HOST.index("    @MainActor static func render<V: View>"):]
        render = render.replace("SeleneCanvas(size: .init(width: 1920, height: 1080))", "SeleneCanvas(size: size)")
        (app / "CloudScreenProbe.swift").write_text(header + SCENARIO + render)
        fixture_home = package / "profile"
        fixture_home.mkdir()
        subprocess.run(["swift", "run", "--jobs", "4", "--package-path", str(package), "NXLibrary", str(output),
                        str(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"),
                        str(ROOT / "Resources/AppIcon-Light.png")], check=True,
                       env=dict(os.environ, HOME=str(fixture_home), CFFIXED_USER_HOME=str(fixture_home)))


if __name__ == "__main__":
    main()
