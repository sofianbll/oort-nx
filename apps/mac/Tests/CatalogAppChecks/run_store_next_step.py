#!/usr/bin/env python3
"""Render the real Details header in French, with only in-memory cloud replies, on the shared Debug app."""
import re
import sys
import tempfile
from pathlib import Path

from audit_probe_host import run_host
from probe_visible import source, text_render
from screen_host import ICON, header, package_name, render

FIXTURES = r'''
extension CloudLibraryModel {
    func installNextStepFixture() {
        let fixture = RcloneStorageBackend(remote: "fixture", root: "Games") { _, _, _ in
            preconditionFailure("The Details probe must not read cloud storage")
        }
        oortProbeInstallArchives(CloudGameArchive(backend: fixture),
                                 sources: CloudGameSources(backend: fixture, root: "Games/GameFiles"))
    }
}

extension CloudArtifactStatus {
    static func nextStepFixture(_ state: State) -> Self {
        .init(state: state, hasLocalCopy: false, bytes: 100, uploadedAt: .now, skippedRoots: [], remoteFolder: nil)
    }
}
'''

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
    text_checks = (Path(__file__).parent / "StoreNextStepText.swift").read_text()
    host = header() + SCENARIOS + text_render(render(), only='name.hasSuffix("-1120")') + text_checks + FIXTURES
    run_host(host, source(), save_model=True, capture=output, resources=(ICON,), package_name=package_name())


if __name__ == "__main__":
    main()
