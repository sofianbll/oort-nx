import XCTest
import OortLibrary
@testable import NxnativeAdapter

/// The records the app really writes, through the app's own store and checks, with synthetic games.
final class LibraryPathsPortingTests: XCTestCase {
    private let fm = FileManager.default

    func testFirstCatalogFromCopiedLegacyLibraryRebasesPathsWithoutChangingOrigin() throws {
        for backupOnly in [false, true] {
            let home = fm.temporaryDirectory.appendingPathComponent("paths-legacy-\(UUID())", isDirectory: true)
            defer { try? fm.removeItem(at: home) }
            let profile = AppDataProfile(home: home, isDevelopment: false)
            let old = profile.legacySupportRoot, new = profile.supportRoot
            let relative = "workspaces/0100000000000001"
            let workspace = old.appendingPathComponent(relative, isDirectory: true)
            try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
            let source = workspace.appendingPathComponent("Fixture.nsp")
            try Data([42]).write(to: source)
            var game = PortedGame(name: "Fixture", url: workspace, platform: .macApp, sizeBytes: 1,
                                  modificationDate: Date(timeIntervalSince1970: 1), titleId: "0100000000000001")
            game.workspacePath = workspace.path
            game.sources = [.init(url: source, kind: .base, sizeBytes: 1)]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let bytes = try encoder.encode(LibraryFile(games: [game]))
            let name = backupOnly ? "library.json.bak" : "library.json"
            try bytes.write(to: old.appendingPathComponent(name))
            if backupOnly { try Data("{}".utf8).write(to: old.appendingPathComponent("settings.json")) }
            XCTAssertTrue(try LibraryMove(from: old, to: new).prepare(preferences: { [:] }, savePreferences: { _ in }))
            XCTAssertTrue(try LibraryPathRepair(from: old, to: new).prepare(checks: DevelopmentProfileImporter.portingChecks,
                                                                           preferences: { [:] }, savePreferences: { _ in }))
            XCTAssertFalse(fm.fileExists(atPath: new.appendingPathComponent("catalog.json").path))

            let store = CatalogStore(directory: new)
            let catalog = try store.loadForStartup(previousLibrary: old).catalog
            let converted = try XCTUnwrap(catalog.nxnativeGames.first)
            let copied = new.appendingPathComponent(relative, isDirectory: true)
            XCTAssertEqual(converted.url, copied)
            XCTAssertEqual(converted.workspacePath, copied.path)
            XCTAssertEqual(converted.sources.map(\.url), [copied.appendingPathComponent("Fixture.nsp")])
            XCTAssertEqual(catalog.legacyOrigin.kind, backupOnly ? .backup : .primary)
            XCTAssertEqual(try store.loadOrMigrate(), catalog)
            for root in [old, new] { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), bytes) }
        }
    }

    func testAnAlreadyCopiedCatalogLoadsWithItsPathsInTheNewFolder() async throws {
        let home = fm.temporaryDirectory.appendingPathComponent("paths-porting-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: home) }
        let profile = AppDataProfile(home: home, isDevelopment: false)
        let old = profile.legacySupportRoot, new = profile.supportRoot
        let ids = (1...4).map { String(format: "010000000000%04X", $0) }
        // No cache was ever made, and the last game has no workspace on disk either.
        for root in [old, new] {
            for id in ids.dropLast() { try fm.createDirectory(at: root.appendingPathComponent("workspaces/\(id)"), withIntermediateDirectories: true) }
        }
        let games = ids.map { id -> PortedGame in
            let workspace = old.appendingPathComponent("workspaces/\(id)", isDirectory: true)
            var game = PortedGame(name: "Synthetic \(id)", url: workspace, platform: .macApp, sizeBytes: 1,
                                  modificationDate: Date(timeIntervalSince1970: 1.25), titleId: id)
            game.workspacePath = workspace.path
            game.buildCachePath = workspace.appendingPathComponent("\(id)_build").path
            game.sources = [GameFileItem(url: workspace.appendingPathComponent("base.nsp"), kind: .base, sizeBytes: 1)]
            game.lastBuild = BuildRecord(logPath: old.appendingPathComponent("Logs/\(id).log").path, outputPath: "/Applications/Synthetic.app")
            return game
        }
        let store = CatalogStore(directory: new)
        var document = try store.loadOrMigrate()
        document.games = games.map(CatalogGame.init(nxnative:))
        document = try store.save(document, expectedRevision: document.revision)
        // Queues as the app writes them, naming a source in the old folder.
        let queue = ActivityQueueFile<BuildRequest>(file: new.appendingPathComponent("build-queue.json"))
        try await queue.saveDurably([BuildRequest(gameID: games[0].id, name: "Synthetic")])
        try Data(#"{"version":1,"ready":true,"files":1}"#.utf8).write(to: new.appendingPathComponent(".moved-library.json"))

        XCTAssertTrue(try LibraryPathRepair(from: old, to: new).prepare(checks: DevelopmentProfileImporter.portingChecks,
                                                                         preferences: { [:] }, savePreferences: { _ in XCTFail() }))

        let repaired = try store.loadOrMigrate()
        XCTAssertEqual(repaired.revision, document.revision)
        for (game, original) in zip(repaired.games.compactMap(\.nxnativeGame), games) {
            let workspace = new.appendingPathComponent("workspaces/\(original.titleId!)", isDirectory: true)
            var expected = original
            expected.url = workspace
            expected.workspacePath = workspace.path
            expected.buildCachePath = workspace.appendingPathComponent("\(original.titleId!)_build").path
            expected.sources[0].url = workspace.appendingPathComponent("base.nsp")
            // Logs stay in the old folder.
            XCTAssertEqual(game, expected)
        }
        XCTAssertEqual(repaired.games.count, 4)
        let waiting = await queue.load()
        XCTAssertEqual(waiting.count, 1)
    }
}
