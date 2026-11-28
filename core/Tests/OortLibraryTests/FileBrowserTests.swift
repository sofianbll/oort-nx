import Foundation
import XCTest
@testable import OortLibrary

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
        if !fm.isReadableFile(atPath: denied.path) { await assertFailure(.denied, at: denied) }

        let protected = root.appendingPathComponent("Documents")
        try fm.createSymbolicLink(at: protected, withDestinationURL: loop)
        let homeEntries = try await FileBrowser.list(root, choice: .folder, home: root)
        XCTAssertTrue(homeEntries.contains { $0.name == "Documents" && $0.isFolder })
        await assertFailure(.link, at: protected)
    }

    func testPicturesAppsToolsAndFoldersOfFiles() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Real.app/Contents/MacOS")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        for file in ["cover.PNG", "photo.heic", "notes.txt", "tool"] { try Data([0]).write(to: root.appendingPathComponent(file)) }
        try fm.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: root.appendingPathComponent("tool"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("linkedFolder"), withDestinationURL: root.appendingPathComponent("Folder"))
        func names(_ choice: FileBrowser.Choice) async throws -> [String] {
            try await FileBrowser.list(root, choice: choice).filter { !$0.isFolder }.map(\.name)
        }
        var found = try await names(.images)
        XCTAssertEqual(found, ["cover.PNG", "photo.heic"])
        found = try await names(.files(["txt"], folder: true, multiple: true))
        XCTAssertEqual(found, ["notes.txt"])
        found = try await names(.apps)
        XCTAssertEqual(found, ["Real.app"])
        found = try await names(.tool)
        XCTAssertTrue(found.contains("tool") && found.contains("linked") && !found.contains("linkedFolder"))
        let package = URL(fileURLWithPath: "/Applications/Real.app", isDirectory: true)
        XCTAssertTrue(FileBrowser.Choice.apps.accepts(package))
        XCTAssertFalse(FileBrowser.Choice.images.accepts(package))
        XCTAssertFalse(FileBrowser.Choice.apps.allowsFolder)
        XCTAssertTrue(FileBrowser.Choice.files(["txt"], folder: true).allowsFolder)
        XCTAssertTrue(FileBrowser.Choice.files(["txt"], multiple: true).allowsMultiple)
        XCTAssertFalse(FileBrowser.Choice.images.allowsMultiple)
    }

    /// Every native window drops the controller: the app opens its own picker and its own questions everywhere.
    func testNoScreenOpensAMacFileWindowOrAlert() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("apps/mac/OortMac")
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "OortFilePicker.swift" }
        var native: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in ["NSOpenPanel(", "NSSavePanel(", "NSAlert(", ".fileImporter("] where text.contains(name) {
                native.append("\(file.lastPathComponent): \(name)")
            }
        }
        XCTAssertEqual(native, [])
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
