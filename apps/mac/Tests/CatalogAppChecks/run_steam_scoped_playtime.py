#!/usr/bin/env python3
"""Refresh synthetic Steam totals after play on a secondary profile."""
from audit_probe_host import run_host

HOST = r'''
import Foundation
@testable import OortMac
import OortLibrary

@main struct Check {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        assertFixtureHome()
        let data = AppData.supportRoot
        let root = data.appendingPathComponent("fake-steam")
        func write(_ text: String, _ relative: String, stamp: Int = 0) throws {
            let file = root.appendingPathComponent(relative)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
            if stamp != 0 {
                try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(stamp))], ofItemAtPath: file.path)
            }
        }
        func playtime(_ minutes: Int) throws {
            try write("""
                "UserLocalConfigStore" {
                    "Software" { "Valve" { "Steam" { "apps" { "440" { "Playtime" "\(minutes)" } } } } }
                }
                """, "userdata/42/config/localconfig.vdf", stamp: 1_700_000_000 + minutes)
        }
        try write(#""users" { "76561197960265770" { "MostRecent" "1" "timestamp" "1" } }"#, "config/loginusers.vdf")
        try playtime(10)
        var date = Date(timeIntervalSince1970: 1_600_000_000)
        let store = PlaySessionStore(now: { date })
        let steam = CatalogGame(steam: SteamCatalogGame(appID: 440, name: "Synthetic Steam"))
        let sync = SteamPlaytimeCoordinator()
        sync.setGames([steam], sources: [.init(integration: .steam, isEnabled: true, rootURL: root)])
        sync.start(sessions: store)
        defer { sync.stop() }
        func waitFor(_ minutes: Double) async throws -> Bool {
            let deadline = ContinuousClock.now + .seconds(3)
            while store.external[steam.id]?.duration != minutes * 60 && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            return store.external[steam.id]?.duration == minutes * 60
        }
        let loaded = try await waitFor(10)
        precondition(loaded, "Fixture must import an initial baseline")
        store.profileID = UUID()
        let first = UUID(), other = UUID()
        for index in 0...PlaySessionStore.maxSessions {
            let id = index == 0 ? first : other
            store.start(gameID: id, sourceID: "0100000000000001")
            date.addTimeInterval(10)
            store.end(gameID: id)
        }
        precondition(store.carried[first]?.duration == 10)
        store.profileID = nil
        try playtime(70)
        sync.refresh()
        guard try await waitFor(70) else {
            fputs("A secondary Switch session freezes Steam at its previous baseline\n", stderr)
            exit(1)
        }
        store.profileID = UUID()
        store.start(gameID: steam.id, sourceID: "steam-440")
        date.addTimeInterval(10)
        store.end(gameID: steam.id)
        for _ in 0...PlaySessionStore.maxSessions {
            store.start(gameID: other, sourceID: "0100000000000001")
            date.addTimeInterval(10)
            store.end(gameID: other)
        }
        precondition(store.carried[steam.id]?.duration == 10)
        store.profileID = nil
        try playtime(71)
        sync.refresh()
        try await Task.sleep(for: .milliseconds(300))
        precondition(store.external[steam.id]?.duration == 70 * 60)
        print("Switch sessions do not block Steam updates; secondary Steam sessions do")
    }
}
'''

if __name__ == "__main__":
    run_host(HOST)
