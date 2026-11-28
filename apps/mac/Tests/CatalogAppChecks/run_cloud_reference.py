#!/usr/bin/env python3
"""Check reference-library copy and controls on the real Selene views with a fake Drive, on the shared Debug app.

cloud_reference_baseline.py runs the same check on a past revision, where it must fail."""
from audit_probe_host import run_host
from run_cloud_screens import ROOT, capture_destination, cloud_settings_fixture
from screen_host import ICON, header, package_name, render

SCENARIO = r'''
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        // Offscreen: the dialog's text field drawn as text, and what the action bar and the status dot draw.
        CloudReferenceDialog.oortProbeStill = true
        OortProbeObserver.actionKey = { title, focused, enabled in if title == "Save" { measuredSave = (focused, enabled) } }
        OortProbeObserver.statusText = { labels.append($0) }
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
        vm.cloudLibrary.oortProbeInstallReference(fixture, folder: folder)
        let (added, warnings) = await vm.oortProbeImportReference(archive: vm.cloudLibrary.archive!)
        precondition(!added && vm.cloudLibrary.referenceCheck?.incomplete == true && warnings.count == 1)
        vm.showSettingsNotice(title: "Reference library", message: warnings[0])
        let warning = warnings[0]
        if !warning.contains(title) || !warning.contains("pas été ajoutés") { failures.append("Unreadable game: \(warning)") }
        for width in [1280.0, 720.0] {
            let size = CGSize(width: width, height: 1000)
            let suffix = width > 1000 ? "-wide" : "-narrow"
            for (name, draft) in [("editor", ""), ("editor-invalid", "https://example.test/file"),
                                  ("editor-valid", folder)] {
                measuredSave = nil
                try render("reference-\(name)\(suffix)", output, CloudReferenceDialog(viewModel: vm, onClose: {})
                    .oortProbeDraft(draft).environment(\.nxAppLocale, fr), size: size)
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
                    viewModel: vm, model: model, settings: /* CLOUD_SETTINGS */ SettingsEditor(settings), advanced: .constant(true),
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


def main():
    output = capture_destination("cloud-reference-captures-")
    output.mkdir(parents=True, exist_ok=True)
    helper = render("    @MainActor static func renderNotice").replace("/* NOTICE_LAYOUT */", "cancelIndex: notice.cancelIndex,")
    host = cloud_settings_fixture(ROOT / "apps/mac/OortMac", header() + SCENARIO + helper)
    run_host(host, save_model=True, capture=output, resources=(ICON,), package_name=package_name())


if __name__ == "__main__":
    main()
