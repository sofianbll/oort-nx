import Foundation
import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class BuildQueueTests: XCTestCase {
    func testQueueWriteFailureIsReported() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([42]).write(to: root)
        let store = ActivityQueueFile<BuildRequest>(file: root.appendingPathComponent("queue.json"))
        let reported = expectation(description: "Queue snapshot could not be written")
        store.save([BuildRequest(gameID: UUID(), name: "Fixture")]) { reported.fulfill() }
        await fulfillment(of: [reported], timeout: 2)
        await store.flush()
        XCTAssertEqual(try Data(contentsOf: root), Data([42]))
    }
    func testVersionedBuildSnapshotRestoresInterruptedFirstAndIgnoresInvalidEntries() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ActivityQueueFile<BuildRequest>(file: file)
        let active = BuildRequest(gameID: UUID(), name: "Active", arguments: ["--allow-damaged"], rebuild: true)
        let queued = BuildRequest(gameID: UUID(), name: "Queued", withoutCache: true)
        store.save([active, queued])
        await store.flush()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        var invalid = entries[0]
        invalid["arguments"] = ["--output", "/not-allowed"]
        entries.insert(invalid, at: 1)
        entries.append(entries[0])
        json["entries"] = entries
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        let loaded = await ActivityQueueFile<BuildRequest>(file: file).load()
        let restored = BuildRequest.restoring(loaded)
        XCTAssertEqual(restored.map(\.id), [active.id, queued.id])
        XCTAssertTrue(restored.allSatisfy(\.localSourcesOnly))
        XCTAssertEqual(restored[0].arguments, active.arguments)
        XCTAssertTrue(restored[1].withoutCache)
    }

    func testResultsRetainLastOutcomeUntilClearedAndRetryKeepsTheWork() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ActivityQueueFile<ActivityHistory.Result>(file: file)
        var history = ActivityHistory()
        let request = BuildRequest(gameID: UUID(), name: "Fixture", withoutCache: true)
        history.record(id: request.id, job: .build(request), name: request.name, outcome: .failed("Fixture failure"))
        let other = UUID()
        history.record(id: other, job: .cloud(.init(id: UUID(), action: .upload(.app))), name: nil, outcome: .cancelled)
        store.save(history.entries)
        await store.flush()
        let saved = await ActivityQueueFile<ActivityHistory.Result>(file: file).load()
        history = ActivityHistory()
        history.restore(saved)
        XCTAssertFalse(history.retry(request.id) { _ in false })
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertTrue(history.retry(request.id) { result in
            result.job == .build(request)
        })
        history.record(id: request.id, job: .build(request), name: request.name, outcome: .succeeded)
        XCTAssertEqual(history.entries.map(\.outcome), [.succeeded, .cancelled])
        XCTAssertFalse(history.retry(request.id) { _ in XCTFail("Success cannot retry"); return true })
        history.clear(request.id)
        XCTAssertEqual(history.entries.map(\.id), [other])
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testRestoredBuildRequiresLocalSourcesAndRebuildRequiresTheApp() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("fixture.nsp")
        let app = folder.appendingPathComponent("fixture.app")
        var game = PortedGame(name: "Fixture", url: app, platform: .macApp, sizeBytes: 1, modificationDate: Date())
        game.sources = [.init(url: source, kind: .base, sizeBytes: 1)]
        let build = BuildRequest(gameID: game.id, name: game.name)
        let rebuild = BuildRequest(gameID: game.id, name: game.name, rebuild: true)
        XCTAssertFalse(build.canResumeAutomatically(game))
        try Data([0]).write(to: source)
        XCTAssertTrue(build.canResumeAutomatically(game))
        XCTAssertFalse(rebuild.canResumeAutomatically(game))
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
        XCTAssertTrue(rebuild.canResumeAutomatically(game))
        try FileManager.default.removeItem(at: source)
        XCTAssertFalse(rebuild.canResumeAutomatically(game))
    }

    func testOnlyOneRequestPerGameAndCancellationKeepsFIFO() {
        let active = UUID(), first = UUID(), cancelled = UUID(), last = UUID()
        let queue = BuildQueue<String>()
        XCTAssertFalse(queue.enqueue("active", id: active, activeID: active))
        XCTAssertTrue(queue.enqueue("first", id: first, activeID: active))
        XCTAssertTrue(queue.enqueue("cancelled", id: cancelled, activeID: active))
        XCTAssertFalse(queue.enqueue("duplicate", id: first, activeID: active))
        XCTAssertTrue(queue.enqueue("last", id: last, activeID: active))
        XCTAssertTrue(queue.cancel(cancelled))
        XCTAssertFalse(queue.cancel(active))
        XCTAssertEqual(queue.ids, [first, last])
        XCTAssertEqual(queue.takeNext { _ in .start }?.value, "first")
        XCTAssertEqual(queue.takeNext { _ in .start }?.value, "last")
        XCTAssertTrue(queue.ids.isEmpty)
    }

    func testBusyHeadWaitsWithoutOvertakingAndMissingHeadIsSkipped() {
        let first = UUID(), second = UUID()
        let queue = BuildQueue<Int>()
        queue.enqueue(1, id: first, activeID: nil)
        queue.enqueue(2, id: second, activeID: nil)
        XCTAssertNil(queue.takeNext { $0 == first ? .wait : .start })
        XCTAssertEqual(queue.ids, [first, second])
        let skipped = queue.takeNext { $0 == first ? .skip : .start }
        XCTAssertEqual(skipped?.id, first)
        XCTAssertEqual(skipped?.decision, .skip)
        XCTAssertEqual(queue.takeNext { _ in .start }?.id, second)
    }

    func testHeadThatBecomesBusyDuringPreflightGoesBackFirst() throws {
        let first = UUID(), second = UUID()
        let queue = BuildQueue<Int>()
        queue.enqueue(1, id: first, activeID: nil)
        queue.enqueue(2, id: second, activeID: nil)
        let entry = try XCTUnwrap(queue.takeNext { _ in .start })
        queue.retryFirst((entry.id, entry.value))
        XCTAssertEqual(queue.ids, [first, second])
        XCTAssertEqual(queue.takeNext { _ in .start }?.value, 1)
    }

    func testSaveRecoveryReleaseWakesAWaitingTitle() throws {
        let gate = SaveOperationGate()
        let queue = BuildQueue<String>()
        let id = UUID(), title = "0100A00000000000"
        let location = try SaveLocation.profileLocation(titleID: title, profileID: UUID(), in: FileManager.default.temporaryDirectory)
        queue.enqueue(title, id: id, activeID: nil)
        gate.setRecoveryBlocked(true, location: location)
        XCTAssertNil(queue.takeNext { _ in gate.isBusy(titleID: title, recoveryLocation: location) ? .wait : .start })
        var started: UUID?
        gate.onActivityChange = { started = queue.takeNext { _ in gate.isBusy(titleID: title, recoveryLocation: location) ? .wait : .start }?.id }
        gate.setRecoveryBlocked(false, location: location)
        XCTAssertEqual(started, id)
    }
}
