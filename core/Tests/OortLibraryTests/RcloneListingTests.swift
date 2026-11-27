import XCTest
@testable import OortLibrary

/// A Drive kept in memory, answering the remote control calls a listing makes. Counts what is asked.
actor ListingDrive {
    struct Node { var id: String, name: String, parent: String, folder: Bool, size: Int64 = -1, md5: String? = nil, body = Data() }
    private(set) var nodes: [Node] = []
    private(set) var calls: [String] = []
    private(set) var running = 0, widest = 0
    var groups = true
    var failure: Error?
    var silent = false
    private var gates: [CheckedContinuation<Void, Never>] = []
    var holds = false

    func add(_ name: String, in parent: String, id: String, folder: Bool = true, body: Data = Data()) {
        nodes.append(.init(id: id, name: name, parent: parent, folder: folder, size: folder ? -1 : Int64(body.count),
                           md5: folder ? nil : "0123456789abcdef0123456789abcdef", body: body))
    }
    func rename(_ id: String, to name: String) { nodes[nodes.firstIndex { $0.id == id }!].name = name }
    func set(groups: Bool) { self.groups = groups }
    func set(failure: Error?) { self.failure = failure }
    func set(silent: Bool) { self.silent = silent }
    func hold() { holds = true }
    func release() { holds = false; gates.forEach { $0.resume() }; gates = [] }
    func forget() { calls = [] }
    func count(_ prefix: String = "") -> Int { calls.filter { $0.hasPrefix(prefix) }.count }

    func answer(_ operation: String, _ data: Data) async throws -> String? {
        let p = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let fs = (p["fs"] ?? p["srcFs"]) as! String
        let parent = fs == "fixture:" ? "" : String(fs.dropFirst("fixture,root_folder_id=".count).dropLast())
        calls.append(operation == "backend/command" ? "group" : "\(operation == "operations/list" ? "list" : operation) \(parent)")
        running += 1
        widest = max(widest, running)
        defer { running -= 1 }
        if holds { await withCheckedContinuation { gates.append($0) } }
        try Task.checkCancellation()
        if let failure { throw failure }
        if silent { return nil }
        switch operation {
        case "operations/list":
            let rows = nodes.filter { $0.parent == parent }.map { node -> [String: Any] in
                var row: [String: Any] = ["Path": node.name, "Name": node.name, "ID": node.id, "IsDir": node.folder, "Size": node.size]
                if let md5 = node.md5 { row["Hashes"] = ["md5": md5] }
                return row
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["list": rows]), as: UTF8.self)
        case "backend/command":
            guard groups else { return nil }
            let query = (p["arg"] as! [String])[0]
            let rows = nodes.filter { query.contains("'\($0.parent)' in parents") && !$0.parent.isEmpty }.map { node -> [String: Any] in
                var row: [String: Any] = ["id": node.id, "name": node.name, "parents": [node.parent],
                                          "mimeType": node.folder ? "application/vnd.google-apps.folder" : "application/octet-stream"]
                if !node.folder { row["size"] = String(node.size); row["md5Checksum"] = node.md5 }
                return row
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["result": rows]), as: UTF8.self)
        case "operations/copyfile":
            guard let node = nodes.first(where: { $0.parent == parent && $0.name == p["srcRemote"] as? String }) else { throw StorageBackendError.notFound }
            let folder = URL(fileURLWithPath: String((p["dstFs"] as! String).dropFirst(":local:".count)))
            try node.body.write(to: folder.appendingPathComponent(p["dstRemote"] as! String))
            return "{}"
        default: return nil
        }
    }
}

final class RcloneListingTests: XCTestCase {
    private let scope = CloudDriveScope(remote: "fixture", account: "AccountID", library: .init(path: "Games", id: "LibraryID"),
                                        sources: .init(path: "Games/GameFiles", id: "SourcesID"))

    private func drive() async -> ListingDrive {
        let drive = ListingDrive()
        await drive.add("Games", in: "", id: "LibraryID")
        await drive.add("GameFiles", in: "LibraryID", id: "SourcesID")
        for i in 0..<60 {
            await drive.add("Game \(i)", in: "LibraryID", id: "Game\(i)")
            await drive.add("manifests", in: "Game\(i)", id: "Manifests\(i)")
            await drive.add("one.json", in: "Manifests\(i)", id: "File\(i)", folder: false, body: Data("body \(i)".utf8))
        }
        return drive
    }

    private func listing(_ drive: ListingDrive, account: String = "AccountID", incomplete: @escaping @Sendable () -> Bool = { false })
        -> RcloneListing {
        RcloneListing(.init(remote: "fixture", account: account, call: { try await drive.answer($0, $1) }, incomplete: incomplete))
    }

    func testEachFolderIsReadOnceByItsIDAndSixtyFoldersTakeTwoRequests() async throws {
        let drive = await drive()
        let listing = listing(drive)
        try await listing.verify(scope)
        let names = try await listing.entries(in: "", under: "LibraryID").filter { $0.name.hasPrefix("Game ") }.map(\.name)
        XCTAssertEqual(names.count, 60)
        await drive.forget()
        await listing.warm(names, under: "LibraryID")
        for (i, name) in names.enumerated() {
            let entries = try await listing.entries(in: name, under: "LibraryID")
            XCTAssertEqual(entries.map(\.id), ["Manifests\(i)"])
            XCTAssertEqual(entries.map(\.isDirectory), [true])
        }
        var calls = await drive.calls
        XCTAssertEqual(calls, ["group", "group"], "fifty folders a request")
        await listing.warm(names.map { $0 + "/manifests" }, under: "LibraryID")
        let file = try await listing.entries(in: "Game 7/manifests", under: "LibraryID")
        XCTAssertEqual(file.map(\.name), ["one.json"])
        XCTAssertEqual(file.map(\.size), [6])
        XCTAssertEqual(file.first?.md5, "0123456789abcdef0123456789abcdef")
        XCTAssertFalse(file[0].isDirectory)
        calls = await drive.calls
        XCTAssertEqual(calls.count, 4)
    }

    func testIdenticalReadsShareOneRequest() async throws {
        let drive = await drive()
        let listing = listing(drive)
        await drive.hold()
        let reads = (0..<12).map { _ in Task { try await listing.entries(in: "", under: "LibraryID").count } }
        while await drive.count() == 0 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(20))
        await drive.release()
        for read in reads { _ = try await read.value }
        let count = await drive.count()
        XCTAssertEqual(count, 1)
    }

    func testAnOlderRcloneReadsEachFolderOnItsOwn() async throws {
        let drive = await drive()
        await drive.set(groups: false)
        let listing = listing(drive)
        await listing.warm(["Game 1", "Game 2", "Game 3"], under: "LibraryID")
        let one = try await listing.entries(in: "Game 1", under: "LibraryID"), three = try await listing.entries(in: "Game 3", under: "LibraryID")
        XCTAssertEqual([one, three].flatMap { $0 }.map(\.id), ["Manifests1", "Manifests3"])
        await listing.warm(["Game 4", "Game 5"], under: "LibraryID")
        _ = try await listing.entries(in: "Game 4", under: "LibraryID")
        let groups = await drive.count("group")
        XCTAssertEqual(groups, 1, "an unsupported request is not repeated")
    }

    func testScopeIsProvedBeforeAndAfter() async throws {
        let drive = await drive()
        await assertFailure(.scopeChanged) { try await self.listing(drive, account: "OtherAccount").verify(self.scope) }
        var calls = await drive.calls
        XCTAssertEqual(calls, [], "another account is refused before any folder is read")

        let reading = listing(drive)
        try await reading.verify(scope)
        try await reading.confirm()
        await drive.rename("LibraryID", to: "Old games")
        await drive.forget()
        try await reading.confirm()
        calls = await drive.calls
        XCTAssertEqual(calls, [], "nothing was read since the last proof")
        _ = try await reading.entries(in: "Game 1", under: "LibraryID")
        await assertFailure(.scopeChanged) { try await reading.confirm() }
        await assertFailure(.scopeChanged) { try await self.listing(drive).verify(self.scope) }
        await drive.rename("LibraryID", to: "Games")
        await drive.add("Games", in: "", id: "Second")
        await assertFailure(.scopeChanged) { try await self.listing(drive).verify(self.scope) }

        let sources = await self.drive()
        let second = listing(sources)
        try await second.verify(scope)
        await sources.rename("SourcesID", to: "Elsewhere")
        await assertFailure(.scopeChanged) { try await second.confirm() }
        let early = ListingDrive()
        let unproved = listing(early)
        await assertFailure(.scopeChanged) { try await unproved.confirm() }
        calls = await early.calls
        XCTAssertEqual(calls, [])
    }

    func testConfirmingTakesOneRoundTripAndReportsAnIncompleteSearch() async throws {
        let drive = await drive()
        let flag = Flag()
        let reading = listing(drive, incomplete: { flag.value })
        try await reading.verify(scope)
        _ = try await reading.entries(in: "Game 1", under: "LibraryID")
        await drive.forget()
        await drive.hold()
        let task = Task { try await reading.confirm() }
        while await drive.running < 1 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(30))
        let together = await drive.count()
        XCTAssertEqual(together, 2, "both parents are asked at once")
        await drive.release()
        task.cancel()
        _ = try? await task.value
        flag.set()
        _ = try await reading.entries(in: "Game 2", under: "LibraryID")
        do { try await reading.confirm(); XCTFail("An incomplete search was accepted") }
        catch { XCTAssertEqual(error as? StorageBackendError, .invalidResponse) }
    }

    func testAmbiguousNamesAreRefusedAndMissingOnesAreMissing() async throws {
        let drive = await drive()
        await drive.add("Game 1", in: "LibraryID", id: "Twin")
        await drive.add("Game\u{301} x", in: "LibraryID", id: "Accent")
        let listing = listing(drive)
        await assertFailure(.incomplete) { _ = try await listing.entries(in: "Game 1", under: "LibraryID") }
        await assertFailure(.folderMissing) { _ = try await listing.entries(in: "Nothing", under: "LibraryID") }
        await assertFailure(.incomplete) { _ = try await listing.entries(in: "Game 2/manifests/one.json", under: "LibraryID") }
        let twins = try await listing.entries(in: "", under: "LibraryID").filter { $0.name == "Game 1" }
        XCTAssertEqual(twins.count, 2, "the caller still sees both")
    }

    func testANameDriveSpellsDifferentlyIsReadFromItsOwnFolder() async throws {
        let drive = await drive()
        await drive.add("Left/Right", in: "Game1", id: "Slash", folder: false, body: Data("x".utf8))
        let listing = listing(drive)
        await listing.warm(["Game 1", "Game 2"], under: "LibraryID")
        _ = try await listing.entries(in: "Game 1", under: "LibraryID")
        _ = try await listing.entries(in: "Game 2", under: "LibraryID")
        let calls = await drive.calls
        XCTAssertEqual(calls.filter { $0 == "list Game1" }.count, 1)
        XCTAssertEqual(calls.filter { $0 == "list Game2" }.count, 0)
    }

    func testAFailureIsNotKeptAndAnUnavailableRcloneSaysSo() async throws {
        let drive = await drive()
        let listing = listing(drive)
        await drive.set(failure: CloudLibraryFailure.offline)
        await assertFailure(.offline) { _ = try await listing.entries(in: "", under: "LibraryID") }
        await drive.set(failure: nil)
        let back = try await listing.entries(in: "", under: "LibraryID")
        XCTAssertFalse(back.isEmpty)
        await drive.set(silent: true)
        do { _ = try await listing.entries(in: "Game 1", under: "LibraryID"); XCTFail("Expected a fallback") }
        catch { XCTAssertTrue(error is RcloneListing.Unavailable) }
    }

    func testCancellingStopsEveryReadAndRefusesMore() async throws {
        let drive = await drive()
        let listing = listing(drive)
        await drive.hold()
        let read = Task { try await listing.entries(in: "", under: "LibraryID") }
        while await drive.running < 1 { await Task.yield() }
        await listing.cancel()
        await drive.release()
        do { _ = try await read.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        do { _ = try await listing.entries(in: "", under: "LibraryID"); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testDownloadReadsTheListedFileByItsFolderID() async throws {
        let drive = await drive()
        let listing = listing(drive)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("listing-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("rc")
        try await listing.download("Game 5/manifests/one.json", under: "LibraryID", to: file)
        XCTAssertEqual(try Data(contentsOf: file), Data("body 5".utf8))
        let calls = await drive.calls
        XCTAssertEqual(calls.last, "operations/copyfile Manifests5")
        do { try await listing.download("Game 5/manifests/other.json", under: "LibraryID", to: file); XCTFail("Missing") }
        catch { XCTAssertEqual(error as? StorageBackendError, .notFound) }
    }

    func testAReadingBackendAnswersListingsWithoutACommandAndRefusesEveryWrite() async throws {
        let drive = await drive()
        let commands = Commands()
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            await commands.add(args)
            throw StorageBackendError.invalidConfiguration
        }.scoped(scope)
        let reading = backend.reading(listing(drive))
        let roots = try await reading.archiveEntries(in: "")
        XCTAssertEqual(roots.filter(\.isDirectory).count, 61)
        XCTAssertEqual(roots.first { $0.name == "Game 3" }?.id, "Game3")
        let manifests = try await reading.archiveEntries(in: "Game 3/manifests")
        XCTAssertEqual(manifests.map(\.object.key.value), ["Game 3/manifests/one.json"])
        XCTAssertEqual(manifests.map(\.object.size), [6])
        let directory = try await reading.atRoot("Games/GameFiles").directoryEntries(in: "")
        XCTAssertEqual(directory.count, 0)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("listing-\(UUID())")
        try await reading.get(.init("Game 4/manifests/one.json"), to: file)
        XCTAssertEqual(try Data(contentsOf: file), Data("body 4".utf8))
        try FileManager.default.removeItem(at: file)
        for write in [{ try await reading.delete(.init("Game 4/manifests/one.json")) },
                      { try await reading.put(URL(fileURLWithPath: "/etc/hosts"), as: .init(key: .init("a/b"), size: 1, hashes: ["sha256": String(repeating: "a", count: 64)])) },
                      { try await reading.copyFiles(["a"], from: URL(fileURLWithPath: "/tmp"), to: .init("a"), reusing: nil, progress: nil) }]
            as [() async throws -> Void] {
            do { try await write(); XCTFail("A reading backend wrote") }
            catch { XCTAssertEqual(error as? StorageBackendError, .invalidConfiguration) }
        }
        let ran = await commands.all
        XCTAssertEqual(ran, [], "nothing but the listing was asked")
        let outside = backend.atRoot("Elsewhere").reading(listing(drive))
        await assertFailure(.scopeChanged) { _ = try await outside.archiveEntries(in: "") }
    }

    private actor Commands { var all: [[String]] = []; func add(_ args: [String]) { all.append(args) } }
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock(); private var on = false
        var value: Bool { lock.withLock { on } }
        func set() { lock.withLock { on = true } }
    }

    private func assertFailure(_ expected: CloudLibraryFailure, file: StaticString = #filePath, line: UInt = #line,
                               _ work: () async throws -> Void) async {
        do { try await work(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? CloudLibraryFailure, expected, "\(error)", file: file, line: line) }
    }
}
