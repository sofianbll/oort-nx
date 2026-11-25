#!/usr/bin/env python3
"""Check reference-library copy and controls on the real Selene views with a fake Drive."""
import os
import pwd
import subprocess
import sys
import tempfile
from pathlib import Path
from shutil import copyfile, copytree

from run_cloud_screens import ROOT, HOST, capture_destination, change, cloud_settings_fixture, isolate_startup

SCENARIO = r'''
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        var failures: [String] = []
        let title = "0100000000008000"
        let folder = "FixtureFolderID"
        let fixture = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            precondition(args[0] == "lsjson" && args.contains("--drive-root-folder-id=\(folder)"))
            if args[1] == "fixture:" {
                let row = #"{"Name":"\#(title)","Path":"\#(title)","IsDir":true,"Size":-1}"#
                return .init(status: 0, stdout: "[\(row),\(row)]", stderr: "")
            }
            throw CocoaError(.fileReadUnknown)
        }
        let warning = await vm.referenceProbe(fixture, folder: folder)
        if !warning.contains(title) || !warning.contains("pas été ajoutés") { failures.append("Unreadable game: \(warning)") }
        for width in [1280.0, 720.0] {
            let size = CGSize(width: width, height: 1000)
            let suffix = width > 1000 ? "-wide" : "-narrow"
            for (name, draft) in [("editor", ""), ("editor-invalid", "https://example.test/file"),
                                  ("editor-valid", folder)] {
                measuredSave = nil
                try render("reference-\(name)\(suffix)", output, CloudReferenceDialog(viewModel: vm, onClose: {})
                    .probeDraft(draft).environment(\.nxAppLocale, fr), size: size)
                if measuredSave?.focused != (name == "editor-valid") || measuredSave?.enabled != (name == "editor-valid") {
                    failures.append("\(name)\(suffix): incorrect Save focus or availability")
                }
            }
            let model = vm.cloudLibrary
            for (name, check, label) in [
                ("settings", CloudLibraryModel.ReferenceCheck(date: .now, count: 1), "Lecture seule"),
                ("error", CloudLibraryModel.ReferenceCheck(date: .now, failure: .folderMissing), "Pas d’accès"),
            ] {
                model.referenceCheck = check
                labels = []
                try render("reference-\(name)\(suffix)", output, SettingsCloudLibrarySection(
                    viewModel: vm, model: model, settings: /* CLOUD_SETTINGS */ SettingsEditor(settings), advanced: .constant(false),
                    onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
                    .environment(\.nxAppLocale, fr).padding(24).frame(width: min(1040, width - 48)), size: size)
                if !labels.contains(label) { failures.append("\(name)\(suffix): \(labels)") }
            }
            try renderNotice("import-with-unreadable-title\(suffix)", output, vm.settingsNotice!, width: width)
        }
        for failure in failures { print("FAIL: \(failure)") }
        exit(failures.isEmpty ? 0 : 3)
    }

    @MainActor static var measuredSave: (focused: Bool, enabled: Bool)?
    @MainActor static var labels: [String] = []
    @MainActor static func measure(_ label: String, _ focused: Bool, _ enabled: Bool) -> Bool {
        if label == "Save" { measuredSave = (focused, enabled) }
        return focused
    }
    @MainActor static func measureLabel(_ label: String) -> String {
        labels.append(label)
        return label
    }
'''

FIXTURE = r'''
extension AppViewModel {
    @MainActor func referenceProbe(_ backend: RcloneStorageBackend, folder: String) async -> String {
        cloudLibrary.installReferenceProbe(backend, folder: folder)
        let (added, warnings) = await importCloudReference(archive: cloudLibrary.archive!)
        precondition(!added && cloudLibrary.referenceCheck?.incomplete == true && warnings.count == 1)
        showSettingsNotice(title: "Reference library", message: warnings[0])
        return warnings[0]
    }
}

extension CloudLibraryModel {
    @MainActor func installReferenceProbe(_ backend: RcloneStorageBackend, folder: String) {
        preference = .init(storage: "fixture:Games", enabled: true, sourcesRoot: nil, referenceFolder: folder)
        archive = CloudGameArchive(backend: backend)
        referenceArchive = CloudGameArchive(backend: backend.reference(folderID: folder)!)
    }
}
'''


def main():
    output = capture_destination("cloud-reference-captures-")
    baseline = sys.argv[2] if len(sys.argv) == 3 else None
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="reference-probe-", dir=output.parent) as temp:
        package = Path(temp)
        copyfile(ROOT / "Package.swift", package / "Package.swift")
        if baseline:
            sources = subprocess.check_output(["git", "-C", str(ROOT), "archive", baseline, "Sources"])
            subprocess.run(["tar", "-xf", "-", "-C", str(package)], input=sources, check=True)
        else:
            copytree(ROOT / "Sources", package / "Sources")
        for name in ("NXLibraryCoreTests", "ArcanePortingTests", "OortCoreTests"):
            folder = package / "Tests" / name
            folder.mkdir(parents=True)
            (folder / "Empty.swift").touch()
        app = package / "Sources/NXLibrary"
        change(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        change(app / "ViewModels/AppViewModel.swift", r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        isolate_startup(app)
        profile = package / "Sources/NXLibraryCore/App/AppDataProfile.swift"
        change(profile, r'public static let profile = [^\n]*',
               'public static let profile = AppDataProfile(home: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!), isDevelopment: true)')
        change(profile, r'public static var preferences: UserDefaults \{ [^\n]+ \}',
               'nonisolated(unsafe) public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        with (app / "ViewModels/AppViewModel+CloudLibrary.swift").open("a") as file:
            file.write(FIXTURE)
        dialog = app / "Views/Settings/CloudReferenceDialog.swift"
        # ImageRenderer cannot draw the AppKit text field. Keep the actual field's layout and model.
        change(dialog, r'                TextField\(.*?\.onExitCommand\(perform: onClose\)',
               '                Text(draft.isEmpty ? text("Google Drive folder link or ID") : draft)\n'
               '                    .frame(maxWidth: .infinity, alignment: .leading)')
        change(dialog, r'        \.onAppear \{.*?\n        }\n', "")
        with dialog.open("a") as file:
            file.write("\nextension CloudReferenceDialog {\n"
                       "    func probeDraft(_ draft: String) -> Self {\n"
                       "        var copy = self\n"
                       "        copy._draft = State(initialValue: draft)\n"
                       "        return copy\n"
                       "    }\n}\n")
        change(app / "Views/OortUI/SeleneConfirmDialog.swift", r'focused: highlightsPills && focus == button,',
               r'focused: CloudScreenProbe.measure(label, highlightsPills && focus == button, enabled),')
        change(app / "Views/Settings/SettingsCloudLibrarySection.swift",
               r'(SeleneRow\(model.referenceCheck.*?SeleneStatusDot\(text: )(.*?), color:',
               lambda match: match[1] + f"CloudScreenProbe.measureLabel({match[2]}), color:")
        helper = HOST[HOST.index("    @MainActor static func renderNotice"):].replace(
            "/* NOTICE_LAYOUT */", "cancelIndex: notice.cancelIndex,")
        host = HOST.split("        // SCENARIO")[0] + SCENARIO + helper
        (app / "ReferenceProbe.swift").write_text(cloud_settings_fixture(app, host))
        subprocess.run(["swift", "build", "--jobs", "4", "--package-path", str(package)], check=True)
        home = package / "home"
        (home / "Library" / "Preferences").mkdir(parents=True)
        sandbox = ('(version 1) (allow default) (deny network*) '
                   '(deny file-read-data file-write* (subpath (param "REAL_LIBRARY")) (subpath "/Volumes")) '
                   '(deny file-write* (subpath "/Applications"))')
        real_library = Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library"
        result = subprocess.run(["sandbox-exec", "-D", f"REAL_LIBRARY={real_library}", "-p", sandbox,
                                 str(package / ".build/debug/NXLibrary"), str(output),
                                 str(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"),
                                 str(ROOT / "Resources/AppIcon-Light.png")],
                                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
        if result.returncode or baseline:
            raise SystemExit(result.returncode or "The baseline unexpectedly passed.")


if __name__ == "__main__":
    main()
