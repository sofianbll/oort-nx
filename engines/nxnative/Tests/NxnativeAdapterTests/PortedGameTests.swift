import XCTest
@testable import OortLibrary
@testable import ArcanePorting

final class PortedGameTests: XCTestCase {
    func testRecentBuildsUseLatestSuccessfulCompletionPerVisibleGame() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(20)
        let later = end.addingTimeInterval(40)
        let app = URL(fileURLWithPath: "/tmp/Game.app")
        let original = PortedGame(name: "G", url: app, platform: .macApp, sizeBytes: 1, modificationDate: later)
        var installed = original
        installed.lastBuild = .init(startedAt: start, endedAt: end, exitCode: 0)
        var ready = installed
        ready.id = UUID()
        ready.pendingInstall = .init(tempApp: app, finalApp: app,
                                     record: .init(startedAt: end, endedAt: later, exitCode: 0),
                                     toolchain: .init(verified: false))
        var failed = original
        failed.lastBuild = .init(startedAt: start, endedAt: later, exitCode: 1)
        var cancelled = original
        cancelled.lastBuild = .init(startedAt: start, endedAt: later, exitCode: 0, cancelled: true)
        var hidden = installed
        hidden.isHidden = true
        let builds = BuildRecord.recentGames(in: [installed, original, hidden, failed, ready, cancelled])
        XCTAssertEqual(builds.map(\.game.id), [ready.id, installed.id])
        XCTAssertEqual(builds.map(\.date), [later, end])
    }

    func testPlayableRequiresBuiltAppBundle() {
        var game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/Game.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date())
        XCTAssertFalse(game.isPlayableLocally)

        game.status = .built
        XCTAssertTrue(game.isPlayableLocally)

        game.status = .builtSourcesMissing
        XCTAssertTrue(game.isPlayableLocally)

        game.status = .appMissing
        XCTAssertFalse(game.isPlayableLocally)

        game.status = .built
        game.url = URL(fileURLWithPath: "/tmp/workspace")
        XCTAssertFalse(game.isPlayableLocally)
    }

    func testDeleteSafetyForSourceFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXDelete-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        defer { try? FileManager.default.removeItem(at: root) }

        var game = PortedGame(name: "G", url: root.appendingPathComponent("workspace"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date())
        game.status = .notBuilt
        XCTAssertFalse(game.canDeleteAppBundle())

        game.status = .built
        game.url = app
        XCTAssertTrue(game.canDeleteAppBundle())

        game.workspacePath = app.path
        XCTAssertFalse(game.canDeleteAppBundle())

        game.workspacePath = nil
        game.sources = [GameFileItem(url: app.appendingPathComponent("source.nsp"),
                                     kind: .base, titleId: "0100000000010000", sizeBytes: 1)]
        XCTAssertFalse(game.canDeleteAppBundle())
    }

    func testDecodesGameWithoutFlags() throws {
        let game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/G.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date())
        let data = try JSONEncoder().encode(game)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "isFavorite")
        json.removeValue(forKey: "isHidden")
        let old = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(PortedGame.self, from: old)
        XCTAssertFalse(decoded.isFavorite)
        XCTAssertFalse(decoded.isHidden)
        XCTAssertEqual(decoded.name, "G")
    }

    func testFlagsRoundTrip() throws {
        var game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/G.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date())
        game.isFavorite = true
        game.isHidden = true
        let decoded = try JSONDecoder().decode(PortedGame.self, from: JSONEncoder().encode(game))
        XCTAssertTrue(decoded.isFavorite)
        XCTAssertTrue(decoded.isHidden)
    }
}
