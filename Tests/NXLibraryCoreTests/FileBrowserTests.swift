import Foundation
import XCTest
@testable import NXLibraryCore

final class FileBrowserTests: XCTestCase {
    func testPlacesAndParentDoNotEnterProtectedFolders() {
        let home = URL(fileURLWithPath: "/synthetic/home", isDirectory: true)
        let disk = URL(fileURLWithPath: "/Volumes/Test", isDirectory: true)
        let recent = home.appendingPathComponent("Recent", isDirectory: true)
        XCTAssertEqual(FileBrowser.places(home: home, homeChildren: ["Games", "Desktop"], disks: [disk],
                                          recent: [recent, disk]).map(\.kind), [.home, .games, .desktop, .disk, .recent])
        XCTAssertNil(FileBrowser.parent(of: home, home: home))
        XCTAssertEqual(FileBrowser.parent(of: recent, home: home)?.path, home.path)
        XCTAssertNil(FileBrowser.parent(of: URL(fileURLWithPath: "/"), home: home))
    }

    func testMetadataFiltersOrderingHiddenLinksAndRemovedDisk() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        for folder in ["Folder", ".Hidden", "Not a folder.app"] {
            try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: false)
        }
        for file in ["Game 10.nsp", "Game 2.XCZ", "Only.nup", "prod.keys", "Other.keys", "Notes.txt", "._Fake.nsp"] {
            try Data([0]).write(to: root.appendingPathComponent(file))
        }
        let loop = root.appendingPathComponent("Loop")
        try fm.createSymbolicLink(at: loop, withDestinationURL: root)
        try fm.createSymbolicLink(at: root.appendingPathComponent("Link.nsp"), withDestinationURL: root.appendingPathComponent("Game 10.nsp"))
        let entries = try await FileBrowser.list(root, choice: .gameFiles(allowFolder: false))
        XCTAssertEqual(FileBrowser.visible(entries, query: "", showHidden: false).map(\.name),
                       ["Folder", "Game 2.XCZ", "Game 10.nsp", "Only.nup"])
        XCTAssertEqual(FileBrowser.visible(entries, query: "hidden", showHidden: true).map(\.name), [".Hidden"])
        XCTAssertEqual(entries.first { $0.name == "Only.nup" }?.size, 1)
        let keys = try await FileBrowser.list(root, choice: .keys)
        XCTAssertEqual(keys.filter { !$0.isFolder }.map(\.name), ["prod.keys"])
        await assertFailure(.link, at: loop)
        await assertFailure(.unavailable, at: root.appendingPathComponent("Removed"))
        let denied = root.appendingPathComponent("Denied")
        try fm.createDirectory(at: denied, withIntermediateDirectories: false, attributes: [.posixPermissions: 0])
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path) }
        await assertFailure(.denied, at: denied)
    }

    func testLargeListing() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        for number in 0..<2_000 {
            try Data().write(to: root.appendingPathComponent("Game \(number).nsp"))
        }
        let entries = try await FileBrowser.list(root, choice: .gameFiles(allowFolder: true))
        XCTAssertEqual(entries.count, 2_000)
        XCTAssertEqual(entries.last?.name, "Game 1999.nsp")
    }

    private func assertFailure(_ expected: FileBrowser.Failure, at url: URL,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await FileBrowser.list(url, choice: .folder)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? FileBrowser.Failure, expected, file: file, line: line)
        }
    }
}
