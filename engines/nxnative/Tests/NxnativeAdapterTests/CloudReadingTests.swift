import CryptoKit
import XCTest
@testable import OortLibrary
@testable import NxnativeAdapter

/// The library as a refresh reads it: few requests, the same refusals, and nothing a transfer could use.
final class CloudReadingTests: XCTestCase {
    private actor Drive {
        struct Node { let id: String, name: String, parent: String, body: Data? }
        private var nodes: [Node] = []
        private(set) var calls: [String] = []
        var offline = false

        func folder(_ name: String, in parent: String, id: String) { nodes.append(.init(id: id, name: name, parent: parent, body: nil)) }
        func file(_ name: String, in parent: String, body: Data) {
            nodes.append(.init(id: "File\(nodes.count)", name: name, parent: parent, body: body))
        }
        func remove(_ id: String) { nodes.removeAll { $0.id == id } }
        func replace(_ name: String, body: Data) {
            let index = nodes.firstIndex { $0.name == name }!
            nodes[index] = .init(id: nodes[index].id, name: name, parent: nodes[index].parent, body: body)
        }
        func forget() { calls = [] }
        func goOffline() { offline = true }

        func answer(_ operation: String, _ data: Data) throws -> String? {
            let p = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let fs = (p["fs"] ?? p["srcFs"]) as! String
            let parent = fs == "fixture:" ? "" : String(fs.dropFirst("fixture,root_folder_id=".count).dropLast())
            calls.append(operation)
            if offline { throw CloudLibraryFailure.offline }
            if operation == "operations/copyfile" {
                let body = nodes.first { $0.parent == parent && $0.name == p["srcRemote"] as? String }!.body!
                try body.write(to: URL(fileURLWithPath: String((p["dstFs"] as! String).dropFirst(7))).appendingPathComponent(p["dstRemote"] as! String))
                return "{}"
            }
            if operation == "operations/list" {
                let rows = nodes.filter { $0.parent == parent }.map {
                    ["Path": $0.name, "Name": $0.name, "ID": $0.id, "IsDir": $0.body == nil, "Size": $0.body?.count ?? -1,
                     "Hashes": $0.body.map { ["md5": CloudArchiveInventory.hex(Insecure.MD5.hash(data: $0))] } ?? [:]] as [String: Any]
                }
                return String(decoding: try JSONSerialization.data(withJSONObject: ["list": rows]), as: UTF8.self)
            }
            let query = (p["arg"] as! [String])[0]
            let rows = nodes.filter { query.contains("'\($0.parent)' in parents") }.map { node -> [String: Any] in
                var row: [String: Any] = ["id": node.id, "name": node.name, "parents": [node.parent],
                                          "mimeType": node.body == nil ? "application/vnd.google-apps.folder" : "application/octet-stream"]
                if let body = node.body { row["size"] = String(body.count); row["md5Checksum"] = CloudArchiveInventory.hex(Insecure.MD5.hash(data: body)) }
                return row
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["result": rows]), as: UTF8.self)
        }
    }

    private let scope = CloudDriveScope(remote: "fixture", account: "AccountID", library: .init(path: "Games", id: "LibraryID"),
                                        sources: .init(path: "Games/GameFiles", id: "SourcesID"))
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("reading-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func title(_ i: Int) -> String { String(format: "0100000000%03d000", i) }

    private func record(_ i: Int) throws -> (name: String, data: Data) {
        let entries = [CloudArtifactFiles.Entry(path: "Contents/Info.plist", size: 3, md5: "d41d8cd98f00b204e9800998ecf8427e")]
        let digest = try CloudArtifactFiles.digest(entries)
        let artifact = CloudGameManifest.Artifact(kind: .app, unpackedSize: 3, entryCount: 1, inventorySHA256: digest,
            engineCommit: nil, shaderChain: nil, options: [:],
            files: .init(folder: "Game \(i) [\(title(i))]/app/\(digest)/Game.app", entries: entries))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(CloudGameManifest(version: 2, titleID: title(i), createdAt: Date(timeIntervalSince1970: 1_760_000_000),
                                                        artifacts: [artifact]))
        return ("0000000000000001-\(CloudArchiveInventory.hex(SHA256.hash(data: data))).json", data)
    }

    private func drive(_ games: Int) async throws -> Drive {
        let drive = Drive()
        await drive.folder("Games", in: "", id: "LibraryID")
        await drive.folder("GameFiles", in: "LibraryID", id: "SourcesID")
        for i in 0..<games {
            await drive.folder("Game \(i) [\(title(i))]", in: "LibraryID", id: "Game\(i)")
            await drive.folder("manifests", in: "Game\(i)", id: "Records\(i)")
            await drive.folder("app", in: "Game\(i)", id: "App\(i)")
            let record = try record(i)
            await drive.file(record.name, in: "Records\(i)", body: record.data)
            await drive.folder("Game \(i) [\(title(i))]", in: "SourcesID", id: "Files\(i)")
            await drive.file("Game \(i) [\(title(i))][v0].nsp", in: "Files\(i)", body: Data("nsp".utf8))
        }
        return drive
    }

    private func read(_ drive: Drive, records: CloudManifestCache) throws -> (listing: RcloneListing, archive: CloudGameArchive, sources: CloudGameSources) {
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            XCTFail("A command ran: \(args.prefix(2))")
            throw StorageBackendError.invalidConfiguration
        }.scoped(scope)
        let listing = RcloneListing(.init(remote: "fixture", account: "AccountID", call: { try await drive.answer($0, $1) }, incomplete: { false }))
        let archive = CloudGameArchive(backend: backend, trash: { _ in XCTFail("Trashed") }, records: records)
        return (listing, try XCTUnwrap(archive.reading(listing)),
                CloudGameSources(backend: backend, root: "Games/GameFiles", usesDefaultRoot: true, trash: { _ in XCTFail("Trashed") }).reading(listing))
    }

    func testFortyGamesTakeTheSameFewRequestsAsOneAndKeptRecordsAreNotReadAgain() async throws {
        var listings: [Int] = []
        for games in [1, 40] {
            let drive = try await drive(games)
            let records = CloudManifestCache(directory: folder.appendingPathComponent("\(games)"))
            for pass in 0..<2 {
                await drive.forget()
                let (listing, archive, sources) = try read(drive, records: records)
                try await listing.verify(scope)
                async let found = archive.latestManifestsForImport()
                async let discovered = sources.discover()
                let (result, discovery) = try await (found, discovered)
                try await listing.confirm()
                XCTAssertEqual(result.manifests.map(\.titleID), (0..<games).map(title))
                XCTAssertEqual(result.invalidTitles, [])
                XCTAssertEqual(discovery.games.map(\.titleID), (0..<games).map(title))
                for i in 0..<games {
                    let availability = try await archive.availability(.init(titleID: title(i), locations: [:]))
                    XCTAssertEqual(availability[.app]?.state, .cloudOnly)
                }
                let calls = await drive.calls
                XCTAssertEqual(calls.filter { $0 == "operations/copyfile" }.count, pass == 0 ? games : 0)
                if games == 40 { XCTAssertLessThanOrEqual(calls.filter { $0 != "operations/copyfile" }.count, 10) }
                listings.append(calls.filter { $0 != "operations/copyfile" }.count)
            }
        }
        XCTAssertEqual(listings[0], listings[1])
        XCTAssertEqual(listings[2], listings[3])
    }

    func testAReplacedRecordIsReadAgainAndADamagedCopyIsIgnored() async throws {
        let drive = try await drive(1)
        let kept = folder.appendingPathComponent("records")
        let records = CloudManifestCache(directory: kept)
        _ = try await read(drive, records: records).archive.latest(titleID: title(0))
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: kept, includingPropertiesForKeys: nil).first)
        var damaged = try Data(contentsOf: file)
        damaged[10] ^= 1
        try damaged.write(to: file)
        await drive.forget()
        let again = try await read(drive, records: .init(directory: kept)).archive.latest(titleID: title(0))
        XCTAssertEqual(again?.titleID, title(0))
        let calls = await drive.calls
        XCTAssertEqual(calls.filter { $0 == "operations/copyfile" }.count, 1)

        // Same name, same size, other bytes: neither the kept copy nor the record already read may hide it.
        let name = try record(0).name
        var changed = try record(0).data
        changed[changed.count - 2] ^= 1
        await drive.replace(name, body: changed)
        do { _ = try await read(drive, records: records).archive.latest(titleID: title(0)); XCTFail("A kept copy hid changed bytes") }
        catch { XCTAssertEqual(error as? CloudArchiveError, .invalidManifest) }
        await drive.replace(name, body: Data("{}".utf8))
        do { _ = try await read(drive, records: .init(directory: folder.appendingPathComponent("empty"))).archive.latest(titleID: title(0)); XCTFail("Accepted") }
        catch { XCTAssertEqual(error as? CloudArchiveError, .invalidManifest) }
        do { _ = try await read(drive, records: records).archive.latest(titleID: title(0)); XCTFail("A kept copy hid a changed record") }
        catch { XCTAssertEqual(error as? CloudArchiveError, .invalidManifest) }
    }

    func testKeptRecordsStayBounded() throws {
        let records = CloudManifestCache(directory: folder.appendingPathComponent("records"), capacity: 250)
        for i in 0..<5 {
            let data = Data(repeating: UInt8(i), count: 100)
            records.store(data, sha256: CloudArchiveInventory.hex(SHA256.hash(data: data)))
            Thread.sleep(forTimeInterval: 0.02)
        }
        func kept(_ byte: UInt8, count: Int = 100) -> Data? {
            let data = Data(repeating: byte, count: count)
            return records.data(CloudArchiveInventory.hex(SHA256.hash(data: data)), of: .init(key: .init("k"), size: Int64(count), hashes: [:]), limit: 1000)
        }
        XCTAssertNotNil(kept(4))
        XCTAssertNil(kept(0))
        records.store(Data(repeating: 9, count: 300), sha256: CloudArchiveInventory.hex(SHA256.hash(data: Data(repeating: 9, count: 300))))
        XCTAssertNil(kept(9, count: 300))
    }

    func testAnUnreadableGameIsLeftOutAndTheRestIsFound() async throws {
        let drive = try await drive(5)
        await drive.folder("manifests", in: "Game2", id: "Twin")
        await drive.file("broken.json", in: "Records4", body: Data("x".utf8))
        let (_, archive, _) = try read(drive, records: .init(directory: folder.appendingPathComponent("r")))
        let result = try await archive.latestManifestsForImport()
        XCTAssertEqual(result.manifests.map(\.titleID), [0, 1, 3].map(title))
        XCTAssertEqual(result.invalidTitles, [2, 4].map(title))
    }

    func testAnOutageStopsTheReadAndIsNotAnEmptyLibrary() async throws {
        let drive = try await drive(3)
        let (_, archive, sources) = try read(drive, records: .init(directory: folder.appendingPathComponent("r")))
        await drive.goOffline()
        do { _ = try await archive.latestManifestsForImport(); XCTFail("Empty") } catch { XCTAssertEqual(error as? CloudLibraryFailure, .offline) }
        do { _ = try await sources.discover(); XCTFail("Empty") } catch { XCTAssertEqual(error as? CloudLibraryFailure, .offline) }
    }

    func testAReadingDecidesAndWritesNothing() async throws {
        let drive = try await drive(1)
        let (_, archive, sources) = try read(drive, records: .init(directory: folder.appendingPathComponent("r")))
        let game = CloudArchiveGame(titleID: title(0), locations: [.app: folder.appendingPathComponent("Game.app")])
        await drive.forget()
        for attempt in [{ _ = try await archive.upload(game) }, { _ = try await archive.restore(.app, for: game) },
                        { _ = try await archive.free(.app, for: game, confirmed: true) }, { _ = try await archive.beginBuild(titleID: self.title(0)) },
                        { _ = try await archive.checkRebuild(game, sourcesAvailable: true, withoutCache: false) },
                        { try await sources.upload(folderName: "Game 0 [\(self.title(0))]", files: [], progress: nil) }] as [() async throws -> Void] {
            do { try await attempt(); XCTFail("A reading acted") }
            catch { XCTAssertEqual(error as? StorageBackendError, .invalidConfiguration, "\(error)") }
        }
        let calls = await drive.calls
        XCTAssertEqual(calls, [])
    }
}
