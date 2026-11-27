import Foundation
import XCTest
@testable import NXLibraryCore

final class MacShortcutTests: XCTestCase {
    func testChosenAppIsLocalAndAliasDoesNotCreateAnotherTile() throws {
        try withFixture { folder, app, binary in
            let store = CatalogStore(directory: folder.appendingPathComponent("catalog"), kinds: .base, legacy: nil)
            let repo = CatalogRepository(store: store)
            let initial = try repo.addMacShortcut(at: app)
            let game = try XCTUnwrap(initial.games.first)
            let alias = folder.appendingPathComponent("Alias.app")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: app)
            XCTAssertEqual(try repo.addMacShortcut(at: alias), initial)
            XCTAssertEqual(try CatalogRepository(store: store).load(), initial)
            XCTAssertEqual(game.macShortcut?.url.standardizedFileURL.path, app.standardizedFileURL.path)
            XCTAssertEqual(game.macShortcut?.bundleIdentifier, "test.oort.shortcut")
            XCTAssertEqual(game.name, "Paper Racer")
            XCTAssertEqual(initial.source(.macShortcut)?.isEnabled, true)
            XCTAssertEqual(CatalogLibraryProjection.visible(games: initial.games, sources: initial.sources).map(\.id), [game.id])
            XCTAssertEqual(PlayTarget(game: game, sourceEnabled: true).installation?.applicationURL, game.macShortcut?.url)
            let sameIDOtherCopy = try makeApp(in: folder, name: "Other.app", binary: binary)
            XCTAssertEqual(try repo.addMacShortcut(at: sameIDOtherCopy).games.count, 2)
        }
    }

    func testMovedOrReplacedAppIsNeverLaunchedUntilExplicitRelinkToSameIdentity() throws {
        try withFixture { folder, app, binary in
            let repo = CatalogRepository(store: .init(directory: folder.appendingPathComponent("catalog"), kinds: .base, legacy: nil))
            let game = try XCTUnwrap(repo.addMacShortcut(at: app).games.first)
            let shortcut = try XCTUnwrap(game.macShortcut)
            let moved = folder.appendingPathComponent("Moved.app", isDirectory: true)
            try FileManager.default.moveItem(at: app, to: moved)
            XCTAssertNil(shortcut.verifiedURL())
            try FileManager.default.createSymbolicLink(at: app, withDestinationURL: moved)
            XCTAssertNil(shortcut.verifiedURL(), "The old path must not silently follow a new symlink")
            try FileManager.default.removeItem(at: app)
            let replacement = try makeApp(in: folder, name: app.lastPathComponent, binary: binary, bundleID: "test.oort.other")
            XCTAssertNil(shortcut.verifiedURL(), "A different bundle at the old path must never be used")
            XCTAssertThrowsError(try repo.relinkMacShortcut(id: game.id, at: replacement))
            XCTAssertEqual(try repo.load().games, [game])
            let relinked = try XCTUnwrap(repo.relinkMacShortcut(id: game.id, at: moved).games.first)
            XCTAssertEqual(relinked.id, game.id)
            XCTAssertEqual(relinked.personalizationReference, game.personalizationReference)
            XCTAssertEqual(relinked.macShortcut?.verifiedURL()?.standardizedFileURL.path, moved.standardizedFileURL.path)
            let executable = moved.appendingPathComponent("Contents/MacOS/Fixture")
            let bytes = try Data(contentsOf: executable)
            XCTAssertTrue(try repo.removeMacShortcut(id: game.id).games.isEmpty)
            XCTAssertEqual(try Data(contentsOf: executable), bytes, "Removing the tile never touches the chosen bundle")
            let empty = folder.appendingPathComponent("Empty.app", isDirectory: true)
            try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
            XCTAssertThrowsError(try repo.addMacShortcut(at: empty))
        }
    }

    private func withFixture(_ check: (URL, URL, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("oort-mac-shortcut-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("fixture.c")
        try Data("int main(void) { return 0; }\n".utf8).write(to: source)
        let binary = folder.appendingPathComponent("Fixture")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = [source.path, "-o", binary.path]
        try compiler.run()
        compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
        try check(folder, makeApp(in: folder, name: "Fixture.app", binary: binary), binary)
    }

    private func makeApp(in folder: URL, name: String, binary: URL, bundleID: String = "test.oort.shortcut") throws -> URL {
        let app = folder.appendingPathComponent(name, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let executableFolder = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executableFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: binary, to: executableFolder.appendingPathComponent("Fixture"))
        let info = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": "Fixture",
                    "CFBundlePackageType": "APPL", "CFBundleDisplayName": "Paper Racer"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }
}
