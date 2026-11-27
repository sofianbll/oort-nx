import XCTest
@testable import NXLibraryCore

final class LibraryMoveTests: XCTestCase {
    private var home: URL!
    private var old: URL { home.appendingPathComponent("Library/Application Support/NXLibrary", isDirectory: true) }
    private var new: URL { home.appendingPathComponent("Library/Application Support/Oort NX", isDirectory: true) }
    private var saved: [String: Any] = [:]
    private var preferences: [String: Any] = [:]

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("move-\(UUID())", isDirectory: true)
        try put("{\"games\":[]}", "catalog.json")
        try put("{}", "settings.json")
        try put("picture", "artwork/one/cover.png")
        try put("synthetic", "keys/prod.keys")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: old.appendingPathComponent("keys/prod.keys").path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: old.appendingPathComponent("keys").path)
        try put("log", "Logs/today.log")
        try put("scratch", "Temp/x")
        try put("kept", "Folder named Temp/Logs/kept.txt")
        try FileManager.default.createSymbolicLink(atPath: old.appendingPathComponent("outside").path, withDestinationPath: "/usr/share")
        try FileManager.default.createSymbolicLink(atPath: old.appendingPathComponent("inside").path, withDestinationPath: old.appendingPathComponent("artwork").path)
        preferences = ["NXNative_SavedProdKeysPath": old.appendingPathComponent("keys/prod.keys").path, "NXLibrary_SetupCompleted": true,
                       "NXLibrary_UpdateRepository": "someone/else", "com.apple.trackpad": 1, "cloudSaves.folder": "/elsewhere"]
        saved = [:]
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    private func put(_ text: String, _ name: String) throws {
        let url = old.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func tree(_ root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for case let name as String in try XCTUnwrap(FileManager.default.enumerator(atPath: root.path)) {
            let url = root.appendingPathComponent(name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let mode = String((attributes[.posixPermissions] as? Int ?? 0), radix: 8)
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink?: result[name] = "-> " + (try FileManager.default.destinationOfSymbolicLink(atPath: url.path))
            case .typeDirectory?: result[name] = "d" + mode
            default: result[name] = mode + ":" + (try Data(contentsOf: url)).base64EncodedString()
            }
        }
        return result
    }

    private func move() throws -> Bool {
        try LibraryMove(from: old, to: new).prepare { preferences } savePreferences: { saved = $0 }
    }

    func testCopiesEverythingOnceAndNeverTouchesTheOriginal() throws {
        let before = try tree(old)
        XCTAssertTrue(try move())
        XCTAssertEqual(try tree(old), before)
        var expected = before.filter { name, _ in !["Temp", "Logs"].contains { name == $0 || name.hasPrefix($0 + "/") } }
        expected["inside"] = "-> " + new.appendingPathComponent("artwork").path
        var copied = try tree(new)
        XCTAssertNotNil(copied.removeValue(forKey: LibraryMove.marker))
        XCTAssertEqual(copied, expected)
        XCTAssertTrue(LibraryMove.moved(new))
        XCTAssertEqual(saved["NXNative_SavedProdKeysPath"] as? String, new.appendingPathComponent("keys/prod.keys").path)
        XCTAssertEqual(saved["NXLibrary_SetupCompleted"] as? Bool, true)
        XCTAssertEqual(saved["cloudSaves.folder"] as? String, "/elsewhere")
        XCTAssertNil(saved["NXLibrary_UpdateRepository"]); XCTAssertNil(saved["com.apple.trackpad"])
        // Later changes stay apart, and a second launch copies nothing.
        try Data("new".utf8).write(to: new.appendingPathComponent("settings.json"))
        try put("older app", "settings.json")
        saved = [:]
        XCTAssertFalse(try move())
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("settings.json"), encoding: .utf8), "new")
    }

    func testNothingToMove() throws {
        try FileManager.default.removeItem(at: old)
        XCTAssertFalse(try move())
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.path))
        try FileManager.default.createDirectory(at: old.appendingPathComponent("Logs"), withIntermediateDirectories: true)
        XCTAssertFalse(try move())
        XCTAssertFalse(LibraryMove.moved(new))
    }

    func testAnOortLibraryAlreadyInUseIsNeverReplaced() throws {
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: new.appendingPathComponent("catalog.json"))
        let before = try tree(new)
        XCTAssertFalse(try move())
        XCTAssertEqual(try tree(new), before)
    }

    func testAFolderWithoutALibraryIsKeptBeside() throws {
        try FileManager.default.createDirectory(at: new.appendingPathComponent("Logs"), withIntermediateDirectories: true)
        try Data("early".utf8).write(to: new.appendingPathComponent("Logs/early.log"))
        XCTAssertTrue(try move())
        XCTAssertTrue(LibraryMove.moved(new))
        let aside = try FileManager.default.contentsOfDirectory(atPath: new.deletingLastPathComponent().path).filter { $0.hasPrefix("Oort NX (before the move)") }
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(try String(contentsOf: new.deletingLastPathComponent().appendingPathComponent(aside[0] + "/Logs/early.log"), encoding: .utf8), "early")
    }

    func testPreferencesThatCannotBeSavedAreRetriedWithoutCopyingAgain() throws {
        struct Refused: Error {}
        XCTAssertThrowsError(try LibraryMove(from: old, to: new).prepare { preferences } savePreferences: { _ in throw Refused() })
        try put("changed since", "artwork/one/cover.png")
        XCTAssertTrue(try move())
        XCTAssertEqual(saved["NXLibrary_SetupCompleted"] as? Bool, true)
        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("artwork/one/cover.png"), encoding: .utf8), "picture")
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.appendingPathComponent(LibraryMove.preferenceFile).path))
    }

    func testAChangeDuringTheCopyPublishesNothing() throws {
        var reads = 0
        XCTAssertThrowsError(try LibraryMove(from: old, to: new).prepare {
            reads += 1
            if reads == 2 { return preferences.merging(["NXLibrary_SetupCompleted": false]) { $1 } }
            return preferences
        } savePreferences: { saved = $0 }) { XCTAssertEqual($0 as? LibraryMove.Failure, .sourceChanged) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: new.deletingLastPathComponent().path), ["NXLibrary"])
        XCTAssertTrue(saved.isEmpty)
    }

    func testUnsafeFilesAndFullVolumesLeaveNothingBehind() throws {
        XCTAssertEqual(mkfifo(old.appendingPathComponent("pipe").path, 0o600), 0)
        XCTAssertThrowsError(try move()) { XCTAssertEqual($0 as? LibraryMove.Failure, .unsafeFile) }
        XCTAssertEqual(unlink(old.appendingPathComponent("pipe").path), 0)
        final class Full: FileManager {
            override func copyItem(at srcURL: URL, to dstURL: URL) throws { throw CocoaError(.fileWriteOutOfSpace) }
        }
        XCTAssertThrowsError(try LibraryMove(from: old, to: new, fileManager: Full()).prepare { preferences } savePreferences: { saved = $0 })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: new.deletingLastPathComponent().path), ["NXLibrary"])
        XCTAssertTrue(try move())
    }

    func testARunningCopyOfTheOldLibraryStopsTheMove() throws {
        let lease = try DowngradeCheckpoint.ProfileLease(in: old)
        XCTAssertThrowsError(try move()) { XCTAssertEqual($0 as? LibraryMove.Failure, .sourceChanged) }
        withExtendedLifetime(lease) {}
    }

    func testTwoFirstLaunchesPublishOneLibrary() throws {
        let group = DispatchGroup(), lock = NSLock()
        var made = 0
        for _ in 0..<6 {
            DispatchQueue.global().async(group: group) { [old, new] in
                if (try? LibraryMove(from: old, to: new).prepare { [:] } savePreferences: { _ in }) == true { lock.withLock { made += 1 } }
            }
        }
        group.wait()
        XCTAssertEqual(made, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: new.deletingLastPathComponent().path).sorted(), ["NXLibrary", "Oort NX"])
    }
}
