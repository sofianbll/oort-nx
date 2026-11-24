import Foundation
import NXLibraryCore
import XCTest
@testable import ArcanePorting

final class InstalledEngineVersionTests: XCTestCase {
    func testBundleVersionAndGitAncestry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = folder.appendingPathComponent("Engine")
        let app = folder.appendingPathComponent("Fixture.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let runner = SystemCommandRunner()
        func git(_ arguments: String...) throws -> String {
            let result = try runner.run(URL(fileURLWithPath: "/usr/bin/git"), ["-C", folder.path] + arguments,
                                       environment: nil, currentDirectory: nil)
            XCTAssertEqual(result.status, 0, result.stderr)
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try git("init", "-q", repo.path)
        func commit(_ name: String) throws -> String {
            _ = try git("-C", repo.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@users.noreply.github.com",
                        "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", name)
            return try git("-C", repo.path, "rev-parse", "HEAD")
        }
        let old = try commit("old")
        let current = try commit("current")
        let recent = try commit("newer")
        _ = try git("-C", repo.path, "checkout", "-q", "--detach", old)
        let divergent = try commit("divergent")
        func stamp(_ value: String) throws {
            let plist = try PropertyListSerialization.data(fromPropertyList: ["DMCommit": value], format: .binary, options: 0)
            try plist.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        }
        var reader = InstalledEngineVersionReader(checkout: repo.path, selected: current)
        for (hash, expected) in [(old, InstalledEngineVersion.Relation.older), (current, .current),
                                 (recent, .newer), (divergent, .unknown)] {
            try stamp(String(hash.prefix(12)))
            guard case .known(_, let relation) = reader.version(of: app) else { return XCTFail("Expected a commit date") }
            XCTAssertEqual(relation, expected)
        }
        try stamp(String(repeating: "f", count: 40))
        XCTAssertEqual(reader.version(of: app), .unknown)
        try stamp(current)
        var missingCheckout = InstalledEngineVersionReader(checkout: folder.appendingPathComponent("Missing").path, selected: current)
        XCTAssertEqual(missingCheckout.version(of: app), .unknown) // matching text is not evidence
        var missingTarget = InstalledEngineVersionReader(checkout: repo.path, selected: String(repeating: "f", count: 40))
        guard case .known(_, .unknown) = missingTarget.version(of: app) else { return XCTFail("Expected only a date") }
        XCTAssertEqual(reader.version(of: folder.appendingPathComponent("Missing.app")), .noApp)
        XCTAssertEqual(reader.version(of: nil), .noApp)
    }

    func testAnOlderAppOnlyGetsAnUpdateMarkWithFilesAndWhenPlayable() {
        let older = InstalledEngineVersion.known(Date(timeIntervalSince1970: 0), .older)
        let en = AppLocale(language: .english, region: "US")
        XCTAssertTrue(older.detail(filesAvailable: false, context: en).hasSuffix("game files needed first"))
        XCTAssertTrue(older.detail(filesAvailable: true, context: en).hasSuffix("update available"))
        func look(playable: Bool = true, appInCloud: Bool = false, here: Bool = false, cloud: Bool? = false,
                  engine: InstalledEngineVersion = older) -> PortingTileLook {
            .resting(playable: playable, appInCloud: appInCloud, filesHere: here, filesInCloud: cloud,
                     engineIsOlder: engine.isOlder)
        }
        XCTAssertEqual(look(here: true), .engineUpdate)
        XCTAssertEqual(look(cloud: true), .engineUpdate)
        XCTAssertEqual(look(), .normal)
        XCTAssertEqual(look(cloud: nil), .normal)
        XCTAssertEqual(look(playable: false, appInCloud: true, here: true), .toDownload)
        XCTAssertEqual(look(playable: false, here: true), .toBuild)
        XCTAssertEqual(look(here: true, engine: .unknown), .normal)
    }
}
