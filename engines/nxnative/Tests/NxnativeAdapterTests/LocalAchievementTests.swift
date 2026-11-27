import Foundation
import XCTest
import NXLibraryCore
@testable import ArcanePorting

final class LocalAchievementTests: XCTestCase {
    func testBeforeAndAfterEveryThresholdWithSeparateProfiles() throws {
        let pack = try XCTUnwrap(LocalAchievementPack.linksAwakening)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("savedata0.bin")
        let second = root.appendingPathComponent("savedata1.bin")
        // An absolute suite path keeps Foundation's plist inside the fixture.
        let preferencesFile = root.appendingPathComponent("test-preferences")
        let suite = preferencesFile.path
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = LocalAchievementStore(defaults: defaults)
        let player = UUID(), other = UUID()
        let cases: [(Int, Int, [String])] = [
            (0, 3, []), (1, 4, ["shells-1", "hearts-4"]), (9, 11, []),
            (10, 12, ["shells-10", "hearts-12"]), (29, 12, []), (30, 12, ["shells-30"])
        ]
        XCTAssertTrue(pack.matches(titleID: "01006bb00c6f0000", gameVersion: "1.0.0"))
        XCTAssertFalse(pack.matches(titleID: "01006BB00C6F0800", gameVersion: "1.0.0"))
        XCTAssertFalse(pack.matches(titleID: pack.titleID, gameVersion: "1.1.0"))
        try fixture(shells: 0, hearts: 2).write(to: second)
        for (index, item) in cases.enumerated() {
            let (shells, hearts, expected) = item
            let original = fixture(shells: shells, hearts: hearts)
            try original.write(to: first)
            let before = try first.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let counts = try XCTUnwrap(LinksAwakeningAchievements.read(from: root))
            XCTAssertEqual(counts, [.seashells: shells, .heartPieces: hearts])
            XCTAssertEqual(store.record(counts, in: pack, profile: player, at: Date(timeIntervalSince1970: Double(index))),
                           expected)
            XCTAssertEqual(try Data(contentsOf: first), original)
            XCTAssertEqual(try first.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, before)
        }
        XCTAssertTrue(defaults.synchronize())
        XCTAssertTrue(FileManager.default.fileExists(atPath: preferencesFile.appendingPathExtension("plist").path))
        let reopened = LocalAchievementStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        let progress = try XCTUnwrap(reopened.progress(for: pack, profile: player))
        XCTAssertEqual(progress.counts[.seashells], 30)
        XCTAssertEqual(progress.unlockDates["shells-1"], Date(timeIntervalSince1970: 1))
        XCTAssertEqual(progress.unlockDates["shells-30"], Date(timeIntervalSince1970: 5))
        XCTAssertEqual(reopened.record([.seashells: 0], in: pack, profile: player, at: .now), [])
        XCTAssertTrue(pack.summary(reopened.progress(for: pack, profile: player), language: .french).isComplete)
        XCTAssertNil(reopened.progress(for: pack, profile: other))
        XCTAssertEqual(reopened.record([.seashells: 12], in: pack, profile: other, at: .now), ["shells-1", "shells-10"])
        let row = try XCTUnwrap(pack.summary(store.progress(for: pack, profile: other), language: .french)
            .rows(.locked).first { $0.id == "shells-30" })
        XCTAssertEqual(row.name, "Les secrets de l’île")
        XCTAssertEqual(row.progress?.current, 12)
        XCTAssertEqual(row.progress?.target, 30)
        XCTAssertNil(row.percent)
        var snapshot = GameOverlaySnapshot()
        snapshot.achievements = pack.summary(reopened.progress(for: pack, profile: other), language: .french)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(snapshot.encoded())) as? NSDictionary)
        XCTAssertEqual(json, ["achievements": ["total": 5, "unlocked": 2,
                                               "recent": ["Au bord de l’eau", "Chasse aux coquillages"]]] as NSDictionary)
    }

    func testRejectsUnknownVersionCorruptionAndUncommittedFiles() throws {
        XCTAssertNil(LinksAwakeningAchievements.decode(fixture(shells: 30, hearts: 12, version: 15)))
        let valid = fixture(shells: 30, hearts: 12)
        XCTAssertNil(LinksAwakeningAchievements.decode(valid.dropLast()))
        for offset in [0x80, 0x5548] {
            var corrupt = valid
            corrupt[offset] ^= 1
            XCTAssertNil(LinksAwakeningAchievements.decode(corrupt))
        }
        XCTAssertNil(LinksAwakeningAchievements.decode(fixture(shells: 51, hearts: 12)))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let pending = root.appendingPathComponent("savedata0.bin.pending")
        try valid.write(to: pending)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("savedata0.bin"), withDestinationURL: pending)
        XCTAssertNil(LinksAwakeningAchievements.read(from: root))
    }

    func testPrimaryReaderDoesNotGuessBetweenNXNativeUsers() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let location = try SaveLocation.defaultLocation(titleID: "01006BB00C6F0000", home: home)
        let primary = location.directory(.account)
        try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: true)
        try fixture(shells: 1, hearts: 4).write(to: primary.appendingPathComponent("savedata0.bin"))
        XCTAssertEqual(LinksAwakeningAchievements.readPrimary(from: location), [.seashells: 1, .heartPieces: 4])
        try Data("nxnative-users-1 03\n".utf8).write(to: location.directory(.users))
        XCTAssertNil(LinksAwakeningAchievements.readPrimary(from: location))
    }

    func testLaunchAccountReadsOnlyTheSelectedProfileSave() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let pack = try XCTUnwrap(LocalAchievementPack.linksAwakening)
        let legacy = try SaveLocation.defaultLocation(titleID: pack.titleID, home: home)
        let active = try SaveLocation.profileLocation(titleID: pack.titleID, profileID: UUID(), in: home)
        let env = try active.profileLaunchEnvironment(shared: legacy)
        for (location, shells) in [(legacy, 30), (active, 1)] {
            let account = location.directory(.account)
            try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
            try fixture(shells: shells, hearts: 4).write(to: account.appendingPathComponent("savedata0.bin"))
        }
        XCTAssertTrue(active.matchesLaunchAccount(env["DM_SAVE"]))
        XCTAssertFalse(legacy.matchesLaunchAccount(env["DM_SAVE"]))
        XCTAssertFalse(active.matchesLaunchAccount(legacy.directory(.account).path))
        XCTAssertFalse(active.matchesLaunchAccount(nil))
        XCTAssertEqual(LinksAwakeningAchievements.readPrimary(from: active), [.seashells: 1, .heartPieces: 4])
        XCTAssertEqual(LinksAwakeningAchievements.readPrimary(from: legacy), [.seashells: 30, .heartPieces: 4])
    }

    /// Synthetic; header and body CRCs use a table as a reference for the bitwise production reader.
    private func fixture(shells: Int, hearts: Int, version: UInt32 = 14) -> Data {
        var data = Data(repeating: 0, count: 0x5EE0)
        func write<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(offset..<offset + $0.count, with: $0) }
        }
        let polynomial: UInt32 = 0xEDB88320
        let table = (0..<256).map { value in
            (0..<8).reduce(UInt32(value)) { crc, _ in (crc >> 1) ^ (crc.isMultiple(of: 2) ? 0 : polynomial) }
        }
        func crc(_ range: Range<Int>) -> UInt32 {
            data[range].reduce(polynomial) { (value, byte) in (value >> 8) ^ table[Int(UInt8(truncatingIfNeeded: value) ^ byte)] }
        }
        write(version, at: 0)
        write((UInt64(1) << shells) - 1, at: 0x5548)
        write((UInt64(1) << hearts) - 1, at: 0x5550)
        write(crc(0..<0xE0), at: 4)
        write(crc(0xE0..<data.count), at: 0x5EC4)
        return data
    }
}
