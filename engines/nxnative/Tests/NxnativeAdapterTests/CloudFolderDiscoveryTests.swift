import Foundation
import XCTest
@testable import OortLibrary
@testable import ArcanePorting

final class CloudFolderDiscoveryTests: XCTestCase {
    private typealias Entry = CloudFolderDiscovery.Entry
    private let manifest = "manifests/0000000000000001-fixture.json"

    private func title(_ index: Int) -> String { String(format: "Fixture %02d [0100000000%06X]", index, 0x1000 + index * 0x2000) }
    private func file(_ path: String) -> Entry { .init(path: path, isDirectory: false) }
    private func folder(_ path: String) -> Entry { .init(path: path, isDirectory: true) }
    private func roms(_ root: String, _ count: Int, _ ext: String = "nsp") -> [Entry] {
        (0..<count).map { file("\(root)/\(title($0))/Fixture.\(ext)") }
    }

    private func expect(_ folder: CloudFolderDiscovery.Folder?, _ path: String, _ games: Int?, kept: Bool = false,
                        _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(folder?.path, path, message, line: line)
        XCTAssertEqual(folder?.games, games, message, line: line)
        XCTAssertEqual(folder?.kept, kept, message, line: line)
    }

    /// The maintainer's own Drive: the ROMs sit beside the library, not inside it.
    func testBothFoldersAreFoundAtOnceWhenTheROMsAreBesideTheLibrary() throws {
        let found = try CloudFolderDiscovery(entries: [
            folder("Games/Switch"), folder("Games/Switch/Oort-nx"), file("Games/Switch/Oort-nx/\(title(0))/\(manifest)"),
            folder("Games/Switch/Oort-nx/GameFiles"),
        ] + roms("Games/Switch/Jeux", 15), kept: nil)
        expect(found.library, "Games/Switch/Oort-nx", 1)
        expect(found.sources, "Games/Switch/Jeux", 15)
    }

    /// Regression: signing in again turned Games/Switch/Jeux back into Oort-nx/GameFiles.
    func testReconnectingTheSameAccountKeepsTheChosenFoldersEvenWhenAnotherHoldsMoreGames() throws {
        let kept = CloudKeptFolders(account: "accountA", library: "Games/Switch/Oort-nx", sources: "Games/Switch/Jeux")
        let entries = [folder("Games/Switch/Oort-nx"), folder("Games/Switch/Oort-nx/GameFiles"), folder("Games/Switch/Jeux")]
            + roms("Games/Switch/Oort-nx/GameFiles", 30)
        let found = try CloudFolderDiscovery(entries: entries, kept: kept.applying(to: "accountA"))
        expect(found.library, "Games/Switch/Oort-nx", 0, kept: true)
        expect(found.sources, "Games/Switch/Jeux", 0, kept: true)
    }

    func testAnotherAccountNeverInheritsTheFoldersAndAnUnknownOneMustShowItsGamesAgain() throws {
        let kept = CloudKeptFolders(account: "accountA", library: "Games/Old", sources: "Games/Switch/Jeux")
        XCTAssertNil(kept.applying(to: "accountB"))
        XCTAssertNil(kept.applying(to: nil))
        let unknown = try XCTUnwrap(CloudKeptFolders(account: nil, library: "Games/Old", sources: "Games/Switch/Jeux").applying(to: "accountB"))
        let empty = try CloudFolderDiscovery(entries: [folder("Games/Old"), folder("Games/Switch/Jeux")], kept: unknown)
        XCTAssertNil(empty.library)
        XCTAssertNil(empty.sources)
        let full = try CloudFolderDiscovery(entries: roms("Games/Switch/Jeux", 2) + roms("Games/More", 9), kept: unknown)
        expect(full.sources, "Games/Switch/Jeux", 2, kept: true)
    }

    func testAKeptFolderThatIsGoneGivesWayToWhatIsThere() throws {
        let kept = CloudKeptFolders(account: "accountA", library: "Games/Gone", sources: "Games/Gone/ROM")
        let found = try CloudFolderDiscovery(entries: [file("Games/Here/\(title(0))/\(manifest)")] + roms("Games/Switch/Jeux", 3), kept: kept)
        expect(found.library, "Games/Here", 1)
        expect(found.sources, "Games/Switch/Jeux", 3)
    }

    func testEveryPackageKindCountsAndUnrelatedFilesNever() throws {
        for ext in ["nsp", "xci", "nsz", "xcz", "nup", "NSP"] {
            let found = try CloudFolderDiscovery(entries: roms("Games/Switch/Jeux", 1, ext), kept: nil)
            expect(found.sources, "Games/Switch/Jeux", 1, ext)
        }
        let unrelated = try CloudFolderDiscovery(entries: [
            file("Games/Unrelated/Game/Base.nsp"), file("Games/Notes/\(title(0))/readme.txt"),
            file("Games/\(title(1)).app/\(title(2))/Base.nsp"), file("Games/Switch/Jeux/0100000000001000/Base.nsp"),
            file("Games/../Jeux/\(title(3))/Base.nsp"),
        ], kept: nil)
        XCTAssertNil(unrelated.sources, "Only “Title [ID]” folders that hold a package are proposed")
        XCTAssertNil(unrelated.library)
    }

    func testTheLibrarysOwnGameFilesKeepTheirOlderNames() throws {
        let library = file("Games/Library/\(title(0))/\(manifest)")
        let groups = try CloudFolderDiscovery(entries: [library, file("Games/Library/Switch/Jeux/Title/Game.XCI")], kept: nil)
        expect(groups.sources, "Games/Library/Switch/Jeux", 1)
        let loose = try CloudFolderDiscovery(entries: [library, file("Games/Library/GameFiles/game.nsp")], kept: nil)
        expect(loose.sources, "Games/Library/GameFiles", nil)
    }

    func testTheLargestThenTheShallowestWinsAndTooManyEntriesAreRefused() throws {
        let found = try CloudFolderDiscovery(entries: roms("Games/B/ROM", 2) + roms("Games/A", 2) + roms("Games/C", 1), kept: nil)
        XCTAssertEqual(found.sources?.path, "Games/A")
        XCTAssertThrowsError(try CloudFolderDiscovery(entries: Array(repeating: folder("Games/A"), count: CloudFolderIndex.limit + 1), kept: nil))
        let none = try CloudFolderDiscovery(entries: [], kept: nil)
        XCTAssertNil(none.library)
        XCTAssertNil(none.sources)
    }

    private func drive() throws -> CloudFolderIndex {
        try CloudFolderIndex(entries: [
            folder("Games/Switch"), folder("Games/Switch/Oort-nx"), folder("Games/Switch/Oort-nx/Lunar Observatory [0100000000001000]"),
            folder("Games/Switch/Oort-nx/Lunar Observatory [0100000000001000]/manifests"), folder("Games/Switch/Empty"),
        ] + roms("Games/Switch/Jeux", 15))
    }

    /// In the browser every folder says in words whether it fits.
    func testEachFolderSaysWhatItHolds() throws {
        let index = try drive()
        guard case .roms(15, let names) = index.kind(of: "Games/Switch/Jeux") else { return XCTFail("ROMs") }
        XCTAssertEqual(names.first, "Fixture 00")
        XCTAssertEqual(index.kind(of: "Games/Switch/Oort-nx"), .compiled(count: 1, names: ["Lunar Observatory"]))
        XCTAssertEqual(index.kind(of: "Games/Switch/Jeux/\(title(0))"), .oneGame)
        XCTAssertEqual(index.kind(of: "Games/Switch"), .further(["Games/Switch/Jeux", "Games/Switch/Oort-nx"]))
        XCTAssertEqual(index.kind(of: ""), .further(["Games/Switch/Jeux", "Games/Switch/Oort-nx"]))
        XCTAssertEqual(index.kind(of: "Games/Switch/Empty"), .nothing)
        XCTAssertEqual(index.kind(of: "Photos"), .unknown, "A folder never read is not an empty one")
        XCTAssertEqual(index.kind(of: "Games/a/b/c/d"), .unknown)
    }

    func testAWrongAnswerIsExplainedAndTheRightFolderProposed() throws {
        let index = try drive()
        let roms = "Games/Switch/Jeux", library = "Games/Switch/Oort-nx"
        XCTAssertNil(index.advice(.sources, choosing: roms, other: library))
        XCTAssertNil(index.advice(.library, choosing: library, other: roms))
        XCTAssertNil(index.advice(.library, choosing: "Games/Switch/Empty", other: roms), "An empty folder is fine for Oort")
        XCTAssertEqual(index.advice(.sources, choosing: library, other: roms), .init(reason: .compiledHere, instead: roms, swaps: true))
        XCTAssertEqual(index.advice(.library, choosing: roms, other: library), .init(reason: .romsHere, instead: library, swaps: true))
        XCTAssertEqual(index.advice(.sources, choosing: library, other: "Games/New"), .init(reason: .compiledHere, instead: roms, swaps: false))
        XCTAssertEqual(index.advice(.sources, choosing: "\(roms)/\(title(3))", other: library), .init(reason: .oneGame, instead: roms, swaps: false))
        XCTAssertEqual(index.advice(.sources, choosing: "Games", other: library), .init(reason: .further, instead: roms, swaps: false))
        XCTAssertEqual(index.advice(.library, choosing: "Games/Switch", other: roms), .init(reason: .further, instead: library, swaps: false))
        XCTAssertEqual(index.advice(.sources, choosing: "Games/Switch/Empty", other: library), .init(reason: .nothingHere, instead: roms, swaps: false))
        XCTAssertEqual(index.advice(.sources, choosing: roms, other: roms)?.reason, .sameFolder)
        XCTAssertNil(index.advice(.sources, choosing: "Photos", other: library), "What was not read is not judged")
        let first = try CloudFolderIndex(entries: onlyROMs())
        XCTAssertEqual(first.advice(.library, choosing: roms, other: roms), .init(reason: .romsHere, instead: nil, swaps: false))
        XCTAssertEqual(index.advice(.sources, choosing: library, other: library), .init(reason: .compiledHere, instead: roms, swaps: false))
        XCTAssertNil(first.advice(.library, choosing: "Games/Switch", other: roms), "Oort's first folder may sit beside the ROMs")
    }

    private func onlyROMs() -> [Entry] { [folder("Games/Switch")] + roms("Games/Switch/Jeux", 2) }

    /// The content decides: a folder named Jeux that holds ROMs is never proposed for compiled games.
    func testNewFoldersFollowTheSystemAndNeverLandAmongOtherFiles() throws {
        let empty = try CloudFolderDiscovery(entries: [], kept: nil)
        XCTAssertEqual(empty.newLibrary, "Games/Switch/Jeux")
        XCTAssertEqual(empty.newSources, "Games/Switch/ROM")
        let taken = try CloudFolderDiscovery(entries: roms("Games/Switch/Jeux", 3), kept: nil)
        XCTAssertEqual(taken.newLibrary, "Games/Switch/Oort-nx")
        let full = try CloudFolderDiscovery(entries: [file("Games/Switch/Jeux/notes.txt"), file("Games/Switch/Oort-nx/notes.txt"),
                                                      file("Games/Switch/ROM/notes.txt")], kept: nil)
        XCTAssertNil(full.newLibrary)
        XCTAssertNil(full.newSources)
        let bare = try CloudFolderDiscovery(entries: [folder("Games/Switch"), folder("Games/Switch/Jeux")], kept: nil)
        XCTAssertEqual(bare.newLibrary, "Games/Switch/Jeux", "An empty folder is fine")
    }

    func testWhatIsLeftToCompileIsWhatHasFilesAndNoCompiledGame() throws {
        let index = try drive()
        XCTAssertEqual(index.gamesToCompile(sources: "Games/Switch/Jeux", library: "Games/Switch/Oort-nx"), 14)
        XCTAssertNil(index.gamesToCompile(sources: "Photos", library: "Games/Switch/Oort-nx"))
    }

    func testTheServiceListsOnceAndDropsTheFoldersOfAnotherAccount() async throws {
        let seen = Seen()
        let name = title(0)
        let drive = CloudDriveFolders(remote: "fixture", executable: URL(fileURLWithPath: "/synthetic/rclone")) { _, args, _ in
            await seen.add(args[0])
            if args[0] == "listremotes" {
                return .init(status: 0, stdout: #"[{"name":"fixture","type":"drive","source":"file"}]"#, stderr: "")
            }
            if args[0] == "about" {
                return .init(status: 0, stdout: "{}", stderr: "'root_folder_id = accountB' - save this in the config to speed up startup")
            }
            XCTAssertEqual(Array(args.prefix(2)), ["lsjson", "fixture:Games"])
            XCTAssertTrue(args.contains("--recursive"))
            return .init(status: 0, stdout: #"[{"Path":"Switch/Jeux","Name":"Jeux","IsDir":true},{"Path":"Switch/Jeux/\#(name)/Base.nsp","Name":"Base.nsp","IsDir":false,"Size":1}]"#, stderr: "")
        }
        let found = try await drive.discoverFolders(kept: .init(account: "accountA", library: "Games/Switch/Jeux", sources: nil))
        XCTAssertNil(found.library)
        expect(found.sources, "Games/Switch/Jeux", 1)
        let commands = await seen.commands
        XCTAssertEqual(commands.filter { $0 == "lsjson" }.count, 1)
        XCTAssertEqual(commands.filter { $0 == "about" }.count, 1)
    }

    /// New folders go inside the folder and account the player saw, in one command; a lost reply is read, not written again.
    func testNewFoldersAreCreatedOnceInTheParentThatWasShown() async throws {
        let config = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).conf")
        try Data().write(to: config)
        defer { try? FileManager.default.removeItem(at: config) }
        for (account, lost, listed) in [("accountA", false, true), ("accountB", false, true), ("accountA", true, true), ("accountA", true, false)] {
            let seen = Seen()
            let drive = CloudDriveFolders(remote: "fixture", executable: URL(fileURLWithPath: "/synthetic/rclone"), config: config) { _, args, _ in
                await seen.add(args.prefix(2).joined(separator: " "))
                switch args[0] {
                case "listremotes": return .init(status: 0, stdout: #"[{"name":"fixture","type":"drive","source":"file"}]"#, stderr: "")
                case "about": return .init(status: 0, stdout: "{}", stderr: "'root_folder_id = \(account)' - save this in the config to speed up startup")
                case "mkdir": return .init(status: lost ? 1 : 0, stdout: "", stderr: lost ? "lost response" : "")
                case "lsjson" where args[1] == "fixture:Games/Switch":
                    return .init(status: 0, stdout: listed ? #"[{"Name":"ROM","IsDir":true}]"# : "[]", stderr: "")
                case "lsjson": return .init(status: 0, stdout: #"[{"Name":"Games","IsDir":true,"ID":"gamesID"}]"#, stderr: "")
                default: return .init(status: 0, stdout: "", stderr: "")
                }
            }
            do {
                try await drive.createPath("Games/Switch/ROM", below: "Games", shown: .init(account: "accountA", id: "gamesID"))
                XCTAssertTrue(account == "accountA" && (!lost || listed))
            } catch CloudLibraryFailure.scopeChanged { XCTAssertEqual(account, "accountB") }
            catch { XCTAssertTrue(lost && !listed, "\(error)") }
            let writes = await seen.commands.filter { $0.hasPrefix("mkdir") }
            XCTAssertEqual(writes, account == "accountA" ? ["mkdir fixture,root_folder_id=gamesID:Switch/ROM"] : [], "Another account is never written to")
        }
    }

    func testNoGamesFolderIsAbsenceAndARefusedListingIsAnError() async throws {
        for (status, stderr) in [(Int32(3), "directory not found"), (1, "googleapi: Error 403: forbidden")] {
            let drive = CloudDriveFolders(remote: "fixture", executable: URL(fileURLWithPath: "/synthetic/rclone")) { _, args, _ in
                args[0] == "listremotes"
                    ? .init(status: 0, stdout: #"[{"name":"fixture","type":"drive","source":"file"}]"#, stderr: "")
                    : .init(status: status, stdout: "", stderr: stderr)
            }
            do {
                let found = try await drive.discoverFolders(kept: nil)
                XCTAssertEqual(status, 3)
                XCTAssertNil(found.library)
                XCTAssertNil(found.sources)
            } catch {
                XCTAssertEqual(status, 1, "An access failure is not an empty Drive")
            }
        }
    }
}

private actor Seen {
    private(set) var commands: [String] = []
    func add(_ command: String) { commands.append(command) }
}
