import Foundation
import Darwin
import XCTest
@testable import OortLibrary

final class DowngradeCheckpointTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    private var checkpoint: URL { root.appendingPathComponent("DowngradeProtection/checkpoint.plist") }

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws { try fm.removeItem(at: root) }

    func testFirstCopyIsPrivateVerifiedAndNeverRefreshedByNormalLaunch() throws {
        try write("old settings", to: "settings.json")
        try write("old art", to: "artwork-picks/FIXTURE/square.png")
        try write("not artwork", to: "artwork-picks/FIXTURE/fixture.nsp")
        try write("not a preference", to: "keys/synthetic")
        let preferences = { ["NXLibrary_CloudStorage": "fixture:Library", "synthetic-secret": "do not copy"] }

        XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, preferences: preferences), .warning([]))
        XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, preferences: preferences), .warning([]))
        let contents = try Data(contentsOf: checkpoint)
        let manifest = try plist(contents)
        let files = try XCTUnwrap(manifest["files"] as? [String: [String: Data]])
        XCTAssertEqual(files.keys.sorted(), ["artwork-picks/FIXTURE/square.png", "settings.json"])
        XCTAssertEqual(files["settings.json"]?["data"], Data("old settings".utf8))
        let preferenceItem = try XCTUnwrap(manifest["preferences"] as? [String: Data])
        let scoped = try plist(XCTUnwrap(preferenceItem["data"]))
        XCTAssertEqual(scoped as? [String: String], ["NXLibrary_CloudStorage": "fixture:Library"])
        XCTAssertEqual(try fm.attributesOfItem(atPath: checkpoint.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, acceptingWarning: true, preferences: preferences), .ready)

        try write("new settings", to: "settings.json")
        XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, preferences: { [:] }), .ready)
        XCTAssertEqual(try Data(contentsOf: checkpoint), contents)
    }

    func testRotatesOnlyWhenGenerationChangesAndKeepsOnePreviousCopy() throws {
        let previous = checkpoint.deletingLastPathComponent().appendingPathComponent("previous.plist")
        for generation in 1...3 {
            try write("generation \(generation)", to: "settings.json")
            XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, generation: generation, preferences: { [:] }), .warning([]))
            XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, generation: generation, acceptingWarning: true, preferences: { [:] }), .ready)
            XCTAssertEqual(try plist(Data(contentsOf: checkpoint))["generation"] as? Int, generation)
            if generation > 1 {
                XCTAssertEqual(try plist(Data(contentsOf: previous))["generation"] as? Int, generation - 1)
            }
        }
        XCTAssertThrowsError(try DowngradeCheckpoint.prepare(in: root, generation: 2, preferences: { [:] }))
    }

    func testFailedRotationLeavesBothVerifiedCopiesAtTheirOriginalPaths() throws {
        try write("one", to: "settings.json")
        _ = try DowngradeCheckpoint.prepare(in: root, generation: 1, preferences: { [:] })
        try write("two", to: "settings.json")
        _ = try DowngradeCheckpoint.prepare(in: root, generation: 2, preferences: { [:] })
        let previous = checkpoint.deletingLastPathComponent().appendingPathComponent("previous.plist")
        let first = try Data(contentsOf: previous)
        let second = try Data(contentsOf: checkpoint)
        try write("three", to: "settings.json")
        XCTAssertThrowsError(try DowngradeCheckpoint.prepare(in: root, generation: 3, replaceCheckpoint: { _, _ in
            throw POSIXError(.ENOSPC)
        }, preferences: { [:] }))
        XCTAssertEqual(try Data(contentsOf: checkpoint), second)
        XCTAssertEqual(try Data(contentsOf: previous), first)
        XCTAssertThrowsError(try DowngradeCheckpoint.prepare(in: root, generation: 3, replaceCheckpoint: { source, destination in
            try DowngradeCheckpoint.replace(source, destination)
            throw POSIXError(.EIO)
        }, preferences: { [:] }))
        XCTAssertEqual(try Data(contentsOf: previous), first)
        _ = try DowngradeCheckpoint.prepare(in: root, generation: 3, preferences: { [:] })
        XCTAssertEqual(try Data(contentsOf: previous), second)
        XCTAssertEqual(try plist(Data(contentsOf: checkpoint))["generation"] as? Int, 3)
    }

    func testOptionalFoldersIgnoreUnrelatedAndSpecialEntriesAndKeepSoundArchives() throws {
        try write("unrelated", to: "artwork-picks/notes.txt")
        try write("art", to: "artwork-picks/TEST/hero.jpg")
        try write("source", to: "unlisted")
        try fm.createSymbolicLink(at: root.appendingPathComponent("artwork-picks/linked-title"),
                                  withDestinationURL: root.appendingPathComponent("artwork-picks/TEST"))
        XCTAssertEqual(mkfifo(root.appendingPathComponent("artwork-picks/TEST/square.png").path, 0o600), 0)
        try write("sound", to: "SoundPacks/normal.oortsound/manifest.json")
        // Real ZIP container; these bytes stand for an imported archive, not unpacked members.
        let zip = Data([0x50, 0x4b, 0x05, 0x06] + [UInt8](repeating: 0, count: 18))
        try zip.write(to: root.appendingPathComponent("SoundPacks/archived.oortsound"))
        XCTAssertEqual(mkfifo(root.appendingPathComponent("SoundPacks/pipe.oortsound").path, 0o600), 0)
        try fm.createSymbolicLink(at: root.appendingPathComponent("SoundPacks/linked.oortsound"),
                                  withDestinationURL: root.appendingPathComponent("unlisted"))
        XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, preferences: { [:] }), .warning([]))
        let files = try XCTUnwrap(plist(Data(contentsOf: checkpoint))["files"] as? [String: [String: Data]])
        XCTAssertEqual(files.keys.sorted(), ["SoundPacks/archived.oortsound", "SoundPacks/normal.oortsound/manifest.json", "artwork-picks/TEST/hero.jpg"])
        XCTAssertEqual(files["SoundPacks/archived.oortsound"]?["data"], zip)
    }

    func testExistingCheckpointDirectoryIsMadePrivate() throws {
        let folder = checkpoint.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        _ = try DowngradeCheckpoint.prepare(in: root, preferences: { [:] })
        XCTAssertEqual(try fm.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int, 0o700)
    }

    func testRefusesLinkAndLeavesOversizedSettingsUntouched() throws {
        try write("sentinel", to: "excluded/sentinel")
        let live = root.appendingPathComponent("settings.json")
        try fm.createSymbolicLink(at: live, withDestinationURL: root.appendingPathComponent("excluded/sentinel"))
        XCTAssertThrowsError(try DowngradeCheckpoint.prepare(in: root, acceptingWarning: true, preferences: { [:] }))
        XCTAssertEqual(try Data(contentsOf: live), Data("sentinel".utf8))
        XCTAssertFalse(fm.fileExists(atPath: checkpoint.path))
        try fm.removeItem(at: live)
        try write("", to: "settings.json")
        let handle = try FileHandle(forWritingTo: live)
        try handle.truncate(atOffset: 128 * 1024 * 1024 + 1)
        try handle.close()
        try write("small sessions", to: "play-sessions.json")
        XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, preferences: { [:] }), .warning([.settings]))
        let files = try XCTUnwrap(plist(Data(contentsOf: checkpoint))["files"] as? [String: [String: Data]])
        XCTAssertEqual(files["play-sessions.json"]?["data"], Data("small sessions".utf8))
        XCTAssertNil(files["settings.json"])
        XCTAssertEqual(try fm.attributesOfItem(atPath: live.path)[.size] as? Int, 128 * 1024 * 1024 + 1)
    }

    func testFreshProfileDoesNotPromptAndCorruptCheckpointIsNotReplaced() throws {
        XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, preferences: { [:] }), .ready)
        try Data("incomplete snapshot".utf8).write(to: checkpoint)
        try write("new settings", to: "settings.json")
        XCTAssertThrowsError(try DowngradeCheckpoint.prepare(in: root, acceptingWarning: true, preferences: { [:] }))
        XCTAssertEqual(try Data(contentsOf: checkpoint), Data("incomplete snapshot".utf8))
    }

    func testOversizedArtworkKeepsTheEssentialFilesAndReportsOmission() throws {
        for name in ["play-sessions.json", "catalog.json", "settings.json", "profiles.json", "cloud-transfer-queue.json"] {
            try write(name, to: name)
        }
        let relative = "artwork-picks/FIXTURE/square.png"
        try write("", to: relative)
        let handle = try FileHandle(forWritingTo: root.appendingPathComponent(relative))
        try handle.truncate(atOffset: 128 * 1024 * 1024 + 1)
        try handle.close()
        let prefs = { ["NXLibrary_CloudLastKnownAvailability": Data([42])] }
        XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, preferences: prefs), .warning([.artwork]))
        let manifest = try plist(Data(contentsOf: checkpoint))
        let files = try XCTUnwrap(manifest["files"] as? [String: [String: Data]])
        XCTAssertNil(files[relative])
        XCTAssertEqual(manifest["omitted"] as? [String], ["artwork"])
        XCTAssertEqual(files.keys.sorted(), ["catalog.json", "cloud-transfer-queue.json", "play-sessions.json", "profiles.json", "settings.json"])
        let preference = try XCTUnwrap(manifest["preferences"] as? [String: Data])
        XCTAssertEqual(try plist(XCTUnwrap(preference["data"]))["NXLibrary_CloudLastKnownAvailability"] as? Data, Data([42]))
        XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, acceptingWarning: true, preferences: prefs), .ready)
        XCTAssertEqual(try DowngradeCheckpoint.prepare(in: root, preferences: prefs), .ready)
    }

    private func write(_ text: String, to name: String) throws {
        let file = root.appendingPathComponent(name)
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    private func plist(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }
}
