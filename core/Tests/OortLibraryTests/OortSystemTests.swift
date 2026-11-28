import XCTest
@testable import OortLibrary

/// The system folder answers the same on every system, or refuses where the system has no equivalent.
final class OortSystemTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("oort-system-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func write(_ text: String, _ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testRenameNeverReplacesAnExistingFileOrFolder() throws {
        let source = try write("new", "source"), destination = try write("old", "destination")
        XCTAssertEqual(OortSystem.rename(source.path, destination.path, .noReplace), -1)
        XCTAssertEqual(errno, EEXIST)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new")
        let folder = root.appendingPathComponent("folder"), taken = root.appendingPathComponent("taken")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: false)
        XCTAssertEqual(OortSystem.rename(folder.path, taken.path, .noReplace), -1)
        XCTAssertEqual(errno, EEXIST)
    }

    func testRenameMovesWhenNothingIsThere() throws {
        let source = try write("new", "source"), destination = root.appendingPathComponent("moved")
        XCTAssertEqual(OortSystem.rename(source.path, destination.path, .noReplace), 0)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testSwapExchangesTwoFolders() throws {
        let one = root.appendingPathComponent("one"), two = root.appendingPathComponent("two")
        for (folder, text) in [(one, "1"), (two, "2")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data(text.utf8).write(to: folder.appendingPathComponent("mark"))
        }
        XCTAssertEqual(OortSystem.rename(one.path, two.path, .swap), 0)
        XCTAssertEqual(try String(contentsOf: one.appendingPathComponent("mark"), encoding: .utf8), "2")
        XCTAssertEqual(try String(contentsOf: two.appendingPathComponent("mark"), encoding: .utf8), "1")
    }

    func testFileTimesAreTheOnesFoundationReads() throws {
        let file = try write("x", "timed")
        let when = Date(timeIntervalSince1970: 1_700_000_000.25)
        try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: file.path)
        var status = stat()
        XCTAssertEqual(lstat(file.path, &status), 0)
        let modified = OortSystem.modified(status)
        XCTAssertEqual(modified.seconds, 1_700_000_000)
        XCTAssertEqual(Double(modified.nanoseconds) / 1e9, 0.25, accuracy: 0.001)
        XCTAssertGreaterThan(OortSystem.changed(status).seconds, 0)
    }

    func testDirectoryEntryNamesKeepTheirBytes() throws {
        _ = try write("x", "é ü.txt")
        let directory = try XCTUnwrap(opendir(root.path))
        defer { closedir(directory) }
        var names: [String] = []
        while let entry = readdir(directory) {
            let length = OortSystem.nameLength(entry)
            names.append(withUnsafeBytes(of: &entry.pointee.d_name) { String(decoding: $0.prefix(length), as: UTF8.self) })
        }
        XCTAssertTrue(names.contains("é ü.txt"), "\(names)")
    }

    func testRegularFileBytesSkipHiddenEntriesAndNeverFollowALink() throws {
        let folder = root.appendingPathComponent("game")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".cache"), withIntermediateDirectories: true)
        try Data(count: 1000).write(to: folder.appendingPathComponent("a.bin"))
        try Data(count: 24).write(to: folder.appendingPathComponent("b.bin"))
        try Data(count: 200).write(to: folder.appendingPathComponent(".hidden"))
        try Data(count: 1000).write(to: folder.appendingPathComponent(".cache/c.bin"))
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data(count: 5000).write(to: outside.appendingPathComponent("big"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertEqual(OortSystem.regularFileBytes(at: folder.path, includingHidden: false), 1024)
        XCTAssertEqual(OortSystem.regularFileBytes(at: folder.path, includingHidden: true), 2224)
        XCTAssertEqual(OortSystem.regularFileBytes(at: root.appendingPathComponent("none").path, includingHidden: true), 0)
    }

    func testTrashIsRefusedWhereTheSystemHasNone() throws {
        // Never touches the user's real Trash: on a system with one, the callers' own tests inject a discard.
        try XCTSkipIf(OortSystem.hasTrash, "this system has a Trash")
        let file = try write("x", "kept")
        XCTAssertThrowsError(try OortSystem.trash(file)) { XCTAssertEqual($0 as? OortSystem.Unsupported, .init(operation: "trash")) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testPoolRunsAndRethrows() {
        XCTAssertEqual(OortSystem.withPool { 7 }, 7)
        struct Failure: Error {}
        XCTAssertThrowsError(try OortSystem.withPool { throw Failure() })
    }

    func testFreeSpaceHasAPlainFigure() throws {
        let space = OortSystem.freeSpace(at: root)
        XCTAssertGreaterThan(try XCTUnwrap(space.plain), 0)
    }

    func testCloneEitherCopiesTheBytesOrAsksForACopy() throws {
        let source = try write("same bytes", "original")
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let copy = root.appendingPathComponent("clone")
        if OortSystem.clone(handle.fileDescriptor, to: copy.path) {
            XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "same bytes")
        } else {
            XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        }
    }

    func testPreferencesOfAPrivateDomainSynchronize() {
        let domain = "oort.tests.system.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.set(1, forKey: "k")
        XCTAssertTrue(OortSystem.synchronizePreferences(domain: domain))
        defaults.removePersistentDomain(forName: domain)
    }
}
