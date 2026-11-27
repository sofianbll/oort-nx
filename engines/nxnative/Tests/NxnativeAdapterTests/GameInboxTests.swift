import Foundation
import XCTest
@testable import NxnativeAdapter

final class GameInboxTests: XCTestCase {
    private let title: UInt64 = 0x0100F43008C44000

    private func fixture(_ test: (URL, URL) throws -> Void) throws {
        let path = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(path) }
        let folder = URL(fileURLWithPath: String(cString: path), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        try test(folder, folder.appendingPathComponent("Games", isDirectory: true))
    }

    func testNamesAndAmbiguities() throws {
        try fixture { folder, root in
            let urls = try ["base.xcz", "patch.nsp", "dlc.nsz", "merged.xci", "unknown.nsp"].map {
                let url = folder.appendingPathComponent($0)
                try Data([1]).write(to: url)
                return url
            }
            let base = PackageContent(kind: .base, titleId: title, version: 0)
            let patch = PackageContent(kind: .update, titleId: title + 0x800, version: 131072)
            let dlc = PackageContent(kind: .dlc, titleId: title + 0x1001, version: 7)
            let rows = GameInbox.plan(inputs: GameInbox.inputs(urls), readings: [
                urls[0]: .contents([base]), urls[1]: .contents([patch]), urls[2]: .contents([dlc]),
                urls[3]: .contents([base, patch])
            ], root: root) { $0 == dlc.titleId ? "Méga DLC" : "Pokémon: Z-A" }
            XCTAssertEqual(rows.compactMap { $0.destination?.lastPathComponent }, [
                "Pokemon - Z-A [0100F43008C44000] [v0].xcz",
                "Pokemon - Z-A [0100F43008C44800] [v131072].nsp",
                "Pokemon - Z-A - Mega DLC [0100F43008C45001].nsz"
            ])
            XCTAssertEqual(Set(rows.compactMap { $0.destination?.deletingLastPathComponent().lastPathComponent }),
                           ["Pokemon - Z-A [0100F43008C44000]"])
            XCTAssertTrue(rows.suffix(2).allSatisfy { $0.issue != nil })
        }
    }

    func testMissingKeysBlockIdentificationOnlyForSupportedInputs() throws {
        try fixture { folder, root in
            let urls = try ["received.nsp", "notes.txt"].map {
                let url = folder.appendingPathComponent($0)
                try Data([1]).write(to: url)
                return url
            }
            let inputs = GameInbox.inputs(urls)
            let blocked = GameInbox.plan(inputs: inputs, readings: nil, root: root) { _ in nil }
            XCTAssertEqual(blocked.map(\.needsKeys), [true, false])
            XCTAssertEqual(blocked.map(\.issue), ["Keys missing: import them to identify this file", "Not a supported incoming file."])
            XCTAssertEqual(blocked.compactMap(\.destination), [])
            let read = GameInbox.plan(inputs: inputs, readings: [:], root: root) { _ in nil }
            XCTAssertEqual(read.first?.issue, "No single verified title, kind and version.")
        }
    }

    func testVerifiedCopyDuplicateAndCollision() throws {
        try fixture { folder, root in
            let source = folder.appendingPathComponent("received.nsp")
            let trash = folder.appendingPathComponent("Trash")
            let bytes = Data([1, 2, 3])
            try bytes.write(to: source)
            func plan() throws -> GameInbox.Entry {
                try XCTUnwrap(GameInbox.plan(inputs: GameInbox.inputs([source]), readings: [
                    source: .contents([.init(kind: .base, titleId: title, version: 0)])
                ], root: root) { _ in "Fixture" }.first)
            }
            let entry = try plan()
            let destination = try XCTUnwrap(entry.destination)
            XCTAssertThrowsError(try GameInbox.store(entry, root: root, discover: { _, _ in false },
                                                      trash: { _ in XCTFail("Undiscovered file sent to Trash") }))
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
            XCTAssertThrowsError(try GameInbox.store(entry, root: root, discover: { _, _ in true },
                                                      trash: { _ in XCTFail("Unconfirmed duplicate") }))
            let duplicate = try plan()
            XCTAssertTrue(duplicate.duplicate)
            try GameInbox.store(duplicate, root: root, discover: { url, row in
                row.titleId == self.title && url == destination
            }, trash: { try FileManager.default.moveItem(at: $0, to: trash) })
            XCTAssertEqual(try Data(contentsOf: trash), bytes)
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
            try Data([3, 2, 1]).write(to: source)
            XCTAssertNil(try plan().destination)
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
        }
    }

    func testInterruptionAndChangedSourceKeepOriginal() throws {
        try fixture { folder, root in
            let source = folder.appendingPathComponent("received.nsp")
            let bytes = Data([1, 2, 3])
            try bytes.write(to: source)
            let entry = try XCTUnwrap(GameInbox.plan(inputs: GameInbox.inputs([source]), readings: [
                source: .contents([.init(kind: .base, titleId: title, version: 0)])
            ], root: root) { _ in "Fixture" }.first)
            let destination = try XCTUnwrap(entry.destination)
            XCTAssertThrowsError(try GameInbox.store(entry, root: root, discover: { _, _ in
                XCTFail("Incomplete copy published"); return false
            }, trash: { _ in XCTFail("Original sent to Trash") }, copy: { _, candidate in
                try Data([1]).write(to: candidate)
                throw CancellationError()
            }))
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path), [])
            try Data([1, 2, 3, 4]).write(to: source)
            XCTAssertThrowsError(try GameInbox.store(entry, root: root, discover: { _, _ in false }))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testFreshCopyDiscoversBeforeTrashAndRefusesLinks() throws {
        try fixture { folder, root in
            let source = folder.appendingPathComponent("received.nsp")
            let link = folder.appendingPathComponent("link.nsp")
            let trash = folder.appendingPathComponent("Trash")
            let bytes = Data([1, 2, 3])
            try bytes.write(to: source)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            let content = PackageContent(kind: .base, titleId: title, version: 0)
            let inputs = GameInbox.inputs(try GameInbox.files(in: folder))
            XCTAssertEqual(inputs.filter(\.canRead).map(\.url), [source])
            let rows = GameInbox.plan(inputs: inputs, readings: [source: .contents([content])], root: root) { _ in "Fixture" }
            XCTAssertNotNil(rows.first { $0.source == link }?.issue)
            let entry = try XCTUnwrap(rows.first { $0.source == source })
            XCTAssertFalse(entry.duplicate)
            var discovered = false
            try GameInbox.store(entry, root: root, discover: { file, identified in
                XCTAssertEqual(try Data(contentsOf: source), bytes)
                XCTAssertEqual(try Data(contentsOf: file), bytes)
                discovered = identified == content
                return discovered
            }, trash: {
                XCTAssertTrue(discovered)
                try FileManager.default.moveItem(at: $0, to: trash)
            })
            XCTAssertEqual(try Data(contentsOf: trash), bytes)
            XCTAssertThrowsError(try Data(contentsOf: source))
        }
    }
}
