#!/usr/bin/env python3
"""Exercise Steam's real process matching with synthetic process observations."""
from audit_probe_host import ROOT, run_host

HOST = r'''
import Foundation
@testable import NXLibrary
import NXLibraryCore

@main struct Check {
    @MainActor static func main() throws {
        assertFixtureHome()
        let data = AppData.supportRoot
        let root = data.appendingPathComponent("fake-steam")
        let gameURL = root.appendingPathComponent("Fixture.app")
        let executable = gameURL.appendingPathComponent("Contents/MacOS/Game")
        let app = try JSONDecoder().decode(CatalogNativeApplication.self, from: JSONSerialization.data(withJSONObject: [
            "url": gameURL.absoluteString, "executableURL": executable.absoluteString, "name": "Fixture",
            "architectures": ["arm64"], "isDeclaredGame": true,
        ]))
        var record = SteamCatalogGame(appID: 440, name: "Fixture")
        record.installations = [.init(libraryURL: root, contentURL: root, applications: [app], availability: .available)]
        let game = CatalogGame(steam: record)
        let on = CatalogSourceConfiguration(integration: .steam, isEnabled: true, rootURL: root)
        let off = CatalogSourceConfiguration(integration: .steam, isEnabled: false, rootURL: root)
        let store = PlaySessionStore()
        let coordinator = FixtureSteamPlayCoordinator()
        coordinator.start(sessions: store, settings: .init(fileURL: data.appendingPathComponent("settings.json")))
        defer { coordinator.stop() }
        coordinator.setGames([game], sources: [on])
        coordinator.fixtureProcesses = [.init(pid: 999_999, bundleURL: gameURL, executableURL: executable)]
        coordinator.refresh()
        precondition(store.isRunning(gameID: game.id))
        coordinator.setGames([game], sources: [off])
        precondition(store.isRunning(gameID: game.id), "An existing session should not be ended by disabling the source")
        coordinator.fixtureProcesses = []
        coordinator.refresh()
        precondition(!store.isRunning(gameID: game.id) && store.sessions.count == 1)
        coordinator.fixtureProcesses = [.init(pid: 999_998, bundleURL: gameURL, executableURL: executable)]
        coordinator.refresh()
        guard !store.isRunning(gameID: game.id), store.sessions.count == 1 else {
            fputs("A disabled Steam source starts another session for a known game\n", stderr)
            exit(1)
        }
        print("Disabling Steam closes finished sessions but does not track another launch")
    }
}
'''

if __name__ == "__main__":
    coordinator = (ROOT / "Sources/NXLibrary/Services/SteamPlayCoordinator.swift").read_text()
    coordinator = "@testable import NXLibrary\n" + coordinator.replace("SteamPlayCoordinator", "FixtureSteamPlayCoordinator")
    start = coordinator.index("        var resolved: [Int32: NativeProcessObservation]")
    end = coordinator.index("        let now = Date()", start)
    coordinator = coordinator[:start] + "        let processes = fixtureProcesses\n" + coordinator[end:]
    coordinator = coordinator.replace("    func refresh(heartbeat:", "    var fixtureProcesses: [NativeProcessObservation] = []\n\n    func refresh(heartbeat:")
    run_host(HOST, coordinator)
