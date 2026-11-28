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

    func testATestProcessNeverUsesTheUsersTrash() throws {
        let own = try XCTUnwrap(OortSystem.currentTrash.root, "a test process gets a Trash of its own")
        XCTAssertFalse(own.path.hasSuffix("/.Trash"))
        let file = try write("x", "thrown-\(UUID().uuidString)")
        try OortSystem.trash(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: own.appendingPathComponent(file.lastPathComponent).path))
        XCTAssertEqual(try OortSystem.trashFolder(for: root).standardizedFileURL, own.standardizedFileURL)
    }

    func testAFolderTrashKeepsBothItemsOfTheSameName() throws {
        let trash = OortSystem.Trash.folder(at: root.appendingPathComponent("bin"))
        for text in ["first", "second"] { try trash.put(try write(text, "same")) }
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("bin/same"), encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("bin/same 2"), encoding: .utf8), "second")
    }

    func testTheSystemTrashIsRefusedWhereTheSystemHasNone() throws {
        // Never calls the user's real Trash: on a system that has one, this test has nothing to check.
        try XCTSkipIf(OortSystem.hasTrash, "this system has a Trash")
        let file = try write("x", "kept")
        XCTAssertThrowsError(try OortSystem.Trash.system.put(file)) {
            XCTAssertEqual($0 as? OortSystem.Unsupported, .init(operation: "trash"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
