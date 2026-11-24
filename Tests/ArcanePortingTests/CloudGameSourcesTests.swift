import Foundation
import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class CloudGameSourcesTests: XCTestCase {
    func testDiscoveryIsScopedAndRejectsUncertainIdentity() async throws {
        let base = "0100000000001000", flat = "0100000000002000", duplicate = "0100000000003000"
        let folder = "Lunar Observatory [\(base)]", first = "First [\(duplicate)]", second = "Second [\(duplicate)]"
        let listings = [
            "fixture:Games": Self.entries(directories: ["GameFiles", "Switch"]),
            "fixture:Games/GameFiles": Self.entries(directories: [folder, first, second, "Unreadable", "Ambiguous", "Case", "case", "Archive.app"],
                                                   files: ["Flat [\(flat)].xci", "Name only.nsp", "../Escape [\(flat)].nsp", "Other [\(flat)][\(base)].nsp"]),
            "fixture:Games/GameFiles/\(folder)": Self.entries(files: ["Game.nsp", "Update [0100000000001800][v64].nsz"]),
            "fixture:Games/GameFiles/\(first)": Self.entries(files: ["First.nsp"]),
            "fixture:Games/GameFiles/\(second)": Self.entries(files: ["Second.nsp"]),
            "fixture:Games/GameFiles/Ambiguous": Self.entries(files: ["One [\(base)].nsp", "Two [\(flat)].nsp"]),
        ]
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            XCTAssertEqual(args.first, "lsjson")
            XCTAssertTrue(args.contains("--drive-skip-shortcuts"))
            XCTAssertFalse(args.contains("--hash"))
            let path = args[1]
            if path == "fixture:Games/GameFiles/Unreadable" { return .init(status: 1, stdout: "", stderr: "403 forbidden") }
            let listing = try XCTUnwrap(listings[path], "Unexpected read: \(path)")
            return .init(status: 0, stdout: listing, stderr: "")
        }
        let discovery = try await CloudGameSources(backend: backend, root: "Games/GameFiles").discover()
        XCTAssertEqual(discovery.games.map(\.titleID), [base, flat])
        XCTAssertEqual(discovery.games.first?.name, "Lunar Observatory")
        XCTAssertEqual(discovery.games.first?.files.map(\.kind), [.base, .update])
        XCTAssertEqual(discovery.ambiguous, ["Ambiguous", "Case", first, "Other [\(flat)][\(base)].nsp", second, "case"].sorted())
        XCTAssertEqual(discovery.unreadable, ["../Escape [\(flat)].nsp", "Name only.nsp", "Unreadable"])

        for path in ["Other/GameFiles", "GamesPrivate/GameFiles", "Games/../Other", "Games"] {
            let service = CloudGameSources(backend: backend, root: path)
            let result = try await service.discover()
            XCTAssertTrue(result.games.isEmpty)
        }
    }

    func testReferenceSourcesOnlyAndCatalogKeepsLocalCopyAndExclusions() async throws {
        let title = "0100000000004000", other = "0100000000005000", reference = "reference-fixture"
        let listings = [
            "fixture:": Self.entries(directories: ["Switch"]),
            "fixture:Switch": Self.entries(directories: ["Games"]),
            "fixture:Switch/Games": Self.entries(files: ["Orbit [\(title)].nsp", "Dawn [\(other)].nsp"]),
        ]
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            XCTAssertEqual(args.first, "lsjson")
            XCTAssertTrue(args.contains(reference))
            XCTAssertFalse(args.contains("--hash"))
            return .init(status: 0, stdout: try XCTUnwrap(listings[args[1]]), stderr: "")
        }
        let scoped = try XCTUnwrap(backend.reference(folderID: reference))
        let discovery = try await CloudGameSources(backend: scoped, root: "GameFiles", usesDefaultRoot: true).discover()
        XCTAssertEqual(discovery.games.map(\.titleID), [title, other])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CatalogRepository(store: .init(directory: root.appendingPathComponent("catalog")))
        let catalog = try repository.importCloudGames([], discovered: discovery.games, in: root, sourceRoot: root, referenceFolder: reference)
        let kept = try XCTUnwrap(catalog.nxnativeGames.first)
        let absent = try XCTUnwrap(catalog.nxnativeGames.last)
        XCTAssertTrue(kept.isCloudSourcePlaceholder)
        XCTAssertEqual(kept.cloudReferenceFolder, reference)
        XCTAssertEqual(GameResourceState.unavailableReason(for: kept), .sourcesMissing)
        let files = CloudGameSources.importedFolder(for: kept.id, in: root)
        XCTAssertEqual(discovery.games[0].availability(for: kept.sources, in: files)?.state, .cloudOnly)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.path), "Discovery must not download or create source directories")
        let downloaded = try XCTUnwrap(kept.sources.first?.url)
        try FileManager.default.createDirectory(at: downloaded.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: downloaded)
        XCTAssertNil(GameResourceState.unavailableReason(for: kept))
        XCTAssertEqual(discovery.games[0].availability(for: kept.sources, in: files)?.state, .unknown)
        XCTAssertEqual(try repository.forgetCloudReference(reference).nxnativeGames.map(\.id), [kept.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloaded.path))
        let imported = try repository.importCloudGames([], discovered: discovery.games, in: root, sourceRoot: root, referenceFolder: reference)
        let removable = try XCTUnwrap(imported.nxnativeGames.first { $0.titleId == other })
        XCTAssertNotEqual(removable.id, absent.id)
        _ = try repository.removeNXNative(id: removable.id)
        XCTAssertEqual(try repository.importCloudGames([], discovered: discovery.games, in: root, sourceRoot: root).nxnativeGames.map(\.id), [kept.id])
    }

    private static func entries(directories: [String] = [], files: [String] = []) -> String {
        let rows: [[String: Any]] = directories.map { ["Name": $0, "Path": $0, "Size": -1, "IsDir": true] }
            + files.map { ["Name": $0, "Path": $0, "Size": 1, "IsDir": false] }
        return String(decoding: try! JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
    }

    func testExplicitSourceUpdateKeepsUnchangedAndPreviousPackages() async throws {
        let f = try Fixture()
        let base = try f.local("Base.nsp", "base")
        let update = try f.local("Update.nsz", "local")
        let dlc = f.localFolder.appendingPathComponent("DLC.nup")
        _ = try f.remote("Base.nsp", "base")
        _ = try f.remote("Update.nsz", "reference")
        _ = try f.remote("DLC.nup", "new")
        let newer = Date(timeIntervalSinceNow: 60)
        await assertError(.localChanged) {
            try await f.service.download(folderName: f.folder, files: [base, update, dlc],
                                         replacingBefore: newer, replacing: [], progress: nil)
        }
        let inode = try CloudArchiveInventory.node(at: base).st_ino
        try await f.service.download(folderName: f.folder, files: [base, update, dlc],
                                     replacingBefore: newer, replacing: [update], progress: nil)
        XCTAssertEqual(try CloudArchiveInventory.node(at: base).st_ino, inode)
        XCTAssertEqual(try String(contentsOf: update, encoding: .utf8), "reference")
        XCTAssertEqual(try String(contentsOf: dlc, encoding: .utf8), "new")
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: f.localFolder,
            includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".arcane-sources-") })
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("file"), encoding: .utf8), "local")
    }

    func testDownloadRefusesInsufficientSpaceBeforeAnyPayloadOrStaging() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            XCTAssertEqual(args.first, "lsjson")
            XCTAssertFalse(args.contains("--stat"))
            let reply = """
            [{"Name":"Game.nup","Path":"Game.nup","Size":600000,"Hashes":{"md5":"0123456789abcdef0123456789abcdef"}},
             {"Name":"Update.nup","Path":"Update.nup","Size":600000,"Hashes":{"md5":"0123456789abcdef0123456789abcdef"}}]
            """
            return .init(status: 0, stdout: reply, stderr: "")
        }
        let service = CloudGameSources(backend: backend, root: "Games/Sources", capacity: { _ in 2_000_000 }, trash: { _ in })
        do {
            try await service.download(folderName: "Fixture [0100000000000001]",
                                       files: ["Game.nup", "Update.nup"].map { root.appendingPathComponent($0) }, progress: nil)
            XCTFail("Enough space for one file, but not both")
        } catch {
            XCTAssertEqual((error as? CloudLibraryFailure)?.action, .freeMacStorage)
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testAvailabilityListsCopiesWithoutTreatingEqualSizesAsSynchronized() async throws {
        let f = try Fixture()
        let base = try f.local("Base.nsp", "same")
        let update = f.localFolder.appendingPathComponent("Update.nsz")
        _ = try f.remote("Base.nsp", "size")
        _ = try f.remote("Update.nsz", "update")
        let status = try await f.service.availability(folderName: f.folder, files: [base, update])
        XCTAssertEqual(status.files.map(\.state), [.unknown, .cloudOnly])
        XCTAssertEqual(status.remoteBytes, 10)
    }

    func testFolderNameKeepsMatchingLocalNameAndOtherwiseUsesSafeCatalogTitle() {
        let id = "010019401051C000"
        let existing = "Mario Strikers - Battle League [\(id)]"
        XCTAssertEqual(CloudGameSources.folderName(local: existing, title: "Renamed", titleID: id.lowercased()), existing)
        XCTAssertEqual(CloudGameSources.folderName(local: "All ROMs", title: "Mario Strikers", titleID: id),
                       "Mario Strikers [\(id)]")
        XCTAssertEqual(CloudGameSources.folderName(local: "Other [0100123456789ABC]",
                                                    title: "  Mario/ Strikers:  Battle\u{0000} League. . ", titleID: id),
                       "Mario - Strikers - Battle League [\(id)]")
        XCTAssertNil(CloudGameSources.folderName(local: existing, title: "Game", titleID: "invalid"))
    }

    func testStatusPartialUploadAndConflictNeverOverwrite() async throws {
        let f = try Fixture()
        let base = try f.local("Base.nsp", "base")
        let update = try f.local("Update.nsz", "update")
        let dlc = try f.local("DLC.nup", "dlc")
        let existing = try f.remote("Base.nsp", "base")
        var status = try await f.service.status(folderName: f.folder, files: [base, update])
        XCTAssertEqual(status.state, .notInCloud)
        XCTAssertEqual(status.files.map(\.state), [.synchronized, .notInCloud])
        XCTAssertEqual(status.localBytes, 10)
        XCTAssertEqual(status.remoteBytes, 4)
        let inode = try CloudArchiveInventory.node(at: existing).st_ino

        try await f.service.upload(folderName: f.folder, files: [base, update], progress: nil)
        XCTAssertEqual(try CloudArchiveInventory.node(at: existing).st_ino, inode)
        status = try await f.service.status(folderName: f.folder, files: [base, update])
        XCTAssertEqual(status.state, .synchronized)
        XCTAssertEqual(status.remoteBytes, 10)

        try Data("fake".utf8).write(to: base)
        status = try await f.service.status(folderName: f.folder, files: [base, dlc])
        XCTAssertEqual(status.state, .newerOnThisMac)
        await assertError(.sourcesConflict) {
            try await f.service.upload(folderName: f.folder, files: [dlc, base], progress: nil)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.remoteFolder.appendingPathComponent("DLC.nup").path))
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "base")
    }

    func testCloudOnlyDownloadSizeAndVerifiedStagingDoNotReplaceLocalFile() async throws {
        let f = try Fixture()
        let base = try f.local("Base.xci", "keep")
        _ = try f.remote("Base.xci", "old!")
        let dlc = f.localFolder.appendingPathComponent("DLC.xcz")
        _ = try f.remote("DLC.xcz", "dlc")
        let status = try await f.service.status(folderName: f.folder, files: [dlc])
        XCTAssertEqual(status.state, .cloudOnly)
        XCTAssertNil(status.files.first?.localBytes)
        let required = try await f.service.downloadSize(folderName: f.folder, files: [base, dlc])
        XCTAssertEqual(required, 3)
        try await f.service.download(folderName: f.folder, files: [base, dlc], progress: nil)
        XCTAssertEqual(try String(contentsOf: base, encoding: .utf8), "keep")
        XCTAssertEqual(try String(contentsOf: dlc, encoding: .utf8), "dlc")
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: f.localFolder.path)), ["Base.xci", "DLC.xcz"])
    }

    func testFreeRequiresConfirmationAndFreshMD5ThenUsesTrash() async throws {
        let f = try Fixture()
        let file = try f.local("Fixture-\(UUID()).nsp", "base")
        let remote = try f.remote(file.lastPathComponent, "base")
        await assertError(.confirmationRequired) {
            _ = try await f.service.free(folderName: f.folder, files: [file], confirmed: false)
        }
        _ = try await f.service.status(folderName: f.folder, files: [file])
        try Data("fake".utf8).write(to: remote)
        await assertError(.sourcesConflict) {
            _ = try await f.service.free(folderName: f.folder, files: [file], confirmed: true)
        }
        let trash = f.directory.appendingPathComponent(file.lastPathComponent)
        try Data("base".utf8).write(to: remote)
        let freed = try await f.service.free(folderName: f.folder, files: [file], confirmed: true)
        XCTAssertEqual(freed, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try String(contentsOf: trash, encoding: .utf8), "base")
    }

    func testMissingRemoteMD5IsUnknownAndDoesNotPermitMutation() async throws {
        let f = try Fixture(withoutHashes: true)
        let file = try f.local("Base.nsp", "base")
        _ = try f.remote("Base.nsp", "base")
        let status = try await f.service.status(folderName: f.folder, files: [file])
        XCTAssertEqual(status.state, .unknown)
        XCTAssertEqual(status.files.first?.remoteBytes, 4)
        await assertError(.invalidArchive) {
            _ = try await f.service.free(folderName: f.folder, files: [file], confirmed: true)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCancelledUploadDoesNotCreateRemoteFileAndReleasesSharedLease() async throws {
        let f = try Fixture()
        let file = try f.local("Base.nsp", "base")
        let archive = CloudGameArchive(backend: f.backend)
        let lease = try await archive.beginBuild(titleID: f.titleID)
        await assertError(.busy) {
            try await f.service.upload(folderName: f.folder, files: [file], progress: nil)
        }
        await archive.endBuild(titleID: f.titleID, token: lease)
        do {
            try await Task {
                try await f.service.upload(folderName: f.folder, files: [file]) { progress in
                    if progress.isVerifying { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }.value
            XCTFail("Expected cancellation")
        }
        catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.remoteFolder.appendingPathComponent("Base.nsp").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.remoteFolder.deletingLastPathComponent()
            .appendingPathComponent(".arcane-upload").path), [])
        try await f.service.upload(folderName: f.folder, files: [file], progress: nil)
    }

    func testDestinationAppearingInUploadStagingIsNotOverwritten() async throws {
        let f = try Fixture()
        let source = try f.local("Base.nsp", "base")
        let destination = f.remoteFolder.appendingPathComponent("Base.nsp")
        try FileManager.default.createDirectory(at: f.remoteFolder, withIntermediateDirectories: true)
        await assertError(.sourcesConflict) {
            try await f.service.upload(folderName: f.folder, files: [source]) { progress in
                if progress.isVerifying { try? Data("race".utf8).write(to: destination) }
            }
        }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "race")
    }

    func testDestinationAppearingInDownloadStagingIsNotOverwritten() async throws {
        let f = try Fixture()
        let destination = f.localFolder.appendingPathComponent("Base.nsp")
        _ = try f.remote("Base.nsp", "base")
        await assertError(.localChanged) {
            try await f.service.download(folderName: f.folder, files: [destination]) { progress in
                if progress.isVerifying { try? Data("race".utf8).write(to: destination) }
            }
        }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "race")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.localFolder.path), ["Base.nsp"])
    }

    func testDownloadDoesNotPublishBytesThatDifferFromListedMD5() async throws {
        let f = try Fixture()
        let destination = f.localFolder.appendingPathComponent("Base.nsp")
        let remote = try f.remote("Base.nsp", "base")
        await assertError(.invalidArchive) {
            try await f.service.download(folderName: f.folder, files: [destination]) { progress in
                if progress.bytesTransferred == 0 && !progress.isVerifying {
                    try? Data("raced".utf8.prefix(4)).write(to: remote)
                }
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.localFolder.path), [])
    }

    private func assertError(_ expected: CloudArchiveError, _ operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? CloudArchiveError, expected) }
    }

    private final class Fixture {
        let directory: URL
        let root: URL
        let localFolder: URL
        let remoteFolder: URL
        let titleID: String
        let folder: String
        let backend: RcloneStorageBackend
        let service: CloudGameSources

        init(withoutHashes: Bool = false) throws {
            guard let rclone = RcloneStorageBackend.findExecutable() else { throw XCTSkip("rclone unavailable") }
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            titleID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))
            folder = "Fixture [\(titleID)]"
            localFolder = directory.appendingPathComponent("local/\(folder)", isDirectory: true)
            root = directory.appendingPathComponent("Games", isDirectory: true)
            let sourcesRoot = directory.appendingPathComponent("Sources", isDirectory: true)
            remoteFolder = sourcesRoot.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sourcesRoot, withIntermediateDirectories: true)
            let config = directory.appendingPathComponent("rclone.conf")
            try Data().write(to: config)
            var executable = rclone
            if withoutHashes {
                executable = directory.appendingPathComponent("nohash")
                try """
                #!/bin/sh
                [ "$1" != rcd ] || exit 1
                RCLONE_LOCAL_HASHES=sha1 exec '\(rclone.path)' "$@"
                """.write(to: executable, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            }
            backend = RcloneStorageBackend(remote: ":local:", root: root.path, executable: executable, config: config)
            service = CloudGameSources(backend: backend, root: sourcesRoot.path) { [directory] file in
                try FileManager.default.moveItem(at: file, to: directory.appendingPathComponent(file.lastPathComponent))
            }
        }

        deinit {
            backend.stopRemoteControl()
            try? FileManager.default.removeItem(at: directory)
        }

        func local(_ name: String, _ content: String) throws -> URL {
            let file = localFolder.appendingPathComponent(name)
            try Data(content.utf8).write(to: file)
            return file
        }

        func remote(_ name: String, _ content: String) throws -> URL {
            try FileManager.default.createDirectory(at: remoteFolder, withIntermediateDirectories: true)
            let file = remoteFolder.appendingPathComponent(name)
            try Data(content.utf8).write(to: file)
            return file
        }
    }

    func testForEachChunkReadsWholeFileInBoundedChunks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data((0..<10_000).map { UInt8($0 % 251) })
        try data.write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var read = Data(), sizes: [Int] = []
        try handle.forEachChunk(4096) { read.append($0); sizes.append($0.count) }
        XCTAssertEqual(read, data)
        XCTAssertEqual(sizes, [4096, 4096, 1808])
    }
}
