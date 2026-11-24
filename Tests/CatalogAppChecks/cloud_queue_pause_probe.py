#!/usr/bin/env python3
"""Check the pause snapshot and render its unchanged Activity rows, with no backend."""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from run_cloud_screens import HOST, ROOT, change

SCENARIO = r'''
        let store = CloudTransferQueue()
        let scope = CloudDriveScope(remote: "fixture", account: "fixture-account",
            library: .init(path: "Games", id: "fixture-games"))
        let head = CloudTransferQueue.Entry(id: UUID(), action: .restore(.app), token: UUID(),
            storage: "fixture:Games", driveScope: scope, toolIdentity: "fixture-tool")
        let next = CloudTransferQueue.Entry(id: UUID(), action: .downloadSources, token: UUID(),
            storage: "fixture:Files", driveScope: scope, toolIdentity: "fixture-tool")
        var saved = head
        // SET_PAUSE
        store.save([saved, next])
        await store.flush()
        let reopened = await CloudTransferQueue().load()
        let entries = CloudTransferQueue.restoring(reopened, gameIDs: [head.id, next.id])
        precondition(entries == [saved, next])
        precondition(entries[0].token == head.token && entries[0].driveScope == scope)
        precondition(entries[0].permitsTool("fixture-tool") && !entries[0].permitsTool("replaced-tool"))
        // CLEAR_PAUSE

        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
        for (entry, name) in zip(entries, ["Observatoire lunaire", "Jardin orbital"]) {
            vm.cloudLibrary.queue.append(.init(token: entry.token!, id: entry.id, name: name, action: entry.action,
                storage: entry.storage, scope: .init(title: "", urls: []), importDestination: nil,
                sourceFiles: nil, onSuccess: nil, driveScope: entry.driveScope, toolIdentity: entry.toolIdentity))
            vm.cloudLibrary.update(entry.id) { $0.action = entry.action; $0.queued = true }
        }
        var focus = ActivityCenterFocus()
        focus.selected = .queuedCloud(head.token!)
        let activity = ActivityCenterView(viewModel: vm, porting: vm.porting, cloudLibrary: vm.cloudLibrary,
            focus: focus, onFocus: { _ in }, onOpen: { _ in }, onCancel: { _ in },
            onBack: {}, onOutside: {}).environment(\.nxAppLocale, fr)
        try render("activite-large-fr", output, activity, size: .init(width: 1440, height: 800))
        try render("activite-etroite-fr", output, activity, size: .init(width: 960, height: 600))
    }
'''


def main():
    output = Path(sys.argv[1]).resolve()
    home = Path(os.environ["HOME"]).resolve()
    assert home == Path(os.environ["CFFIXED_USER_HOME"]).resolve()
    assert os.environ.get("ORIGINAL_HOME") and home != Path(os.environ["ORIGINAL_HOME"]).resolve()
    with tempfile.TemporaryDirectory(prefix="queue-pause-", dir=home) as temp:
        package = Path(temp)
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
        change(app / "ViewModels/AppViewModel+CloudLibrary.swift",
               r"        let defaults = AppData\.preferences.*?(?=        rebuildArchive\(\))",
               '        preference = .init(storage: nil, enabled: false, sourcesRoot: nil)\n        chosenExecutable = nil\n')
        # Like run_cloud_screens: ImageRenderer cannot draw the native scrolling container.
        activity = app / "Views/Shell/ActivityCenterView.swift"
        change(activity, r"                ScrollViewReader \{ scroll in\n                    ScrollView \{\n", "")
        change(activity, r"                    }\n                    \.padding\(EdgeInsets.*?\.onChange\(of: focused\)[^\n]*\n                }\n", "")
        change(activity, r"        LazyVStack\(", "        VStack(")
        profile = package / "Sources/NXLibraryCore/App/AppDataProfile.swift"
        change(profile, r"public static let profile = [^\n]*",
               'public static let profile = AppDataProfile(home: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!), isDevelopment: true)')
        change(profile, r"public static var preferences: UserDefaults \{ [^\n]+ \}",
               'public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        queue_path = Path("Sources/ArcanePorting/Library/CloudTransferQueue.swift")
        baseline = subprocess.check_output(["git", "-C", str(ROOT), "show", f"e432ed20:{queue_path}"])
        header = HOST.split("        // SCENARIO")[0]
        render = HOST[HOST.index("    @MainActor static func render<V: View>"):]
        render = render.replace("SeleneCanvas(size: .init(width: 1920, height: 1080))", "SeleneCanvas(size: size)")
        for phase in ("avant", "apres"):
            dest = output / phase
            dest.mkdir(parents=True, exist_ok=True)
            profile_home = package / phase
            profile_home.mkdir()
            scenario = SCENARIO
            if phase == "avant":
                (package / queue_path).write_bytes(baseline)
                scenario = scenario.replace("var saved = head", "let saved = head")
            else:
                shutil.copyfile(ROOT / queue_path, package / queue_path)
                scenario = scenario.replace("// SET_PAUSE", "saved.isUserPaused = true").replace("// CLEAR_PAUSE", """
        var resumed = entries[0]
        precondition(resumed.isUserPaused && !entries[1].isUserPaused)
        resumed.isUserPaused = false
        precondition(resumed == head)
        """)
            (app / "CloudScreenProbe.swift").write_text(header + scenario + render)
            subprocess.run(["swift", "run", "--jobs", "4", "--package-path", str(package), "NXLibrary", str(dest),
                            str(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"),
                            str(ROOT / "Resources/AppIcon-Light.png")], check=True,
                           env=dict(os.environ, HOME=str(profile_home), CFFIXED_USER_HOME=str(profile_home)))
    for before in (output / "avant").glob("*.png"):
        assert before.read_bytes() == (output / "apres" / before.name).read_bytes(), before.name
    print("Pause snapshot reopens with its original identity; French Activity screenshots are unchanged.")


if __name__ == "__main__":
    main()
