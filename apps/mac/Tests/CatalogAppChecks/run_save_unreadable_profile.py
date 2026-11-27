#!/usr/bin/env python3
"""An invalid profile list must not expose or modify the original save."""
from audit_probe_host import run_host

HOST = r'''
import Foundation
@testable import NXLibrary
import OortLibrary
import NxnativeAdapter

@main struct Check {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        assertFixtureHome()
        suppressProbeNotifications()
        let data = AppData.supportRoot
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        settings.settings.checkEngineAtLaunch = false
        settings.settings.refreshLibraryAtLaunch = false
        AppData.preferences.set(true, forKey: AppViewModel.StorageKeys.setupCompleted)
        AppData.preferences.set(data.appendingPathComponent("Apps").path, forKey: AppViewModel.StorageKeys.savedLibraryFolder)
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("bad profile data".utf8).write(to: data.appendingPathComponent("profiles.json"))
        let profiles = LocalProfileStore(directory: data, settings: settings.settings, name: "Fixture")
        precondition(profiles.failed && profiles.active == nil)
        let game = PortedGame(name: "Save fixture", url: data.appendingPathComponent("Fixture.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: "0100000000000001")
        let vm = AppViewModel(settingsStore: settings, catalog: .init(games: [.init(nxnative: game)]),
                              repository: .init(store: .init(directory: data)), localProfiles: profiles)
        let plist = game.url.appendingPathComponent("Contents/Info.plist")
        try fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["DMTitleID": game.titleId!], format: .xml, options: 0)
            .write(to: plist)
        let original = try vm.legacySaveLocation(for: game)
        let slot = original.directory(.account)
        try fm.createDirectory(at: slot, withIntermediateDirectories: true)
        let marker = slot.appendingPathComponent("progress")
        try Data("original profile".utf8).write(to: marker)
        let panel = SavePanelModel(viewModel: vm, game: game)
        panel.refresh()
        let deadline = ContinuousClock.now + .seconds(5)
        while panel.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard panel.issue != nil, panel.context == nil, !panel.canMutate,
              (try? vm.defaultSaveLocation(for: game)) == nil,
              (try? vm.saveContext(for: game)) == nil else {
            fputs("The save panel resolves the original profile after reading a corrupt profile list\n", stderr)
            exit(1)
        }
        panel.backUp()
        precondition(!panel.busy)
        panel.showBackups()
        precondition(panel.issue?.message == SaveFailure.profilesUnavailable.localizedDescription)
        let journal = original.root.appendingPathComponent(".nxlibrary-save-transaction.json")
        try Data("do not recover".utf8).write(to: journal)
        vm.recoverSavesAtStartup()
        precondition(!vm.saveGate.hasActiveOperations)
        precondition(!fm.fileExists(atPath: data.appendingPathComponent("SaveBackups").path))
        precondition(try! String(contentsOf: marker, encoding: .utf8) == "original profile")
        print("Unreadable profiles cannot access or write original saves")
    }
}
'''

if __name__ == "__main__":
    run_host(HOST, save_model=True)
