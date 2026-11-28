#!/usr/bin/env python3
"""Check and render Cloud library's free-space confirmation on synthetic copies. On the shared Debug app."""
from audit_probe_host import run_host
from probe_visible import source, text_render
from run_cloud_screens import capture_destination
from screen_host import ICON, header, package_name, render

SCENARIO = r'''
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
        // A cloud library the player chose, saved as the app saves it; its Drive tool was already chosen.
        AppData.preferences.set("fixture:Games", forKey: CloudLibraryPreference.storageKey)
        AppData.preferences.set(true, forKey: CloudLibraryPreference.enabledKey)
        AppData.preferences.set(true, forKey: CloudLibraryPreference.toolChoiceKey)
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        let model = vm.cloudLibrary
        precondition(model.preference.remote == "fixture" && model.preference.enabled && !model.needsDriveToolChoice)
        // Every read of this archive fails: the panel decides from the states set below, never from Drive.
        let fixtureArchive = CloudGameArchive(backend: RcloneStorageBackend(remote: "fixture", root: "Games",
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            config: AppData.profile.home.appendingPathComponent("never-configured.conf")))
        model.oortProbeInstallArchives(fixtureArchive)
        let game = PortedGame(name: "Observatoire lunaire", url: data.appendingPathComponent("Fixture.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: "0100000000001000")
        func copy(_ state: CloudArtifactStatus.State, _ bytes: Int64?) -> CloudArtifactStatus {
            .init(state: state, hasLocalCopy: state != .cloudOnly, bytes: bytes, uploadedAt: nil, skippedRoots: [])
        }
        let panel = CloudLibraryPanel(viewModel: vm, model: model, game: game)
        model.update(game.id) { $0.copies = [.app: copy(.synchronized, 100_000_000), .cache: copy(.synchronized, 50_000_000)] }
        let both = CloudFreeSelection(state: model.states[game.id]!)
        precondition(both.selected == [.app, .cache])
        precondition(panel.oortProbeOffersFree())
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let sample = Data([42])
        try sample.write(to: game.url)
        precondition(panel.oortProbeCancel(both) == nil)
        precondition(model.queue.isEmpty && model.states[game.id]?.action == nil)
        let afterCancel = try Data(contentsOf: game.url)
        precondition(afterCancel == sample)
        var cacheOnly = both
        cacheOnly.toggle(.app)
        precondition(cacheOnly.selected == [.cache])
        var none = cacheOnly
        none.toggle(.cache)
        precondition(none.selected.isEmpty)
        model.update(game.id) { $0.copies[.app] = copy(.synchronized, nil) }
        let unknown = CloudFreeSelection(state: model.states[game.id]!)
        model.update(game.id) {
            $0.copies = [.cache: copy(.newerOnThisMac, 50_000_000)]
            $0.referenceKinds = [.app]
            $0.referenceAvailability[.app] = copy(.cloudOnly, 100_000_000)
        }
        precondition(!panel.oortProbeOffersFree(), "Reference-only and modified local copies must not be offered")
        model.update(game.id) {
            $0.referenceKinds = []
            $0.referenceAvailability = [:]
            $0.copies = [.app: copy(.cloudOnly, 100_000_000)]
            $0.action = .restore(.app)
            $0.progress = .init(.verifying, kind: .app, downloadComplete: true)
        }
        precondition(panel.oortProbeCanCancelDownload())
        for (width, label) in [(1440.0, "wide"), (780.0, "narrow")] {
            let size = CGSize(width: width, height: 720)
            try render("free-both-\(label)", output, panel.oortProbeFree(both).environment(\.nxAppLocale, fr), size: size)
            try render("free-cache-\(label)", output, panel.oortProbeFree(cacheOnly).environment(\.nxAppLocale, fr), size: size)
            try render("free-unknown-\(label)", output, panel.oortProbeFree(unknown).environment(\.nxAppLocale, fr), size: size)
            try render("free-none-\(label)", output, panel.oortProbeFree(none).environment(\.nxAppLocale, fr), size: size)
            try render("verifying-\(label)", output, panel.environment(\.nxAppLocale, fr), size: size)
        }
        var failures: [String] = []
        func check(_ name: String, _ includes: String, _ excludes: String? = nil) throws {
            let text = try readProbeText(output, name: name).lowercased()
            if !text.contains(includes) || excludes.map(text.contains) == true {
                failures.append("\(name): expected \(includes), excluding \(excludes ?? "nothing"); saw \(text)")
            }
            failures += assertVisible(output, name: name, [includes])
        }
        for label in ["wide", "narrow"] {
            try check("free-both-\(label)", "150 mo")
            try check("free-cache-\(label)", "50 mo à mettre", "150 mo")
            try check("free-unknown-\(label)", "taille totale inconnue", "150 mo")
            try check("free-none-\(label)", "aucun élément sélectionné")
            try check("verifying-\(label)", "vérification", "télécharger")
        }
        precondition(model.archive === fixtureArchive, "The free-space probe must keep its failing archive")
        if !failures.isEmpty {
            for failure in failures { FileHandle.standardError.write(Data((failure + "\n").utf8)) }
            exit(1)
        }
    }

'''


def main():
    output = capture_destination("cloud-free-captures-")
    output.mkdir(parents=True, exist_ok=True)
    renderer = render().replace("SeleneCanvas(size: .init(width: 1920, height: 1080))", "SeleneCanvas(size: size)")
    run_host(header() + SCENARIO + text_render(renderer), source(), save_model=True, capture=output,
             resources=(ICON,), package_name=package_name())


if __name__ == "__main__":
    main()
