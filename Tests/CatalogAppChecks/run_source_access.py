#!/usr/bin/env python3
"""Check source-access triggers using the real startup block, observer and pickers.

No AppKit windows or player data: replace the picker and the scanner I/O boundary,
then count requests made by the actual PortingModel and AppViewModel code, as in run_review.py.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = ''.join(p.read_text() for p in sorted((ROOT / 'apps/mac/OortMac/ViewModels').glob('AppViewModel*.swift')))
porting_source = ''.join(p.read_text() for p in sorted((ROOT / 'apps/mac/OortMac/ViewModels').glob('PortingModel*.swift')))


def declaration(signature, source=source):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


startup = source[source.index('        setup.restoreBuildInputs(automatic: true,'):
                 source.index('        recoverSavesAtStartup()')]
host = r'''
import Foundation
import Combine
import UniformTypeIdentifiers

final class Preferences {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func bool(forKey key: String) -> Bool { false }
    func set(_ value: String?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}
enum AppData {
    static let preferences = Preferences()
    struct Profile { var isDevelopment = false }
    static var profile = Profile()
}
enum StorageKeys {
    static let savedGameFolder = "fixture-folder"
    static let onboardingFreshProfile = "fixture-fresh"
}
struct Startup { var checkEngineAtLaunch = true; var refreshLibraryAtLaunch = true }
struct GameRuntimeConfig {}
final class SettingsStore {
    struct Choices { var gameSourcesPath: String? }
    struct Settings { var launcherChoices = Choices() }
    var settings = Settings()
}
struct SetupPage { let isGuided = false }
struct FirstRunSetup { let page = SetupPage() }
enum GameFoldersCopy {
    static let sourcesTitle = "Game files"
    static func sourcesPickerMessage(extractedFolders: Bool) -> String { "Fixture picker" }
}
enum ExtractedSourceCatalog {
    static func recognizes(_ folder: URL) -> Bool { folder.lastPathComponent == "Extracted fixture" }
}

// Only the picker is substituted; save its completion to exercise delayed selection.
enum OortFilePickerPresentation {
    enum Choice { case folder, gameFiles(allowFolder: Bool) }
    static var picked: [URL] = []
    static var openedAt: URL?
    static var completion: (([URL]) -> Void)?
    static func open(_ choice: Choice, title: String, message: String, startingAt: URL?, completion: @escaping ([URL]) -> Void) {
        openedAt = startingAt
        self.completion = completion
    }
}

enum L10n { static func text(_ key: String) -> String { key } }

final class SourceHost {
    private var keepsRememberedGameFolder = false
    private var restoringGameFolder = false
    private var selectedPackageURLs: [URL]?
    var scanGeneration = UUID()
    var detectedGames: [Int] = []
    var selectedGame: Int?
    var selectedSourceIDs: Set<UUID> = []
    var scanError: String?
    var isScanningGameFolder = false
    var engineSourceCapabilities = (extractedFolders: true, unused: false)
    var scans: [(folder: URL, files: [URL]?)] = []
    // The Add game draft lives in PortingModel, which reaches the coordinator through `app`.
    static let savedGameFolderKey = StorageKeys.savedGameFolder
    var app: SourceHost { self }
    var setup: SourceHost { self }
    var settingsStore: SettingsStore?
    // ACTUAL_FOLDER
    // ACTUAL_LEGACY_PATH
    // ACTUAL_REMEMBER_FOLDER
    // ACTUAL_REMEMBERED_FOLDER
    // ACTUAL_FOLDER_PICKER
    // ACTUAL_FILE_PICKER
    // ACTUAL_PREPARE_FILES
    // ACTUAL_FILE_CHOOSER
    let firstRunSetup = FirstRunSetup()
    func restoreBuildInputs(automatic: Bool, readKeys: Bool) {}
    func refreshCompatibility() {}
    func startNewAddGame(defaults: GameRuntimeConfig) {
        keepsRememberedGameFolder = true
        selectedGameFolder = nil
        keepsRememberedGameFolder = false
    }
    func scanGameFolder(_ folder: URL) { scans.append((folder, selectedPackageURLs)) }
    func boot(_ startup: Startup) {
        // ACTUAL_STARTUP
    }
}

@main struct Check {
    static func main() {
        var failures = 0
        func require(_ ok: @autoclosure () -> Bool, _ message: String) {
            if !ok() { failures += 1; print("FAIL: " + message) }
        }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Downloads")
        AppData.preferences.set(folder.path, forKey: StorageKeys.savedGameFolder)
        for development in [false, true] {
            AppData.profile.isDevelopment = development
            for refresh in [false, true] {
                let model = SourceHost()
                model.boot(Startup(refreshLibraryAtLaunch: refresh))
                require(model.scans.isEmpty, "Launch must not scan remembered sources (refresh=\(refresh), dev=\(development))")
                require(model.selectedGameFolder == nil, "Launch must leave the Add game draft empty")
                require(model.gameFilesFolder == folder, "Launch must keep the remembered folder preference")
            }
        }

        let model = SourceHost()
        model.boot(Startup())
        var folderPicked = false
        model.selectGameFolder(onPick: { folderPicked = true })
        OortFilePickerPresentation.completion = nil
        require(!folderPicked, "Cancelling the picker must not report a choice")
        require(model.scans.isEmpty, "Cancelling the picker must not scan sources")
        require(OortFilePickerPresentation.openedAt == folder, "The folder picker receives the remembered folder")

        model.selectGameFolder(onPick: { folderPicked = true })
        OortFilePickerPresentation.completion?([folder])
        require(folderPicked, "An explicit folder choice must be accepted")
        require(model.scans.count == 1 && model.scans.last?.folder == folder,
                "An explicit folder choice must request one scan")

        let otherFolder = folder.deletingLastPathComponent().appendingPathComponent("Other inputs")
        let files = [otherFolder.appendingPathComponent("chosen.nsp"), otherFolder.appendingPathComponent("update.nsp")]
        let filesModel = SourceHost()
        filesModel.boot(Startup())
        var filesPicked = false
        filesModel.selectGameFiles(onPick: { filesPicked = true })
        require(!filesPicked && filesModel.scans.isEmpty, "Opening the picker must not scan sources")
        OortFilePickerPresentation.completion?(files)
        require(filesPicked, "Explicit file choices must be accepted")
        require(filesModel.scans.count == 1 && filesModel.scans.last?.files == files,
                "Explicit files must request one scan limited to those files")
        require(filesModel.gameFilesFolder == folder, "File picks must preserve the remembered folder")

        let extracted = otherFolder.appendingPathComponent("Extracted fixture")
        require(filesModel.prepareAddGameFiles([extracted], defaults: GameRuntimeConfig()), "Extracted source must open a draft")
        require(filesModel.scans.last?.folder == extracted && filesModel.scans.last?.files == nil,
                "Add Game must scan the extracted directory itself")
        if failures > 0 { exit(1) }
        print("Source access checks passed: no launch scan, remembered picker, cancel, explicit files and extracted draft.")
    }
}
'''
for marker, signature in (
    ('// ACTUAL_FOLDER', '    @Published var selectedGameFolder:'),
    ('// ACTUAL_LEGACY_PATH', '    var legacyGameSourcesPath:'),
    ('// ACTUAL_REMEMBER_FOLDER', '    func rememberGameFilesFolder('),
    ('// ACTUAL_REMEMBERED_FOLDER', '    var gameFilesFolder:'),
    ('// ACTUAL_FOLDER_PICKER', '    func selectGameFolder('),
    ('// ACTUAL_FILE_PICKER', '    func selectGameFiles('),
    ('// ACTUAL_PREPARE_FILES', '    func prepareAddGameFiles('),
    ('// ACTUAL_FILE_CHOOSER', '    func chooseGameFiles('),
):
    host = host.replace(marker + '\n', declaration(signature, porting_source) + '\n')
host = host.replace('// ACTUAL_STARTUP', startup)
with tempfile.TemporaryDirectory(prefix='source-access-check-') as folder:
    scratch = Path(folder)
    swift = scratch / 'check.swift'
    swift.write_text(host)
    executable = scratch / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(scratch)], check=True)
