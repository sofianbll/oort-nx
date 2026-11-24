import Foundation
import XCTest
@testable import NXLibraryCore

final class LocalProfileStoreTests: XCTestCase {
    func testGuestDoesNotReplaceLastProfileOrShareFavorites() throws {
        try withDirectory { url in
            let store = LocalProfileStore(directory: url, settings: .init(), name: "Host")
            let host = try XCTUnwrap(store.active)
            let guest = LocalProfile(name: "Guest", avatar: LocalProfile.avatarCount - 1, look: host.look)
            let game = UUID()
            XCTAssertTrue(store.beginGuest(guest))
            XCTAssertTrue(store.toggleFavorite(game))
            XCTAssertEqual(store.active?.favorites, [game])
            XCTAssertEqual(store.profiles, [host])
            XCTAssertEqual(LocalProfileStore(directory: url, settings: .init(), name: "Host").active, host)
            XCTAssertTrue(store.choose(host.id))
            XCTAssertNil(store.guest)
            XCTAssertEqual(store.active?.favorites, [])
        }
    }

    func testLockedStartupAndIndependentPresencePreferences() throws {
        try withDirectory { url in
            let store = LocalProfileStore(directory: url, settings: .init(), name: "Host")
            let host = try XCTUnwrap(store.active)
            var locked = LocalProfile(name: "Locked", avatar: LocalProfile.avatarCount - 1, look: host.look)
            XCTAssertFalse(locked.setPIN("１２３４"))
            XCTAssertFalse(locked.setPIN("123"))
            XCTAssertTrue(locked.setPIN("0123"))
            XCTAssertFalse(locked.matchesPIN("1230"))
            XCTAssertTrue(locked.matchesPIN("0123"))
            XCTAssertFalse(locked.sharesPresence)
            locked.showsCurrentGame = true
            XCTAssertFalse(locked.sharesCurrentGame)
            locked.appearsOnline = true
            XCTAssertTrue(locked.sharesCurrentGame)
            XCTAssertTrue(store.update(locked))
            XCTAssertTrue(store.needsStartupPicker(.profile(locked.id)))
            XCTAssertEqual(store.startupSelection(.profile(locked.id)), locked.id)
            XCTAssertEqual(store.active?.id, host.id)
            XCTAssertTrue(store.choose(locked.id))
            let reopened = LocalProfileStore(directory: url, settings: .init(), name: "Host")
            XCTAssertTrue(reopened.needsStartupPicker(.last))
            XCTAssertTrue(reopened.active?.matchesPIN("0123") == true)
            XCTAssertTrue(locked.setPIN(nil))
            XCTAssertFalse(locked.isLocked)
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    func testMigrationCreatesOneProfileWithExistingLookAndRetainsLastChoice() throws {
        try withDirectory { url in
            var settings = AppSettings()
            settings.colorThemeID = "arcane-flow"
            settings.wallpaperID = "Custom/One"
            settings.settingsWallpaperID = "Custom/Two"
            settings.spotlightOrder = ["card:activity"]
            let store = LocalProfileStore(directory: url, settings: settings, name: "Local")
            let first = try XCTUnwrap(store.active)
            XCTAssertEqual(first.look, .init(settings))
            XCTAssertEqual(store.originalID, first.id)
            XCTAssertFalse(store.remove(first.id))
            XCTAssertNil(first.appearsOnline)
            var other = LocalProfile(name: "  Jade ", avatar: 2, look: .init(AppSettings()))
            other.appearsOnline = false
            XCTAssertTrue(store.update(other))
            XCTAssertEqual(store.active?.id, first.id)
            let profileFile = url.appendingPathComponent("profiles.json")
            let existing = try Data(contentsOf: profileFile)
            XCTAssertTrue(store.choose(other.id))
            XCTAssertEqual(try Data(contentsOf: profileFile), existing)
            XCTAssertEqual(LocalProfileStore(directory: url, settings: .init(), name: "Other").active?.id, other.id)
            let game = UUID()
            XCTAssertTrue(store.toggleFavorite(game))
            let reopened = LocalProfileStore(directory: url, settings: .init(), name: "Do not reimport")
            XCTAssertEqual(reopened.active?.name, "Jade")
            XCTAssertEqual(reopened.active?.favorites, [game])
            XCTAssertEqual(reopened.active?.appearsOnline, false)
            XCTAssertTrue(reopened.remove(other.id))
            XCTAssertEqual(reopened.active, first)
        }
    }

    func testCorruptProfileFileIsNotReplaced() throws {
        try withDirectory { url in
            let file = url.appendingPathComponent("profiles.json")
            let original = Data("{not JSON".utf8)
            try original.write(to: file)
            let store = LocalProfileStore(directory: url, settings: .init(), name: "Local")
            XCTAssertTrue(store.failed)
            XCTAssertNil(store.active)
            XCTAssertFalse(store.update(LocalProfile(name: "Other", look: .init(.init()))))
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }

    func testOriginalProfileCannotBeRemovedWhileAnotherIsActive() throws {
        try withDirectory { url in
            let store = LocalProfileStore(directory: url, settings: .init(), name: "Original")
            let original = try XCTUnwrap(store.active)
            let other = LocalProfile(name: "Jade", look: .init(AppSettings()))
            XCTAssertTrue(store.update(other))
            XCTAssertTrue(store.choose(other.id))
            XCTAssertFalse(store.remove(original.id))
            let reopened = LocalProfileStore(directory: url, settings: .init(), name: "Unused")
            XCTAssertTrue(reopened.profiles.contains(original))
            XCTAssertEqual(reopened.active?.id, other.id)
        }
    }

    func testStartupPreferenceMigratesAndPersists() throws {
        let decoder = JSONDecoder()
        for (json, expected): (String, ProfileStartup) in [
            ("{}", .ask), (#"{"showProfilePicker":true}"#, .ask), (#"{"showProfilePicker":false}"#, .last)
        ] {
            XCTAssertEqual(try decoder.decode(AppSettings.self, from: Data(json.utf8)).profileStartup, expected)
        }
        let settings = AppSettings(profileStartup: .profile(UUID()))
        let encoded = try JSONEncoder().encode(settings)
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: encoded).profileStartup, settings.profileStartup)
    }

    func testStartupUsesPinnedProfileOrAsksWhenItIsDeleted() throws {
        try withDirectory { url in
            let settings = AppSettings()
            let store = LocalProfileStore(directory: url, settings: settings, name: "Alex")
            let alex = try XCTUnwrap(store.active)
            let sam = LocalProfile(name: "Sam", look: .init(settings))
            XCTAssertTrue(store.update(sam))
            XCTAssertFalse(store.needsStartupPicker(.profile(sam.id)))
            XCTAssertEqual(store.active?.id, sam.id)
            XCTAssertTrue(store.choose(alex.id))
            let reopened = LocalProfileStore(directory: url, settings: settings, name: "Unused")
            XCTAssertFalse(reopened.needsStartupPicker(.last))
            XCTAssertEqual(reopened.active?.id, alex.id)
            XCTAssertFalse(reopened.needsStartupPicker(.profile(sam.id)))
            XCTAssertEqual(reopened.active?.id, sam.id)
            XCTAssertTrue(reopened.remove(sam.id))
            XCTAssertTrue(reopened.needsStartupPicker(.profile(sam.id)))
            XCTAssertEqual(ProfileStartup.profile(sam.id).available(in: reopened.profiles), .ask)
            XCTAssertEqual(reopened.active?.id, alex.id)
        }
    }

    func testBackupIsCreatedOnceAndCanRestoreLegacyFiles() throws {
        try withDirectory { url in
            let settingsURL = url.appendingPathComponent("settings.json")
            let original = try JSONEncoder().encode(AppSettings())
            try original.write(to: settingsURL)
            let store = LocalProfileStore(directory: url, settings: .init(), name: "Original")
            XCTAssertNotNil(store.active)
            let backup = url.appendingPathComponent("profiles-migration-backup/settings.json")
            XCTAssertEqual(try Data(contentsOf: backup), original)
            let after = Data("new settings".utf8)
            try after.write(to: settingsURL)
            let again = LocalProfileStore(directory: url, settings: .init(), name: "Do not reimport")
            XCTAssertEqual(again.active, store.active)
            XCTAssertEqual(try Data(contentsOf: backup), original)
            try Data(contentsOf: backup).write(to: settingsURL, options: .atomic)
            XCTAssertEqual(try Data(contentsOf: settingsURL), original)
        }
    }

    func testHistoryMigratesWithoutChangingLegacyAndKeepsLaunchOwner() throws {
        try withDirectory { url in
            let file = url.appendingPathComponent("play-sessions.json")
            let game = UUID(), second = UUID(), profile = UUID()
            var now = Date(timeIntervalSinceReferenceDate: 900)
            let legacy = PlaySession(gameID: game, titleID: "old", bundleID: nil, startedAt: now,
                                     endedAt: now + 70, lastHeartbeatAt: now + 70)
            let data = try JSONEncoder().encode([legacy])
            try data.write(to: file)
            now += 70
            let store = PlaySessionStore(fileURL: file, now: { now })
            XCTAssertEqual(try Data(contentsOf: file), data)
            XCTAssertEqual(store.totalDuration(for: game), 70)
            store.expectStart(gameID: second)
            store.profileID = profile
            XCTAssertNil(store.lastPlayed(for: game))
            XCTAssertTrue(store.start(gameID: second, sourceID: "launch"))
            now += 40
            XCTAssertTrue(store.end(gameID: second).isEmpty)
            XCTAssertEqual(store.totalDuration(for: second), 0)
            XCTAssertTrue(store.start(gameID: game, sourceID: "scoped"))
            now += 20
            XCTAssertEqual(store.end(gameID: game).first?.profileID, profile)
            let reopened = PlaySessionStore(fileURL: file)
            XCTAssertEqual(reopened.totalDuration(for: second), 40)
            XCTAssertEqual(reopened.totalDuration(for: game), 70)
            reopened.profileID = profile
            XCTAssertEqual(reopened.totalDuration(for: game), 20)
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
    }
}
