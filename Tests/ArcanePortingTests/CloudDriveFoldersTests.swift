import Foundation
import CryptoKit
import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class CloudDriveFoldersTests: XCTestCase {
    func testDiscoverLibraryReadsOnlyGamesAndImmediateChildrenUsingValidatedManifests() async throws {
        let named = "Old name [\(DiscoveryBackend.title)]"
        let backend = try DiscoveryBackend(folder: named)
        var checked = [String]()
        let match = try await CloudDriveFolders.discoverLibrary(directories: { path in
            checked.append(path)
            switch path {
            case "Games": return ["Empty", "Library", DiscoveryBackend.title]
            case "Games/Empty": return ["Nested"]
            case "Games/Library": return [DiscoveryBackend.title, named, named]
            default: throw StorageBackendError.invalidKey
            }
        }, count: { path, folders in
            if path == "Games" { return 0 }
            return try await CloudDriveFolders.libraryCount(backend, folders: folders)
        })
        XCTAssertEqual(match, .init(path: "Games/Library", games: 1))
        XCTAssertEqual(checked, ["Games", "Games/Empty", "Games/Library"])
        let reads = await backend.reads
        XCTAssertEqual(reads, ["\(named)/manifests", "\(DiscoveryBackend.title)/manifests", backend.manifest.key.value])
    }

    func testDiscoveryDistinguishesErrorsAndCancellationFromAbsence() async throws {
        let absent = try await CloudDriveFolders.discoverLibrary(directories: { _ in throw StorageBackendError.notFound },
            count: { _, _ in XCTFail("No manifest reads for a missing Games folder"); return 0 })
        XCTAssertNil(absent)
        do {
            _ = try await CloudDriveFolders.discoverLibrary(directories: { _ in ["Library"] },
                count: { _, _ in throw StorageBackendError.backendUnavailable })
            XCTFail("Access failure is not an empty library")
        } catch StorageBackendError.backendUnavailable {}
        let unreadable = try DiscoveryBackend(corrupt: true)
        do {
            _ = try await CloudDriveFolders.discoverLibrary(directories: { _ in [DiscoveryBackend.title] },
                count: { _, folders in try await CloudDriveFolders.libraryCount(unreadable, folders: folders) })
            XCTFail("An invalid manifest is not an empty library")
        } catch CloudArchiveError.invalidManifest {}
        do {
            _ = try await CloudDriveFolders.discoverLibrary(directories: { _ in (0...64).map { "Folder \($0)" } },
                count: { _, _ in 0 })
            XCTFail("Discovery must cap the number of library candidates")
        } catch StorageBackendError.invalidResponse {}
        let cancelled = Task {
            try await CloudDriveFolders.discoverLibrary(directories: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return []
            }, count: { _, _ in XCTFail("No manifest reads after cancellation"); return 0 })
        }
        do {
            _ = try await cancelled.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
    }

    func testDiscoverSourcesProbesKnownPathsAndIgnoresDeepOrUnrecognizedFiles() async throws {
        var checked = [String]()
        let match = try await CloudDriveFolders.discoverSources(library: "Games/Library") { path in
            checked.append(path)
            switch path {
            case "Games/Library/GameFiles": return ["title/deeper/game.nsp", "readme.txt"]
            case "Games/Library/Switch/Jeux": return ["Title/Game.XCI"]
            default: throw StorageBackendError.invalidKey
            }
        }
        XCTAssertEqual(match, .init(path: "Games/Library/Switch/Jeux", games: 1))
        XCTAssertEqual(checked, ["Games/Library/GameFiles", "Games/Library/Switch/Jeux"])
        let loose = try await CloudDriveFolders.discoverSources(library: "Games") { _ in ["game.nsp", "update.nup"] }
        XCTAssertEqual(loose, .init(path: "Games/GameFiles", games: nil))
    }

    func testAutomaticSourceDiscoveryDoesNotListSiblingsOfTheSelectedLibrary() async throws {
        var checked: [String] = []
        let result = try await CloudDriveFolders.discoverSources(library: "Games/Chosen library") { path in
            checked.append(path)
            if path == "Games/Switch/Jeux" { return ["Unrelated/Game.XCI"] }
            return []
        }
        XCTAssertEqual(checked, ["Games/Chosen library/GameFiles", "Games/Chosen library/Switch/Jeux",
                                 "Games/Chosen library/Switch/Games"])
        XCTAssertNil(result, "An unrelated folder must not be indexed or suggested")
        for invalid in ["", "Games/../Other", "Games//Other"] {
            do {
                _ = try await CloudDriveFolders.discoverSources(library: invalid) { _ in
                    XCTFail("No automatic scan is allowed without a valid selected folder")
                    return []
                }
                XCTFail("Expected an invalid key")
            } catch StorageBackendError.invalidKey {}
        }
    }

    func testDiscoverSourcesFindsSwitchGamesOnlyAfterExistingLocationsAndIgnoresAppArchives() async throws {
        let library = "Games/Chosen library"
        let candidates = ["GameFiles", "Switch/Jeux", "Switch/Games"].map { "\(library)/\($0)" }
        let archives = ["Fixture [0100123456789ABC]/manifest.json", "Fixture [0100123456789ABC]/app/old.aar",
                        "Fixture [0100123456789ABC]/cache/partial.xci", "Fixture.App/embedded.nsp"]
        for selected in [0, 1, 2, nil] as [Int?] {
            var checked = [String]()
            let match = try await CloudDriveFolders.discoverSources(library: library) { path in
                checked.append(path)
                let index = try XCTUnwrap(candidates.firstIndex(of: path), "Only scan sources under the selected library")
                return selected.map { index >= $0 } == true
                    ? archives + ["Fixture [0100123456789ABC]/Base.nsp", "Fixture [0100123456789ABC]/Update.nsp"]
                    : archives
            }
            XCTAssertEqual(match, selected.map { .init(path: candidates[$0], games: 1) })
            XCTAssertEqual(checked, Array(candidates.prefix(selected.map { $0 + 1 } ?? candidates.count)))
        }
    }

    func testSavedMoveCanBeCancelledThenRetryReusesTheDestinationCopy() async throws {
        let title = "0100123456789ABC"
        let name = String(repeating: "a", count: 64) + ".aar"
        let hash = String(repeating: "b", count: 32)
        let key = "\(title)/app/\(name)"
        let manifest = "0000000000000001-\(String(repeating: "c", count: 64)).json"
        let manifestKey = "\(title)/manifests/\(manifest)"
        let artifact = #"{"key":{"value":"\#(key)"},"size":7,"hashes":{"md5":"\#(hash)"}}"#
        let payload = """
        {"source":"Old","remote":"fixture","games":1,"bytes":7,
        "binding":{"account":"accountA","sourceID":"oldID","destinationID":"newID","destination":"New"},"entries":[
          {"file":\(artifact),"dependencies":[]},
          {"file":{"key":{"value":"\(manifestKey)"},"size":7,"hashes":{"md5":"\(hash)"}},"dependencies":[\(artifact)]}]}
        """
        let plan = try JSONDecoder().decode(CloudDriveFolders.MovePlan.self, from: Data(payload.utf8))
        let request = LibraryMoveRequest(plan: plan, destination: "New")
        let saved = try JSONEncoder().encode(request)
        let restored = try JSONDecoder().decode(LibraryMoveRequest.self, from: saved)
        let config = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: config)
        defer { try? FileManager.default.removeItem(at: config) }
        let drive = CloudDriveFolders(remote: "fixture", executable: URL(fileURLWithPath: "/synthetic/rclone"),
                                      config: config) { _, args, _ in
            if args.first == "listremotes" {
                return .init(status: 0, stdout: #"[{"name":"fixture","type":"drive","source":"file"}]"#, stderr: "")
            }
            XCTAssertTrue(args.contains("--drive-shared-with-me=false"))
            XCTAssertTrue(args.contains("--drive-skip-shortcuts"))
            if args[0] == "about" {
                return .init(status: 0, stdout: "{}", stderr: "'root_folder_id = accountA' - save this in the config to speed up startup")
            }
            XCTAssertEqual(args[0], "lsjson", "The verified destination copy must not be moved again")
            let listing: String
            switch args[1] {
            case "fixture:": listing = #"[{"Name":"Old","IsDir":true,"ID":"oldID"},{"Name":"New","IsDir":true,"ID":"newID"}]"#
            case "fixture,root_folder_id=newID:": listing = """
                [{"Name":"\(name)","Path":"\(key)","Size":7,"IsDir":false,"Hashes":{"MD5":"\(hash)"}},
                 {"Name":"\(manifest)","Path":"\(manifestKey)","Size":7,"IsDir":false,"Hashes":{"MD5":"\(hash)"}}]
                """
            case "fixture,root_folder_id=newID:\(title)/app":
                listing = #"[{"Name":"\#(name)","Size":7,"IsDir":false,"Hashes":{"MD5":"\#(hash)"}}]"#
            case "fixture,root_folder_id=newID:\(title)/manifests":
                listing = #"[{"Name":"\#(manifest)","Size":7,"IsDir":false,"Hashes":{"MD5":"\#(hash)"}}]"#
            default: listing = "[]"
            }
            return .init(status: 0, stdout: listing, stderr: "")
        }
        do {
            _ = try await drive.move(restored.plan, to: restored.destination) { done, total in
                XCTAssertEqual(done, 0)
                XCTAssertEqual(total, 2)
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        let id = UUID()
        var history = ActivityHistory()
        history.record(id: id, job: .move(request), name: "New", outcome: .cancelled)
        XCTAssertTrue(history.retry(id) { $0.job == .move(restored) }, "An interrupted move must keep its Retry action")
        var progress = [Int]()
        let conflicts = try await drive.move(restored.plan, to: restored.destination) { done, _ in
            progress.append(done)
        }
        XCTAssertEqual(progress, [0, 1, 2])
        XCTAssertEqual(conflicts, [])
        let invalid = try JSONDecoder().decode(CloudDriveFolders.MovePlan.self,
            from: Data(payload.replacingOccurrences(of: key, with: "\(title)/GameFiles/test.nsp").utf8))
        do {
            _ = try await drive.move(invalid, to: "New") { _, _ in XCTFail("Invalid entry reached progress") }
            XCTFail("Only archive keys can be restored from disk")
        } catch StorageBackendError.invalidKey {}
    }

    func testArchiveManifestWaitsForObjectsOnResumeAndMoveLeavesGameFilesInPlace() async throws {
        try await withMoveFixture { drive, root in
            let title = "0100123456789ABC"
            let old = root.appendingPathComponent("Old")
            let new = root.appendingPathComponent("New")
            let fm = FileManager.default
            let payload = root.appendingPathComponent("payload")
            try Data("archive".utf8).write(to: payload)
            let hashes = try CloudArchiveInventory.hashes(at: payload)
            let sha = try XCTUnwrap(hashes["sha256"]), md5 = try XCTUnwrap(hashes["md5"])
            let artifacts = CloudArtifactKind.allCases.map {
                CloudGameManifest.Artifact(kind: $0, size: 7, sha256: sha, md5: md5, unpackedSize: 1,
                    entryCount: 1, inventorySHA256: sha, engineCommit: nil, shaderChain: nil, options: [:])
            }
            let manifest = CloudGameManifest(version: 1, titleID: title, createdAt: Date(), artifacts: artifacts)
            let manifestDir = old.appendingPathComponent("\(title)/manifests")
            try fm.createDirectory(at: manifestDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let staged = root.appendingPathComponent("fixture.json")
            try encoder.encode(manifest).write(to: staged)
            let checksum = try XCTUnwrap(CloudArchiveInventory.hashes(at: staged)["sha256"])
            let manifestPath = "\(title)/manifests/0000000000000001-\(checksum).json"
            try fm.moveItem(at: staged, to: old.appendingPathComponent(manifestPath))
            let keys = artifacts.flatMap { $0.objects(titleID: title) }.map(\.key.value).sorted()
            for key in keys {
                let target = old.appendingPathComponent(key)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: payload, to: target)
            }
            let gameFiles = ["Switch/Jeux/Other/game.nsp", "GameFiles/Test [\(title)]/game.xci"]
            for path in gameFiles {
                let source = old.appendingPathComponent(path)
                try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: payload, to: source)
            }
            let clash = new.appendingPathComponent(keys[1])
            try fm.createDirectory(at: clash.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("changed".utf8).write(to: clash)
            let plan = try await drive.movePlan(from: "Old")
            XCTAssertEqual(plan.games, 1)
            XCTAssertEqual(plan.bytes, 14 + (try CloudArchiveInventory.node(at: old.appendingPathComponent(manifestPath)).st_size))
            do {
                _ = try await drive.move(plan, to: "New") { done, _ in
                    if done == 1 { throw CancellationError() }
                }
                XCTFail("Expected cancellation")
            } catch is CancellationError {}
            XCTAssertTrue(fm.fileExists(atPath: new.appendingPathComponent(keys[0]).path))
            XCTAssertTrue(fm.fileExists(atPath: old.appendingPathComponent(keys[1]).path))
            let conflicts = try await drive.move(plan, to: "New") { done, total in
                if done < total {
                    XCTAssertFalse(fm.fileExists(atPath: new.appendingPathComponent(manifestPath).path))
                }
            }
            XCTAssertEqual(conflicts, [keys[1], manifestPath])
            XCTAssertTrue(fm.fileExists(atPath: old.appendingPathComponent(manifestPath).path))
            XCTAssertTrue(fm.fileExists(atPath: new.appendingPathComponent(keys[0]).path))
            try fm.removeItem(at: clash)
            let resumed = try await drive.movePlan(from: "Old")
            let remaining = try await drive.move(resumed, to: "New") { _, _ in }
            XCTAssertEqual(remaining, [])
            let count = try await drive.libraryCount(in: "New", folders: [title])
            XCTAssertEqual(count, 1)
            XCTAssertFalse(fm.fileExists(atPath: old.appendingPathComponent(manifestPath).path))
            for path in gameFiles {
                XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent(path)), Data("archive".utf8))
                XCTAssertFalse(fm.fileExists(atPath: new.appendingPathComponent(path).path))
            }
        }
    }

    func testBlockingArchivesRefusePreviewAndRetryBeforeMovingAnyFiles() async throws {
        try await withMoveFixture { drive, root in
            let title = "0100123456789ABC", other = "0100123456789ABD"
            let old = root.appendingPathComponent("Old"), new = root.appendingPathComponent("New")
            let fm = FileManager.default
            func write(_ data: Data, to path: String) throws -> URL {
                let file = old.appendingPathComponent(path)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file)
                return file
            }
            let raw = Data("archive".utf8)
            let sha = CloudArchiveInventory.hex(SHA256.hash(data: raw))
            let md5 = CloudArchiveInventory.hex(Insecure.MD5.hash(data: raw))
            let objectKey = "\(title)/app/\(sha).aar"
            let object = try write(raw, to: objectKey)
            let artifact = CloudGameManifest.Artifact(kind: .app, size: Int64(raw.count), sha256: sha, md5: md5,
                unpackedSize: 1, entryCount: 1, inventorySHA256: sha, engineCommit: nil, shaderChain: nil, options: [:])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(CloudGameManifest(version: 1, titleID: title, createdAt: .now, artifacts: [artifact]))
            let manifestKey = "\(title)/manifests/0000000000000001-\(CloudArchiveInventory.hex(SHA256.hash(data: data))).json"
            let manifest = try write(data, to: manifestKey)
            let plan = try await drive.movePlan(from: "Old", to: "New")
            XCTAssertEqual(plan.games, 1)
            for residue in [
                "\(other)/manifests/zz-invalid.json",
                "\(other)/MANIFESTS/zz-invalid.JSON",
                "\(other)/app/\(sha).aar",
                "Café [\(other)]/cache/\(sha)/empty",
            ] {
                let blocker = try write(Data(), to: residue)
                do {
                    _ = try await drive.movePlan(from: "Old", to: "New")
                    XCTFail("Preview offered to move despite \(residue)")
                } catch {
                    guard case .sourceResidue(let path)? = error as? CloudDriveFolders.MoveFailure else { throw error }
                    XCTAssertEqual(path.lowercased(), residue.lowercased())
                }
                do {
                    _ = try await drive.move(plan, to: "New") { _, _ in XCTFail("A blocked move must not start") }
                    XCTFail("An old plan must not ignore \(residue)")
                } catch {
                    guard case .sourceResidue(let path)? = error as? CloudDriveFolders.MoveFailure else { throw error }
                    XCTAssertEqual(path.lowercased(), residue.lowercased())
                }
                XCTAssertEqual(try Data(contentsOf: object), raw)
                XCTAssertEqual(try Data(contentsOf: manifest), data)
                XCTAssertTrue(try fm.contentsOfDirectory(atPath: new.path).isEmpty)
                XCTAssertEqual(try Data(contentsOf: blocker), Data())
                try fm.removeItem(at: blocker)
            }
            // Simulate the old mover having relocated the healthy files before reporting the residue.
            let blocker = try write(Data(), to: "\(other)/manifests/zz-invalid.json")
            for (source, key) in [(object, objectKey), (manifest, manifestKey)] {
                let destination = new.appendingPathComponent(key)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: source, to: destination)
            }
            do {
                _ = try await drive.move(plan, to: "New") { _, _ in XCTFail("Retry must still refuse the residue") }
                XCTFail("A partially completed old move must not activate")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("zz-invalid.json"))
                XCTAssertTrue(error.localizedDescription.contains("before retrying"))
            }
            let saved = root.appendingPathComponent("preserved.json")
            try fm.moveItem(at: blocker, to: saved)
            let conflicts = try await drive.move(plan, to: "New") { _, _ in }
            XCTAssertEqual(conflicts, [])
            XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent(objectKey)), raw)
            XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent(manifestKey)), data)
            XCTAssertEqual(try Data(contentsOf: saved), Data())
        }
    }

    func testJournalResumesWithRealFilesAfterEachProgressAndLostWriteReply() async throws {
        let cuts = ["progress-0", "reply-0", "progress-1", "reply-1", "progress-2", "reply-2", "progress-3"]
        for cut in cuts {
            try await withFakeDrive { fixture, root in
                let fm = FileManager.default
                let title = "0100123456789ABC"
                let sha = String(repeating: "a", count: 64)
                let keys = ["\(title)/app/\(sha).aar", "\(title)/cache/\(sha).aar",
                            "\(title)/manifests/0000000000000001-\(sha).json"]
                let old = root.appendingPathComponent("Old")
                let new = root.appendingPathComponent("New")
                func write(_ data: Data, to file: URL) throws {
                    try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: file)
                }
                var objects: [[String: Any]] = []
                for key in keys {
                    let file = old.appendingPathComponent(key)
                    let bytes = Data(key.utf8)
                    try write(bytes, to: file)
                    objects.append(["key": ["value": key], "size": bytes.count,
                                    "hashes": try CloudArchiveInventory.hashes(at: file)])
                }
                let unrelated = old.appendingPathComponent("GameFiles/fixture.nsp")
                try write(Data("unrelated".utf8), to: unrelated)
                let plan = try JSONDecoder().decode(CloudDriveFolders.MovePlan.self, from: JSONSerialization.data(withJSONObject: [
                    "source": "Old", "remote": "fixture", "games": 1, "bytes": 0,
                    "binding": ["account": "accountA", "sourceID": "oldID", "destinationID": "newID", "destination": "New"],
                    "entries": objects.enumerated().map { index, object in
                        ["file": object, "dependencies": index == 2 ? Array(objects.prefix(2)) : []]
                    },
                ]))
                let pending = LibraryMoveJournal.Pending(id: UUID(), request: .init(plan: plan, destination: "New"),
                                                        sourcesRoot: "Old/GameFiles")
                let journal = LibraryMoveJournal(in: root)
                XCTAssertNil(try journal.load())
                try journal.begin(pending)
                XCTAssertThrowsError(try journal.begin(pending), "A second start must not overwrite the plan")
                let lease = try journal.acquire()
                try withExtendedLifetime(lease) {
                    XCTAssertThrowsError(try LibraryMoveJournal(in: root).acquire())
                }
                fixture.loseReply = cut.hasPrefix("reply-") ? Int(cut.suffix(1)) : nil
                do {
                    _ = try await fixture.backend.move(plan, to: "New") { done, _ in
                        if cut == "progress-\(done)" { throw CancellationError() }
                    }
                    XCTFail("Expected the injected cut at \(cut)")
                } catch is CancellationError {
                    XCTAssertTrue(cut.hasPrefix("progress-"))
                } catch CloudLibraryFailure.offline {
                    XCTAssertTrue(cut.hasPrefix("reply-"))
                }
                // A fresh manager has only the disk snapshot and the two actual folder trees.
                let reopened = LibraryMoveJournal(in: root)
                let saved = try XCTUnwrap(reopened.load())
                XCTAssertEqual(saved, pending)
                fixture.loseReply = nil
                let conflicts = try await fixture.backend.move(saved.request.plan, to: saved.request.destination) { _, _ in }
                XCTAssertEqual(conflicts, [], cut)
                for key in keys {
                    XCTAssertFalse(fm.fileExists(atPath: old.appendingPathComponent(key).path), cut)
                    XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent(key)), Data(key.utf8), cut)
                }
                XCTAssertEqual(try Data(contentsOf: unrelated), Data("unrelated".utf8))
                let sealed = try reopened.markVerified(saved)
                XCTAssertEqual(try reopened.load(), sealed)
                try reopened.finish(sealed)
                XCTAssertNil(try reopened.load())
            }
        }
    }

    func testBoundMoveRejectsChangedIdentityAndConcurrentChangesWithoutWritingUnplannedFiles() async throws {
        for fault in ["account", "source", "destination", "unicode", "late-upload", "late-removal", "duplicate"] {
            try await withFakeDrive { fixture, root in
                let title = "0100123456789ABC"
                let key = "\(title)/app/\(String(repeating: "a", count: 64)).aar"
                let source = root.appendingPathComponent("Old/\(key)")
                let destination = root.appendingPathComponent("New/\(key)")
                let late = root.appendingPathComponent("Old/0100123456789ABD/app/\(String(repeating: "b", count: 64)).aar")
                let bytes = Data("archive".utf8)
                try fixture.write(bytes, to: source)
                let object: [String: Any] = ["key": ["value": key], "size": bytes.count,
                    "hashes": try CloudArchiveInventory.hashes(at: source)]
                let plan = try JSONDecoder().decode(CloudDriveFolders.MovePlan.self, from: JSONSerialization.data(withJSONObject: [
                    "source": fault == "unicode" ? "Café" : "Old", "remote": "fixture", "games": 1, "bytes": bytes.count,
                    "binding": ["account": "accountA", "sourceID": "oldID", "destinationID": "newID", "destination": "New"],
                    "entries": [["file": object, "dependencies": []]],
                ]))
                let journal = LibraryMoveJournal(in: root)
                let pending = LibraryMoveJournal.Pending(id: UUID(), request: .init(plan: plan, destination: "New"), sourcesRoot: nil)
                try journal.begin(pending)
                if fault == "late-upload" {
                    let absent = try await fixture.backend.originalSourcesRoot(plan, to: "New")
                    XCTAssertNil(absent)
                    try fixture.write(bytes, to: root.appendingPathComponent("Old/GameFiles/game.nsp"))
                    let present = try await fixture.backend.originalSourcesRoot(plan, to: "New")
                    XCTAssertEqual(present, "Old/GameFiles")
                }
                if fault == "account" { fixture.account = "accountB" }
                if fault == "source" { fixture.oldID = "replacementOld" }
                if fault == "destination" { fixture.newID = "replacementNew" }
                if fault == "unicode" { fixture.matchesDecomposedOnly = true }
                if fault == "duplicate" { try fixture.write(bytes, to: destination) }
                do {
                    let conflicts = try await fixture.backend.move(XCTUnwrap(journal.load()).request.plan, to: "New") { done, total in
                        if done == total && fault == "late-upload" { try fixture.write(bytes, to: late) }
                        if done == total && fault == "late-removal" {
                            try FileManager.default.moveItem(at: destination, to: root.appendingPathComponent("other-mac-copy"))
                        }
                    }
                    XCTAssertEqual(fault, "duplicate")
                    XCTAssertEqual(conflicts, [key])
                } catch let failure as CloudDriveFolders.MoveFailure {
                    switch (fault, failure) {
                    case ("account", .accountChanged), ("source", .foldersChanged), ("destination", .foldersChanged),
                         ("unicode", .foldersChanged), ("late-upload", .sourceNotEmpty), ("late-removal", .destinationChanged): break
                    default: XCTFail("Unexpected refusal \(fault): \(failure)")
                    }
                }
                XCTAssertEqual(try journal.load(), pending)
                if fault.hasPrefix("late-") {
                    XCTAssertEqual(fixture.writes, 1)
                    let preserved = fault == "late-upload" ? late : root.appendingPathComponent("other-mac-copy")
                    XCTAssertEqual(try Data(contentsOf: preserved), bytes)
                } else {
                    XCTAssertEqual(fixture.writes, 0)
                    XCTAssertEqual(try Data(contentsOf: source), bytes)
                }
            }
        }
    }

    func testMoveUsesSameConfigurationForAccountCheckAndMutation() async throws {
        try await withFakeDrive { fixture, root in
            let key = "0100123456789ABC/app/\(String(repeating: "a", count: 64)).aar"
            let source = root.appendingPathComponent("Old/\(key)")
            let bytes = Data("archive".utf8)
            try fixture.write(bytes, to: source)
            try Data("accountA".utf8).write(to: fixture.config)
            fixture.readAccountFromConfig = true
            let plan = try JSONDecoder().decode(CloudDriveFolders.MovePlan.self, from: JSONSerialization.data(withJSONObject: [
                "source": "Old", "remote": "fixture", "games": 1, "bytes": bytes.count,
                "binding": ["account": "accountA", "sourceID": "oldID", "destinationID": "newID", "destination": "New"],
                "entries": [["file": ["key": ["value": key], "size": bytes.count,
                                      "hashes": try CloudArchiveInventory.hashes(at: source)], "dependencies": []]],
            ]))
            do {
                let conflicts = try await fixture.backend.move(plan, to: "New") { done, _ in
                    if done == 0 { fixture.swapConfigAfterAccountCheck = true }
                }
                XCTAssertEqual(conflicts, [])
            } catch {
                XCTFail("The checked snapshot should still be usable: \(error)")
            }
            XCTAssertEqual(fixture.mutationAccount, "accountA")
            XCTAssertEqual(try String(contentsOf: fixture.config, encoding: .utf8), "accountB")
        }
    }

    func testMovePreviewRequiresAlreadyApprovedAccountAndSourceID() async throws {
        try await withFakeDrive { fixture, _ in
            let scope = CloudDriveScope(remote: "fixture", account: "accountA", library: .init(path: "Old", id: "oldID"))
            for fault in ["account", "folder"] {
                fixture.account = fault == "account" ? "accountB" : "accountA"
                fixture.oldID = fault == "folder" ? "otherOldID" : "oldID"
                do {
                    _ = try await fixture.backend.movePlan(from: "Old", to: "New", approved: scope)
                    XCTFail("A mismatched move must not reach the preview")
                } catch let error as CloudDriveFolders.MoveFailure {
                    switch (fault, error) {
                    case ("account", .accountChanged), ("folder", .foldersChanged): break
                    default: XCTFail("Unexpected failure: \(error)")
                    }
                }
            }
            XCTAssertEqual(fixture.recursiveListings, 0)
            fixture.oldID = "oldID"
            let plan = try await fixture.backend.movePlan(from: "Old", to: "New", approved: scope)
            try plan.verifyApproved(scope)
            XCTAssertEqual(try plan.destinationScope(reference: nil).library.id, "newID")
        }
    }

    func testCreationAndMoveRefuseTheFollowedFolderBeforeWriting() async throws {
        try await withFakeDrive { fixture, root in
            let key = "0100123456789ABC/app/\(String(repeating: "a", count: 64)).aar"
            let source = root.appendingPathComponent("Old/\(key)")
            let bytes = Data("archive".utf8)
            try fixture.write(bytes, to: source)
            let plan = try JSONDecoder().decode(CloudDriveFolders.MovePlan.self, from: JSONSerialization.data(withJSONObject: [
                "source": "Old", "remote": "fixture", "games": 1, "bytes": bytes.count,
                "binding": ["account": "accountA", "sourceID": "oldID", "destinationID": "newID", "destination": "New"],
                "entries": [["file": ["key": ["value": key], "size": bytes.count,
                                      "hashes": try CloudArchiveInventory.hashes(at: source)], "dependencies": []]],
            ]))
            for (folder, id) in [("Old", "oldID"), ("New", "newID")] {
                let drive = fixture.backend(reference: id)
                do {
                    try await drive.create("Subfolder", in: folder)
                    XCTFail("mkdir cannot run under the followed folder")
                } catch CloudLibraryFailure.referenceOverlap {}
                do {
                    _ = try await drive.move(plan, to: "New") { _, _ in XCTFail("An overlapping move cannot begin") }
                    XCTFail("moveid cannot move from or to the followed folder")
                } catch CloudLibraryFailure.referenceOverlap {}
                XCTAssertEqual(fixture.writes, 0)
                XCTAssertEqual(try Data(contentsOf: source), bytes)
            }
        }
    }

    private func withFakeDrive(_ body: (MoveDriveFixture, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Old", "New"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let fixture = MoveDriveFixture(root: root)
        try Data().write(to: fixture.config)
        try await body(fixture, root)
    }

    /// Stable inode-backed file IDs and actual file moves; never runs an external command or opens a real config.
    private final class MoveDriveFixture: @unchecked Sendable {
        let root: URL
        var account = "accountA", oldID = "oldID", newID = "newID"
        var matchesDecomposedOnly = false
        var loseReply: Int?
        var writes = 0
        var readAccountFromConfig = false
        var swapConfigAfterAccountCheck = false
        var mutationAccount: String?
        var recursiveListings = 0
        let fm = FileManager.default
        init(root: URL) { self.root = root }

        var config: URL { root.appendingPathComponent("empty.conf") }
        var backend: CloudDriveFolders {
            backend(reference: nil)
        }
        func backend(reference: String?) -> CloudDriveFolders {
            CloudDriveFolders(remote: "fixture", executable: URL(fileURLWithPath: "/synthetic/rclone"),
                              config: config, reference: reference, run: { [self] _, args, _ in try run(args) })
        }

        func write(_ data: Data, to file: URL) throws {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }

        func run(_ args: [String]) throws -> CommandResult {
            func configuredAccount() throws -> String {
                guard readAccountFromConfig else { return account }
                let path = args[try XCTUnwrap(args.lastIndex(of: "--config")) + 1]
                return try String(contentsOfFile: path, encoding: .utf8)
            }
            func node(_ target: String) throws -> URL {
                for (prefix, path) in [("fixture,root_folder_id=\(oldID):", "Old"),
                                       ("fixture,root_folder_id=\(newID):", "New"), ("fixture:", "")] {
                    if target.hasPrefix(prefix) {
                        let base = path.isEmpty ? root : root.appendingPathComponent(path)
                        let relative = String(target.dropFirst(prefix.count))
                        return relative.isEmpty ? base : base.appendingPathComponent(relative)
                    }
                }
                throw StorageBackendError.invalidKey
            }
            func id(_ file: URL, accountRoot: Bool = false) throws -> String {
                if accountRoot && file.lastPathComponent == "Old" { return oldID }
                if accountRoot && file.lastPathComponent == "New" { return newID }
                return "\(try CloudArchiveInventory.node(at: file).st_ino)"
            }
            if args[0] == "listremotes" {
                return .init(status: 0, stdout: #"[{"name":"fixture","type":"drive","source":"file"}]"#, stderr: "")
            }
            XCTAssertTrue(args.contains("--drive-shared-with-me=false"))
            if args[0] == "about" {
                XCTAssertEqual(args[1], "fixture,root_folder_id=,team_drive=:")
                let account = try configuredAccount()
                if swapConfigAfterAccountCheck {
                    swapConfigAfterAccountCheck = false
                    try Data("accountB".utf8).write(to: config, options: .atomic)
                }
                return .init(status: 0, stdout: "{}", stderr: "'root_folder_id = \(account)' - save this in the config to speed up startup")
            }
            if args[0] == "backend" && args[1] == "moveid" {
                mutationAccount = try configuredAccount()
                let source = try node(args[2])
                let target = try node(args[4])
                let children = try XCTUnwrap(fm.enumerator(at: source, includingPropertiesForKeys: nil))
                let object = try XCTUnwrap(children.compactMap { $0 as? URL }.first { (try? id($0)) == args[3] })
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: object, to: target)
                defer { writes += 1 }
                return writes == loseReply
                    ? .init(status: 1, stdout: "", stderr: "connection reset")
                    : .init(status: 0, stdout: "", stderr: "")
            }
            XCTAssertEqual(args[0], "lsjson", "No name-based writes are allowed")
            let parent = try node(args[1])
            guard fm.fileExists(atPath: parent.path) else { return .init(status: 3, stdout: "", stderr: "") }
            if matchesDecomposedOnly && parent.path == root.path {
                // The Drive path no longer has the bytes selected in the assistant.
                return .init(status: 0, stdout: #"[{"Name":"Café","ID":"oldID","IsDir":true},{"Name":"New","ID":"newID","IsDir":true}]"#, stderr: "")
            }
            let files: [URL]
            if args.contains("--recursive") {
                recursiveListings += 1
                files = (fm.enumerator(at: parent, includingPropertiesForKeys: nil)?.allObjects ?? []).compactMap { $0 as? URL }
            } else { files = try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) }
            let items: [[String: Any]] = try files.map { file in
                let relative = file.resolvingSymlinksInPath().pathComponents
                    .dropFirst(parent.resolvingSymlinksInPath().pathComponents.count).joined(separator: "/")
                let status = try CloudArchiveInventory.node(at: file)
                let directory = status.st_mode & S_IFMT == S_IFDIR
                return ["Name": file.lastPathComponent, "Path": relative, "IsDir": directory, "ID": try id(file, accountRoot: args[1] == "fixture:"),
                        "Size": status.st_size, "Hashes": directory ? [:] : try CloudArchiveInventory.hashes(at: file)]
            }.filter { !args.contains("--max-depth") || ($0["Path"] as! String).split(separator: "/").count <= 3 }
            return .init(status: 0, stdout: String(decoding: try JSONSerialization.data(withJSONObject: items), as: UTF8.self), stderr: "")
        }
    }

    private func withMoveFixture(_ body: (CloudDriveFolders, URL) async throws -> Void) async throws {
        guard let executable = RcloneStorageBackend.findExecutable() else { throw XCTSkip("rclone is not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        for name in ["Old", "New"] { try fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: false) }
        try await body(CloudDriveFolders(remote: ":local:", executable: executable, localRoot: root,
                                        config: root.appendingPathComponent("rclone.conf")), root)
    }

    func testListAndExplicitCreateWithLocalRemote() async throws {
        guard let executable = RcloneStorageBackend.findExecutable() else { throw XCTSkip("rclone is not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("file"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Existing"), withIntermediateDirectories: false)
        let drive = CloudDriveFolders(remote: ":local:", executable: executable, localRoot: root,
                                     config: root.appendingPathComponent("rclone.conf"))
        let ticket = UUID()
        let listing = try await drive.list("", ticket: ticket)
        XCTAssertEqual(listing.ticket, ticket)
        XCTAssertEqual(listing.names, ["Existing"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Arcane").path))
        try await drive.create("Arcane", in: "")
        try await drive.create("Arcane", in: "")
        let names = try await drive.list("", ticket: UUID()).names
        XCTAssertEqual(names, ["Arcane", "Existing"])
        try await drive.verifyAccess(to: "Arcane")
        let titleID = "0100123456789ABC"
        let count = try await drive.libraryCount(in: "Arcane", folders: [titleID])
        XCTAssertEqual(count, 0)
        let manifests = root.appendingPathComponent("Arcane/0100123456789ABC/manifests")
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: manifests.appendingPathComponent("invalid.json"))
        do {
            _ = try await drive.libraryCount(in: "Arcane", folders: [titleID])
            XCTFail("An invalid manifest cannot become a zero-game library")
        } catch CloudArchiveError.invalidManifest {}
        try FileManager.default.removeItem(at: manifests.appendingPathComponent("invalid.json"))
        let manifest = CloudGameManifest(version: 1, titleID: titleID, createdAt: Date(),
            artifacts: CloudArtifactKind.allCases.map {
                .init(kind: $0, size: 1, sha256: String(repeating: "a", count: 64),
                      md5: String(repeating: "b", count: 32), unpackedSize: 1, entryCount: 1,
                      inventorySHA256: String(repeating: "c", count: 64), engineCommit: nil, shaderChain: nil, options: [:])
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let staged = root.appendingPathComponent("fixture.json")
        try encoder.encode(manifest).write(to: staged)
        let checksum = try XCTUnwrap(CloudArchiveInventory.hashes(at: staged)["sha256"])
        try FileManager.default.moveItem(at: staged, to: manifests.appendingPathComponent("0000000000000001-\(checksum).json"))
        let found = try await drive.libraryCount(in: "Arcane", folders: [titleID, titleID.lowercased(), "Other"])
        XCTAssertEqual(found, 1)
    }

    func testLostMkdirResponseIsReconciledWithoutResubmitting() async throws {
        let calls = Calls()
        let drive = CloudDriveFolders(remote: "drive", executable: URL(fileURLWithPath: "/rclone")) { _, args, _ in
            if args.first == "listremotes" {
                return .init(status: 0, stdout: #"[{"name":"drive","type":"drive","source":"file"}]"#, stderr: "")
            }
            return await calls.run(args[0])
        }
        try await drive.create("Arcane", in: "")
        let commands = await calls.commands
        XCTAssertEqual(commands, ["lsjson", "mkdir", "lsjson"])
    }

    func testConfigReplacementRejectsExternalEditAndKeepsPreviousFileUntilApply() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let original = root.appendingPathComponent("rclone.conf")
        let first = Data("RCLONE_ENCRYPT_V0:\nfirst".utf8)
        let candidate = Data("RCLONE_ENCRYPT_V0:\ncandidate".utf8)
        let external = Data("RCLONE_ENCRYPT_V0:\nexternal".utf8)
        try first.write(to: original)
        let stale = try CloudDriveCredentialChange.stage(original)
        try candidate.write(to: stale.config)
        XCTAssertEqual(try Data(contentsOf: original), first)
        try external.write(to: original)
        XCTAssertThrowsError(try stale.apply())
        XCTAssertEqual(try Data(contentsOf: original), external)
        let fresh = try CloudDriveCredentialChange.stage(original)
        try candidate.write(to: fresh.config)
        try fresh.apply()
        XCTAssertEqual(try Data(contentsOf: original), candidate)
    }

    private actor Calls {
        var commands: [String] = []
        func run(_ command: String) -> CommandResult {
            commands.append(command)
            if command == "mkdir" { return .init(status: 1, stdout: "", stderr: "lost response") }
            return .init(status: 0, stdout: commands.count == 1 ? "[]" : #"[{"Name":"Arcane","IsDir":true}]"#, stderr: "")
        }
    }
}

private actor DiscoveryBackend: StorageBackend {
    static let title = "0100123456789ABC"
    let manifest: StorageObject
    private let data: Data
    private(set) var reads: [String] = []

    init(corrupt: Bool = false, folder: String = DiscoveryBackend.title) throws {
        let hash = String(repeating: "0", count: 64)
        let artifacts = CloudArtifactKind.allCases.map {
            CloudGameManifest.Artifact(kind: $0, size: 7, sha256: hash, md5: String(hash.prefix(32)),
                unpackedSize: 1, entryCount: 1, inventorySHA256: hash, engineCommit: nil, shaderChain: nil, options: [:])
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(CloudGameManifest(version: 1, titleID: Self.title, createdAt: Date(), artifacts: artifacts))
        data = corrupt ? Data(repeating: 0, count: bytes.count) : bytes
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        manifest = .init(key: .init("\(folder)/manifests/0000000000000001-\(digest).json"), size: Int64(bytes.count), hashes: [:])
    }

    func list(in prefix: StorageObjectKey) async throws -> [StorageObject] {
        reads.append(prefix.value)
        guard manifest.key.value.hasPrefix(prefix.value + "/") else { throw CloudLibraryFailure.folderMissing }
        return [manifest]
    }
    func get(_ key: StorageObjectKey, to destination: URL, progress: (@Sendable (StorageProgress) -> Void)?) async throws {
        reads.append(key.value)
        try data.write(to: destination)
    }
    func list() async throws -> [StorageObject] { throw StorageBackendError.invalidKey }
    func rootDirectories() async throws -> [String] { throw StorageBackendError.invalidKey }
    func put(_ source: URL, as object: StorageObject, progress: (@Sendable (StorageProgress) -> Void)?) async throws {
        XCTFail("Discovery must not write to the backend")
    }
    func delete(_ key: StorageObjectKey) async throws { XCTFail("Discovery must not delete from the backend") }
    func verify(_ object: StorageObject) async throws { throw StorageBackendError.invalidKey }
}
