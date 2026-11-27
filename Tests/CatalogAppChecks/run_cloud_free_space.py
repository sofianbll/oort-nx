#!/usr/bin/env python3
"""Check and render Cloud library's free-space confirmation on synthetic copies."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from probe_visible import install, text_render
from run_cloud_screens import HOST, ROOT, build_probe, capture_destination, change, isolate_cloud_init, isolate_startup
import names  # noqa: E402  architecture/names.json (on sys.path from run_cloud_screens)

SCENARIO = r'''
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        let model = vm.cloudLibrary
        let game = PortedGame(name: "Observatoire lunaire", url: data.appendingPathComponent("Fixture.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: "0100000000001000")
        func copy(_ state: CloudArtifactStatus.State, _ bytes: Int64?) -> CloudArtifactStatus {
            .init(state: state, hasLocalCopy: state != .cloudOnly, bytes: bytes, uploadedAt: nil, skippedRoots: [])
        }
        let panel = CloudLibraryPanel(viewModel: vm, model: model, game: game)
        model.update(game.id) { $0.copies = [.app: copy(.synchronized, 100_000_000), .cache: copy(.synchronized, 50_000_000)] }
        let both = CloudFreeSelection(state: model.states[game.id]!)
        precondition(both.selected == [.app, .cache])
        precondition(panel.offersFreeForProbe())
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let sample = Data([42])
        try sample.write(to: game.url)
        panel.checkCancelForProbe(both)
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
        precondition(!panel.offersFreeForProbe(), "Reference-only and modified local copies must not be offered")
        model.update(game.id) {
            $0.referenceKinds = []
            $0.referenceAvailability = [:]
            $0.copies = [.app: copy(.cloudOnly, 100_000_000)]
            $0.action = .restore(.app)
            $0.progress = .init(.verifying, kind: .app, downloadComplete: true)
        }
        precondition(panel.canCancelDownloadForProbe())
        for (width, label) in [(1440.0, "wide"), (780.0, "narrow")] {
            let size = CGSize(width: width, height: 720)
            try render("free-both-\(label)", output, panel.freeForProbe(both).environment(\.nxAppLocale, fr), size: size)
            try render("free-cache-\(label)", output, panel.freeForProbe(cacheOnly).environment(\.nxAppLocale, fr), size: size)
            try render("free-unknown-\(label)", output, panel.freeForProbe(unknown).environment(\.nxAppLocale, fr), size: size)
            try render("free-none-\(label)", output, panel.freeForProbe(none).environment(\.nxAppLocale, fr), size: size)
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
        if !failures.isEmpty {
            for failure in failures { FileHandle.standardError.write(Data((failure + "\n").utf8)) }
            exit(1)
        }
    }

'''


def main():
    output = capture_destination("cloud-free-captures-")
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cloud-free-") as temporary:
        package = Path(temporary)
        names.stage(package)
        app = package / "Sources/NXLibrary"
        change(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        change(app / "ViewModels/AppViewModel.swift", r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        change(app / "ViewModels/AppViewModel.swift", r"let root = SystemDetector.shared.resolveRootDirectory\(\)",
               "let root = AppData.profile.home")
        isolate_startup(app, keep_catalog=True)
        profile = package / "Sources/NXLibraryCore/App/AppDataProfile.swift"
        change(profile, r"public static let profile = [^\n]*",
               'public static let profile = AppDataProfile(home: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!), isDevelopment: true)')
        change(profile, r"public static var preferences: UserDefaults \{ [^\n]+ \}",
               'nonisolated(unsafe) public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        isolate_cloud_init(app / "ViewModels/AppViewModel+CloudLibrary.swift",
               '        preference = .init(storage: "fixture:Games", enabled: true, sourcesRoot: nil)\n'
               '        chosenExecutable = nil\n')
        change(app / "ViewModels/AppViewModel+CloudLibrary.swift", r"    private func rebuildArchive\(\) \{.*?\n    \}",
               '''    private func rebuildArchive() {
        archive = .init(backend: RcloneStorageBackend(remote: "fixture", root: "Games",
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            config: AppData.profile.home.appendingPathComponent("never-configured.conf")))
    }''')
        panel = app / "Views/Detail/CloudLibraryPanel.swift"
        change(panel, r"        \.task\(id: ReadRequest.*?\n", "")
        # Bind installed state by hand only for the cancel check, without sending UI events.
        change(panel, r"    @State private var freeSelection: CloudFreeSelection\?",
               '''    @State private var sheetSelection: CloudFreeSelection?
    private var probeSelection: Binding<CloudFreeSelection?>? = nil
    private var freeSelection: CloudFreeSelection? {
        get { if let probeSelection { return probeSelection.wrappedValue }; return sheetSelection }
        nonmutating set {
            if let probeSelection { probeSelection.wrappedValue = newValue }
            else { sheetSelection = newValue }
        }
    }''')
        with panel.open("a") as file:
            file.write(r'''
extension CloudLibraryPanel {
    func freeForProbe(_ selection: CloudFreeSelection) -> Self {
        var panel = self
        panel._sheetSelection = State(initialValue: selection)
        return panel
    }
    func checkCancelForProbe(_ selection: CloudFreeSelection) {
        var current: CloudFreeSelection? = selection
        var panel = self
        panel.probeSelection = Binding(get: { current }, set: { current = $0 })
        panel.handle(.confirm) // Initial focus is Cancel.
        precondition(current == nil)
    }
    func offersFreeForProbe() -> Bool { controls.contains(.free) }
    func canCancelDownloadForProbe() -> Bool { artifactControl(.app) == .cancel }
}
''')
        preamble = HOST.split("        // SCENARIO", 1)[0]
        renderer = HOST[HOST.index("    @MainActor static func render<V: View>"):]
        renderer = renderer.replace("SeleneCanvas(size: .init(width: 1920, height: 1080))", "SeleneCanvas(size: size)")
        (app / "CloudScreenProbe.swift").write_text(preamble + SCENARIO + text_render(renderer))
        install(app)
        font = ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"
        icon = ROOT / "Resources/AppIcon-Light.png"
        home = package / "fixture-home"
        home.mkdir()
        subprocess.run([str(build_probe(package)), str(output), str(font), str(icon)], check=True,
                       env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))


if __name__ == "__main__":
    main()
