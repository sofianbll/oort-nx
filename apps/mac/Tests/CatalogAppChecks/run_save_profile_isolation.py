#!/usr/bin/env python3
"""Exercise the debug app's save routing, without launching it or using real data."""
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
        let profiles = LocalProfileStore(directory: data, settings: settings.settings, name: "Original")
        let a = LocalProfile(name: "A", look: profiles.active!.look)
        let b = LocalProfile(name: "B", look: profiles.active!.look)
        precondition(profiles.update(a) && profiles.update(b) && profiles.choose(a.id))
        let game = PortedGame(name: "Save isolation", url: data.appendingPathComponent("Fixture.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: "0100000000000001")
        let vm = AppViewModel(settingsStore: settings, catalog: .init(games: [.init(nxnative: game)]),
                              repository: .init(store: .init(directory: data)), localProfiles: profiles)
        let location = try vm.defaultSaveLocation(for: game)
        try fm.createDirectory(at: location.root, withIntermediateDirectories: true)
        let journal = location.root.appendingPathComponent(".nxlibrary-save-transaction.json")
        try Data("unrecoverable fixture".utf8).write(to: journal)
        precondition(!vm.savesPermitPlay(game))
        let deadline = ContinuousClock.now + .seconds(5)
        while vm.saveGate.hasActiveOperations && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(!vm.saveGate.hasActiveOperations)
        precondition(fm.fileExists(atPath: journal.path))
        precondition(profiles.choose(b.id))
        guard vm.savesPermitPlay(game) else {
            fputs("A failed recovery blocks Play in profile B\n", stderr)
            exit(1)
        }
        precondition(profiles.choose(a.id) && !vm.savesPermitPlay(game))
        print("Save recovery is isolated to its own profile")
    }
}
'''

if __name__ == "__main__":
    run_host(HOST, save_model=True)
