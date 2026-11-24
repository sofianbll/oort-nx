import Foundation
import XCTest
@testable import NXLibraryCore

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

        XCTAssertFalse(try DowngradeCheckpoint.prepare(in: root, preferences: preferences))
        XCTAssertFalse(try DowngradeCheckpoint.prepare(in: root, preferences: preferences))
        let contents = try Data(contentsOf: checkpoint)
        let manifest = try plist(contents)
        let files = try XCTUnwrap(manifest["files"] as? [String: [String: Data]])
        XCTAssertEqual(files.keys.sorted(), ["artwork-picks/FIXTURE/square.png", "settings.json"])
        XCTAssertEqual(files["settings.json"]?["data"], Data("old settings".utf8))
        let preferenceItem = try XCTUnwrap(manifest["preferences"] as? [String: Data])
        let scoped = try plist(XCTUnwrap(preferenceItem["data"]))
        XCTAssertEqual(scoped as? [String: String], ["NXLibrary_CloudStorage": "fixture:Library"])
        XCTAssertEqual(try fm.attributesOfItem(atPath: checkpoint.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertTrue(try DowngradeCheckpoint.prepare(in: root, acceptingWarning: true, preferences: preferences))

        try write("new settings", to: "settings.json")
        XCTAssertTrue(try DowngradeCheckpoint.prepare(in: root, preferences: { [:] }))
        XCTAssertEqual(try Data(contentsOf: checkpoint), contents)
    }

    func testRotatesOnlyWhenGenerationChangesAndKeepsOnePreviousCopy() throws {
        let previous = checkpoint.deletingLastPathComponent().appendingPathComponent("previous.plist")
        for generation in 1...3 {
            try write("generation \(generation)", to: "settings.json")
            XCTAssertFalse(try DowngradeCheckpoint.prepare(in: root, generation: generation, preferences: { [:] }))
            XCTAssertTrue(try DowngradeCheckpoint.prepare(in: root, generation: generation, acceptingWarning: true, preferences: { [:] }))
            XCTAssertEqual(try plist(Data(contentsOf: checkpoint))["generation"] as? Int, generation)
            if generation > 1 {
                XCTAssertEqual(try plist(Data(contentsOf: previous))["generation"] as? Int, generation - 1)
            }
        }
        XCTAssertThrowsError(try DowngradeCheckpoint.prepare(in: root, generation: 2, preferences: { [:] }))
    }

    func testRefusesLinkAndSizeLimitWithoutPublishingOrChangingOriginal() throws {
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
        XCTAssertThrowsError(try DowngradeCheckpoint.prepare(in: root, preferences: { [:] }))
        XCTAssertFalse(fm.fileExists(atPath: checkpoint.path))
        XCTAssertEqual(try fm.attributesOfItem(atPath: live.path)[.size] as? Int, 128 * 1024 * 1024 + 1)
    }

    func testFreshProfileDoesNotPromptButCorruptCheckpointBlocksLaunch() throws {
        XCTAssertTrue(try DowngradeCheckpoint.prepare(in: root, preferences: { [:] }))
        try Data("incomplete snapshot".utf8).write(to: checkpoint)
        try write("new settings", to: "settings.json")
        XCTAssertThrowsError(try DowngradeCheckpoint.prepare(in: root, acceptingWarning: true, preferences: { [:] }))
        XCTAssertEqual(try Data(contentsOf: checkpoint), Data("incomplete snapshot".utf8))
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
