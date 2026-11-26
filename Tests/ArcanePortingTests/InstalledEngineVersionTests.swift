import Foundation
import NXLibraryCore
import XCTest
@testable import ArcanePorting

final class InstalledEngineVersionTests: XCTestCase {
    func testBundleVersionAndGitAncestry() async throws {
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
        let shallow = folder.appendingPathComponent("Shallow")
        // Keep both endpoint objects, but mark HEAD as shallow so Git cannot prove their ancestry.
        _ = try git("clone", "-q", "--no-hardlinks", repo.path, shallow.path)
        try (current + "\n").write(to: shallow.appendingPathComponent(".git/shallow"), atomically: true, encoding: .utf8)
        let recent = try commit("newer")
        _ = try git("-C", repo.path, "checkout", "-q", "--detach", old)
        let divergent = try commit("divergent")
        func stamp(_ value: String) throws {
            let plist = try PropertyListSerialization.data(fromPropertyList: ["DMCommit": value], format: .binary, options: 0)
            try plist.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        }
        let place = Place(UUID()), entry = Entry(UUID()), installation = Installation(UUID())
        let binding = EngineBinding(place, entry, installation: installation, profile: Profile(UUID()), generation: Generation(UUID()))
        func version(_ checkout: URL, _ target: String = current, url: URL? = nil) async throws -> InstalledVersion {
            let engine: any EngineAdapter = MacNXNative(place: place, checkout: checkout.path,
                prescribed: old, expected: target, apps: [installation: url ?? app])
            return try await engine.game(binding).embedded
        }
        try stamp(String(old.prefix(12)))
        let full = try await version(repo)
        let truncated = try await version(shallow)
        XCTAssertEqual(full.identity, truncated.identity)
        guard case .known(let fullDate, .older) = full.status,
              case .known(let shallowDate, .unknown) = truncated.status else {
            return XCTFail("Same commits should give a badge only when their ancestry is known")
        }
        XCTAssertEqual(fullDate, shallowDate)
        for (hash, expected) in [(old, InstalledVersion.Relation.older), (current, .current),
                                 (recent, .newer), (divergent, .unknown)] {
            try stamp(String(hash.prefix(12)))
            guard case .known(_, let relation) = try await version(repo).status else { return XCTFail("Expected a commit date") }
            XCTAssertEqual(relation, expected)
        }
        try stamp(String(repeating: "f", count: 40))
        let unrecognized = try await version(repo)
        XCTAssertEqual(unrecognized.status, .unknown)
        try stamp(current)
        let missingCheckout = try await version(folder.appendingPathComponent("Missing"))
        XCTAssertEqual(missingCheckout.status, .unknown) // matching text is not evidence
        let missingTarget = try await version(repo, String(repeating: "f", count: 40))
        guard case .known(_, .unknown) = missingTarget.status else { return XCTFail("Expected only a date") }
        let missingBundle = try await version(repo, url: folder.appendingPathComponent("Missing.app"))
        XCTAssertEqual(missingBundle.status, .noApp)
    }

    func testAnOlderAppOnlyGetsAnUpdateMarkWithFilesAndWhenPlayable() {
        let older = InstalledVersion.Status.known(Date(timeIntervalSince1970: 0), .older)
        let en = AppLocale(language: .english, region: "US")
        XCTAssertTrue(older.detail(filesAvailable: false, context: en).hasSuffix("game files needed first"))
        XCTAssertTrue(older.detail(filesAvailable: true, context: en).hasSuffix("update available"))
        func look(playable: Bool = true, appInCloud: Bool = false, here: Bool = false, cloud: Bool? = false,
                  engine: InstalledVersion.Status = older) -> PortingTileLook {
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
