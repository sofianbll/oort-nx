#!/usr/bin/env python3
"""Render the real Details header in French, with only in-memory cloud replies."""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from run_cloud_screens import HOST, ROOT, build_probe, change

SCENARIOS = r'''
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        let cloud = vm.cloudLibrary
        cloud.installNextStepFixture()
        let fr = AppLocale(language: .french, region: "FR")
        let game = PortedGame(name: "Observatoire lunaire", url: data.appendingPathComponent("Fixture.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: "0100000000001000")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let source = data.appendingPathComponent("Fixture.nsp")
        try Data([0]).write(to: source)
        let en = AppLocale(language: .english, region: "US")
        let scenarios = ["online-app", "offline-local", "offline-app", "offline-cache", "reference-files",
                         "local-files", "engine-blocked", "cache-only", "unchecked",
                         "running", "verifying", "waiting", "queued", "refreshing", "blocked"]
        for state in scenarios {
            var displayed = game
            cloud.states[game.id] = .init()
            cloud.localSourceIDs.removeAll()
            cloud.catalogChecked = state != "unchecked"
            cloud.remember { $0.referenceFiles.removeAll() }
            switch state {
            case "offline-local": displayed.status = .builtSourcesMissing
            case "local-files", "engine-blocked":
                displayed.sources = [.init(url: source, name: source.lastPathComponent, sizeBytes: 1, type: .base)]
                cloud.localSourceIDs.insert(game.id)
            default: break
            }
            cloud.checkFailure = state.hasPrefix("offline-") ? .offline : nil
            cloud.update(game.id) {
                if state == "reference-files" {
                    displayed.cloudSourcesReferenceFolder = "fixture-reference"
                } else if ["offline-cache", "cache-only", "unchecked"].contains(state) {
                    $0.availability[.cache] = .nextStepFixture(.cloudOnly)
                } else if !["offline-local", "local-files", "engine-blocked"].contains(state) {
                    $0.availability[.app] = .nextStepFixture(.cloudOnly)
                }
                $0.refreshing = state == "refreshing"
                if ["running", "verifying", "waiting", "queued"].contains(state) {
                    $0.action = .restore(.app)
                    $0.queued = state == "queued"
                    $0.progress = switch state {
                    case "running": .init(.downloading, kind: .app,
                        transfer: .init(bytesTransferred: 42_000_000, totalBytes: 100_000_000))
                    case "verifying": .init(.verifying, kind: .app, downloadComplete: true)
                    case "waiting": .init(.readyToInstall, kind: .app, downloadComplete: true)
                    default: nil
                    }
                }
            }
            if state == "reference-files" { cloud.remember { $0.referenceFiles.insert(game.id) } }
            L10n.setContext(fr)
            let presentation = GameDetailPresentation(game: displayed, metadata: nil, totalPlaytime: 0, lastPlayed: nil)
            L10n.setContext(en) // The view uses its own locale, not the previous global render's.
            for (width, height) in [(1120, 535), (700, 335)] {
                let scale = CGFloat(width) / 1120
                let screen = DetailsTopBlock(game: displayed, logo: nil,
                    presentation: presentation, isRunning: false, focusedPill: 0,
                    primaryEnabled: presentation.canPlay || (presentation.canRebuild && state != "engine-blocked"),
                    expanded: .constant(false),
                    onPrimary: {}, onSecondary: {}, onFavorite: {}, onHoverPill: { _ in },
                    pillSet: vm.portingPills(displayed).detailsPresentation(cloudOnly: cloud.downloadItem(for: displayed) != nil),
                    cloud: cloud, showsCloudPill: true, downloadEnabled: state != "blocked")
                    .environment(\.nxAppLocale, fr)
                    .environment(\.seleneCanvas, SeleneCanvas(size: .init(width: 1920 * scale, height: 1080 * scale)))
                try render("\(state)-\(width)", output, screen, size: .init(width: width, height: height))
            }
        }
        let status = SelenePillButton(title: "Play", focused: true) {}
        try render("shared-active", output, status.environment(\.nxAppLocale, fr), size: .init(width: 330, height: 90))
        try render("shared-download", output, SelenePillButton(title: "Download", focused: true, downloadFill: 0.42) {}
            .environment(\.nxAppLocale, fr), size: .init(width: 330, height: 90))
        try checkNextStepText(output)
    }
'''


def main():
    output = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="store-next-captures-")).resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="store-next-") as temp:
        package = Path(temp)
        home = package / "home"
        (home / "Library/Preferences").mkdir(parents=True)
        shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
        shutil.copytree(ROOT / "Sources", package / "Sources")
        for target in ("NXLibraryCoreTests", "ArcanePortingTests", "OortCoreTests"):
            folder = package / "Tests" / target
            folder.mkdir(parents=True)
            (folder / "Empty.swift").touch()
        app = package / "Sources/NXLibrary"
        change(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        vm = app / "ViewModels/AppViewModel.swift"
        change(vm, r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        change(vm, r"        applyCatalog\(catalog\).*?\n    }\n\n    // MARK: - Dynamic", "    }\n\n    // MARK: - Dynamic")
        profile = package / "Sources/NXLibraryCore/App/AppDataProfile.swift"
        change(profile, r"public static let profile = [^\n]*",
               'public static let profile = AppDataProfile(home: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!), isDevelopment: true)')
        change(profile, r"public static var preferences: UserDefaults \{ [^\n]+ \}",
               'nonisolated(unsafe) public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        with (app / "ViewModels/AppViewModel+CloudLibrary.swift").open("a") as file:
            file.write('''
extension CloudLibraryModel {
    func installNextStepFixture() {
        let fixture = RcloneStorageBackend(remote: "fixture", root: "Games") { _, _, _ in
            preconditionFailure("The Details probe must not read cloud storage")
        }
        archive = CloudGameArchive(backend: fixture)
        sourceArchive = CloudGameSources(backend: fixture, root: "Games/GameFiles")
    }
}
''')
        with (package / "Sources/ArcanePorting/Library/CloudGameArchive.swift").open("a") as file:
            file.write('''
extension CloudArtifactStatus {
    public static func nextStepFixture(_ state: State) -> Self {
        .init(state: state, hasLocalCopy: false, bytes: 100, uploadedAt: .now, skippedRoots: [], remoteFolder: nil)
    }
}
''')
        render = re.search(r"    @MainActor static func render<V: View>.*", HOST, flags=re.S).group()
        render = render.replace("try png.write(to: output.appendingPathComponent(name + \".png\"))",
                                'let imageURL = output.appendingPathComponent(name + ".png")\n'
                                '        try png.write(to: imageURL)\n'
                                '        if name.hasSuffix("-1120") { try saveProbeText(renderer, beside: imageURL) }')
        text_checks = (Path(__file__).parent / "StoreNextStepText.swift").read_text()
        (app / "StoreNextStepProbe.swift").write_text(
            HOST.split("        // SCENARIO")[0] + SCENARIOS + render + text_checks)
        shutil.copyfile(Path(__file__).with_name("ProbeRenderedText.swift"), app / "ProbeRenderedText.swift")
        subprocess.run([str(build_probe(package)),
                        str(output), str(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"),
                        str(ROOT / "Resources/AppIcon-Light.png")], check=True,
                       env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))


if __name__ == "__main__":
    main()
