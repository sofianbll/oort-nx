import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class CloudTransferQueueTests: XCTestCase {
    func testPersistedFreeKeepsTheToolItWasApprovedWith() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data(#"""
        {"version":1,"entries":[
          {"id":"00000000-0000-0000-0000-000000000001","action":{"free":{"_0":["app"]}},
           "token":"00000000-0000-0000-0000-000000000002","storage":"fixture:Games","toolIdentity":"approved-copy"}
        ]}
        """#.utf8)
        try data.write(to: file)
        let store = CloudTransferQueue(file: file)
        let loaded = await store.load()
        XCTAssertEqual(loaded.first?.action, .free([.app]))
        XCTAssertTrue(loaded.first?.permitsTool("approved-copy") == true)
        XCTAssertFalse(loaded.first?.permitsTool("different-copy") == true)
        XCTAssertFalse(loaded.first?.permitsTool(nil) == true)
        XCTAssertFalse(CloudTransferQueue.Entry(id: UUID(), action: .free([.app])).permitsTool("approved-copy"))
        store.save(loaded)
        await store.flush()
        XCTAssertTrue(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("approved-copy"))
    }

    func testToolIdentityChangesForADifferentExecutableOrMissingCopy() throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: directory) }
        let tool = directory.appendingPathComponent("rclone")
        let other = directory.appendingPathComponent("other-rclone")
        let original = URL(fileURLWithPath: "/usr/bin/true")
        try files.copyItem(at: original, to: tool)
        try files.copyItem(at: original, to: other)
        let approved = try XCTUnwrap(RcloneDownload.identity(of: tool))
        XCTAssertEqual(RcloneDownload.identity(of: tool), approved)
        XCTAssertNotEqual(RcloneDownload.identity(of: other), approved)
        try files.removeItem(at: tool)
        XCTAssertNil(RcloneDownload.identity(of: tool))
        try files.moveItem(at: other, to: tool)
        XCTAssertNotEqual(RcloneDownload.identity(of: tool), approved)
    }

    func testLoadsPersistedEntriesWithRemovedOffer() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data(#"""
        {"version":1,"entries":[
          {"id":"00000000-0000-0000-0000-000000000001","action":{"restore":{"_0":"app"}},
           "token":"00000000-0000-0000-0000-000000000002","storage":"fixture:Games",
           "offer":{"app":{"reference":true,"fingerprint":"fixture","bytes":1024,"required":2048,"update":false}}},
          {"id":"00000000-0000-0000-0000-000000000003","action":{"downloadSources":{}},
           "offer":{"rom":{"reference":false,"folder":"fixture","files":[],"bytes":1024,"required":2048}}}
        ]}
        """#.utf8)
        try data.write(to: file)
        let loaded = await CloudTransferQueue(file: file).load()
        XCTAssertEqual(loaded.map(\.isUserPaused), [false, false])
        XCTAssertEqual(loaded, [
            .init(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")), action: .restore(.app),
                  token: UUID(uuidString: "00000000-0000-0000-0000-000000000002"), storage: "fixture:Games"),
            .init(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003")), action: .downloadSources)
        ])
    }

    func testReopeningKeepsOnePausedHeadAndItsOriginalIdentity() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let scope = CloudDriveScope(remote: "fixture", account: "original-account",
                                    library: .init(path: "Games", id: "original-app-root"),
                                    sources: .init(path: "Games/Files", id: "original-files-root"))
        let original = CloudTransferQueue.Entry(id: UUID(), action: .restore(.app), token: UUID(),
                                                storage: "fixture:Games", sourceReference: "fixture:Reference",
                                                driveScope: scope, toolIdentity: "approved-copy")
        let waiting = CloudTransferQueue.Entry(id: UUID(), action: .downloadSources)
        var paused = original
        paused.isUserPaused = true
        let store = CloudTransferQueue(file: file)
        store.save([paused, waiting])
        await store.flush()

        let reopened = CloudTransferQueue(file: file)
        let loaded = await reopened.load()
        XCTAssertEqual(CloudTransferQueue.restoring(loaded, gameIDs: [original.id, waiting.id]), [paused, waiting])
        var resumed = try XCTUnwrap(loaded.first)
        XCTAssertTrue(resumed.isUserPaused)
        XCTAssertTrue(resumed.permitsTool("approved-copy"))
        XCTAssertFalse(resumed.permitsTool("different-copy"))
        resumed.isUserPaused = false
        XCTAssertEqual(resumed, original)
        reopened.save([resumed, waiting])
        await reopened.flush()
        let reloaded = await CloudTransferQueue(file: file).load()
        XCTAssertEqual(reloaded, [original, waiting])
    }

    func testRejectsInvalidPauseMarkersWithoutReplayingThoseEntries() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data(#"""
        {"version":1,"entries":[
          {"id":"00000000-0000-0000-0000-000000000001","action":{"restore":{"_0":"app"}},
           "token":"00000000-0000-0000-0000-000000000011","storage":"fixture:Games","userPaused":true},
          {"id":"00000000-0000-0000-0000-000000000002","action":{"uploadSources":{}},
           "token":"00000000-0000-0000-0000-000000000012","storage":"fixture:Games","userPaused":true},
          {"id":"00000000-0000-0000-0000-000000000003","action":{"free":{"_0":["app"]}},
           "token":"00000000-0000-0000-0000-000000000013","storage":"fixture:Games","userPaused":true},
          {"id":"00000000-0000-0000-0000-000000000004","action":{"downloadSources":{}},
           "token":"00000000-0000-0000-0000-000000000014","storage":"fixture:Files","userPaused":true},
          {"id":"00000000-0000-0000-0000-000000000005","action":{"upload":{}},"userPaused":"true"},
          {"id":"00000000-0000-0000-0000-000000000006","action":{"downloadSources":{}}}
        ]}
        """#.utf8)
        try data.write(to: file)
        let loaded = await CloudTransferQueue(file: file).load()
        XCTAssertEqual(loaded.map(\.id.uuidString), [
            "00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000006"
        ])
    }

    func testNetworkFailureDefersButInvalidContentDoesNot() {
        XCTAssertTrue(CloudTransferQueue.waitsForConnection(after: URLError(.notConnectedToInternet)))
        XCTAssertTrue(CloudTransferQueue.waitsForConnection(after: StorageBackendError.backendUnavailable))
        XCTAssertFalse(CloudTransferQueue.waitsForConnection(after: StorageBackendError.hashMismatch))
        XCTAssertFalse(CloudTransferQueue.waitsForConnection(after: CancellationError()))
        XCTAssertFalse(CloudTransferQueue.waitsForConnection(after: CloudLibraryFailure.volumeFull("Fixture")))
        XCTAssertFalse(CloudTransferQueue.waitsForConnection(after: CloudLibraryFailure.quotaFull))
    }
    func testQueueSaveFailureReportsOnceAndLaterSnapshotsStillWrite() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder)
        let store = CloudTransferQueue(file: folder.appendingPathComponent("queue.json"))
        let notice = expectation(description: "One nonfatal queue error")
        notice.assertForOverFulfill = true
        let report: @Sendable (CloudLibraryFailure) -> Void = {
            XCTAssertEqual($0, .queueNotSaved)
            XCTAssertEqual($0.action, .dismiss)
            notice.fulfill()
        }
        let entry = CloudTransferQueue.Entry(id: UUID(), action: .downloadSources)
        store.save([entry], onFailure: report)
        store.save([], onFailure: report)
        await store.flush()
        await fulfillment(of: [notice], timeout: 2)
        try FileManager.default.removeItem(at: folder)
        store.save([entry], onFailure: report)
        await store.flush()
        let loaded = await store.load()
        XCTAssertEqual(loaded, [entry])
    }

    func testQuitDecisionWaitsForConfirmationAndQueueCleanup() {
        XCTAssertEqual(CloudQuitDecision.resolve(isWorking: true, hasQueueWrites: true), .confirm)
        XCTAssertEqual(CloudQuitDecision.resolve(isWorking: true, relaunchScheduled: true), .cancel)
        XCTAssertEqual(CloudQuitDecision.resolve(hasQueueWrites: true), .flush)
        XCTAssertEqual(CloudQuitDecision.resolve(isWorking: true, isQuitting: true), .cancel)
        XCTAssertEqual(CloudQuitDecision.resolve(hasQueueWrites: true, isQuitting: true), .cancel)
        XCTAssertEqual(CloudQuitDecision.resolve(isWorking: true, hasQueueWrites: true,
                                                 isQuitting: true, cleanupComplete: true), .quit)
        XCTAssertEqual(CloudQuitDecision.resolve(), .quit)
    }

    func testRoundTripKeepsInterruptedTransferFirstAndFiltersMissingGames() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CloudTransferQueue(file: folder.appendingPathComponent("queue.json"))
        let active = CloudTransferQueue.Entry(id: UUID(), action: .upload(nil), token: UUID(), storage: "fixture:Games")
        let missing = CloudTransferQueue.Entry(id: UUID(), action: .restore(.app))
        let waiting = CloudTransferQueue.Entry(id: UUID(), action: .free([.app, .cache, .sources]))
        let entries = [active, missing, waiting, active]
        store.save([missing])
        store.save(entries)
        await store.flush()
        let loaded = await store.load()
        XCTAssertEqual(loaded, entries)
        XCTAssertEqual(CloudTransferQueue.restoring(loaded, gameIDs: [active.id, waiting.id]), [active, waiting])
    }

    func testInvalidAndFutureFilesLoadEmptyWithoutBeingOverwritten() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        for text in ["not JSON", #"{"version":2,"entries":[]}"#] {
            let store = CloudTransferQueue(file: file)
            let data = Data(text.utf8)
            try data.write(to: file)
            let loaded = await store.load()
            XCTAssertEqual(loaded, [])
            store.save([.init(id: UUID(), action: .restore(.app))])
            await store.flush()
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
    }

    func testResumedFreeOnlyKeepsItemsStillSafeToRemove() {
        let action = CloudLibraryAction.free([.app, .cache, .sources])
        XCTAssertEqual(action.resumableFree(synchronized: [.cache]), .free([.cache]))
        XCTAssertNil(action.resumableFree(synchronized: []))
    }
}
