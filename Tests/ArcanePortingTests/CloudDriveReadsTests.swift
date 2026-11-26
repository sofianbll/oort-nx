import Foundation
import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class CloudDriveReadsTests: XCTestCase {
    private actor Runner {
        private(set) var commands: [[String]] = []
        private(set) var cancelled = 0
        var delay: Duration = .zero
        var status: Int32 = 0
        private var nextCommand: XCTestExpectation?
        func set(delay: Duration) { self.delay = delay }
        func set(status: Int32) { self.status = status }
        func holdNextCommand(_ started: XCTestExpectation) {
            delay = .seconds(10)
            nextCommand = started
        }
        func record(_ args: [String]) {
            commands.append(args)
            nextCommand?.fulfill()
            nextCommand = nil
        }
        func noteCancelled() { cancelled += 1 }
        nonisolated var run: RcloneConfiguration.Run {
            { _, args, _ in
                await self.record(args)
                do { try await Task.sleep(for: await self.delay) }
                catch { await self.noteCancelled(); throw CancellationError() }
                if args[0] == "listremotes" {
                    return .init(status: 0, stdout: #"[{"name":"fixture","type":"drive","source":"file"}]"#, stderr: "")
                }
                return .init(status: await self.status, stdout: args.contains("--stat") ? #"{"Name":"Games","IsDir":true}"# : #"[{"Name":"Switch","IsDir":true}]"#, stderr: "")
            }
        }
        func listings() -> Int { commands.filter { $0[0] == "lsjson" }.count }
    }

    private func drive(_ runner: Runner, _ reads: CloudDriveReads?) -> CloudDriveFolders {
        CloudDriveFolders(remote: "fixture", executable: URL(fileURLWithPath: "/synthetic/rclone"), reads: reads, run: runner.run)
    }

    func testTheSameFolderIsReadOnceThenAgainAfterRefreshOrAMinute() async throws {
        let runner = Runner(), reads = CloudDriveReads()
        for _ in 0..<3 { _ = try await drive(runner, reads).list("Games", ticket: UUID()) }
        var count = await runner.listings()
        XCTAssertEqual(count, 1)
        _ = try await drive(runner, reads).list("Games/Switch", ticket: UUID())
        count = await runner.listings()
        XCTAssertEqual(count, 2, "Another folder is another answer")
        await reads.clear()
        _ = try await drive(runner, reads).list("Games", ticket: UUID())
        count = await runner.listings()
        XCTAssertEqual(count, 3)
        let short = CloudDriveReads(lifetime: .zero)
        for _ in 0..<2 { _ = try await drive(runner, short).list("Games", ticket: UUID()) }
        count = await runner.listings()
        XCTAssertEqual(count, 5, "An answer too old is asked again")
    }

    func testReadsAtTheSameTimeShareOneProcessAndOnlyTheLastReaderStopsIt() async throws {
        let runner = Runner(), reads = CloudDriveReads()
        await runner.set(delay: .milliseconds(150))
        let service = drive(runner, reads)
        let first = Task { try await service.list("Games", ticket: UUID()) }
        let second = Task { try await service.list("Games", ticket: UUID()) }
        try await Task.sleep(for: .milliseconds(40))
        first.cancel()
        let names = try await second.value.names
        XCTAssertEqual(names, ["Switch"])
        let count = await runner.listings(), cancelled = await runner.cancelled
        XCTAssertEqual(count, 1)
        XCTAssertEqual(cancelled, 0)
        let started = expectation(description: "The last reader's command actually started")
        await runner.holdNextCommand(started)
        let alone = Task { try await service.list("Elsewhere", ticket: UUID()) }
        await fulfillment(of: [started], timeout: 5)
        alone.cancel()
        do { _ = try await alone.value; XCTFail("Cancelled") } catch is CancellationError {}
        let stopped = await runner.cancelled
        XCTAssertEqual(stopped, 1, "Nobody waits for it any more")
    }

    func testARefusalIsNeverKept() async throws {
        let runner = Runner(), reads = CloudDriveReads()
        await runner.set(status: 3)
        do { _ = try await drive(runner, reads).list("Games", ticket: UUID()); XCTFail("Missing") } catch StorageBackendError.notFound {}
        await runner.set(status: 0)
        let names = try await drive(runner, reads).list("Games", ticket: UUID()).names
        XCTAssertEqual(names, ["Switch"])
    }

    /// Reads kept for the screen must never decide a write, a move or an access check.
    func testNothingThatWritesOrAllowsAWriteGoesThroughKeptReads() async throws {
        let runner = Runner()
        let service = drive(runner, CloudDriveReads())
        let plan = try JSONDecoder().decode(CloudDriveFolders.MovePlan.self, from: Data(
            #"{"source":"Old","remote":"fixture","games":0,"bytes":0,"entries":[]}"#.utf8))
        let refused: [() async throws -> Void] = [
            { try await service.create("New", in: "Games") },
            { try await service.createPath("Games/New", below: "Games", shown: .init(account: "a", id: "b")) },
            { try await service.verifyAccess(to: "Games") },
            { try await service.verifyPersonalFolder("Games") },
            { _ = try await service.movePlan(from: "Games", to: "New") },
            { try await service.preflightMove(plan, to: "New") },
            { _ = try await service.move(plan, to: "New") { _, _ in } },
            { try await service.verifyCompletedMove(plan, to: "New") },
            { _ = try await service.snapshot() },
        ]
        for (index, attempt) in refused.enumerated() {
            do { try await attempt(); XCTFail("\(index) must be refused") }
            catch StorageBackendError.invalidConfiguration {}
        }
        let commands = await runner.commands
        XCTAssertTrue(commands.isEmpty)
        for command in ["mkdir", "moveto", "copyto", "deletefile", "backend", "rcd", "version"] {
            XCTAssertFalse(CloudDriveReads.isRead([command, "x"]), command)
        }
        XCTAssertFalse(CloudDriveReads.isRead(["config", "update"]))
        XCTAssertFalse(CloudDriveReads.isRead(["config", "delete"]))
    }

    /// Folders never read are glanced at a few at a time; browsing into one then costs nothing.
    func testAGlanceReadsALimitedNumberOfFoldersAndPreparesTheNextOne() async throws {
        let runner = Runner(), reads = CloudDriveReads()
        let service = drive(runner, reads)
        let index = await service.glance(at: (0..<40).map { "Photos/\($0)" }, into: try CloudFolderIndex(entries: []))
        XCTAssertEqual(index.kind(of: "Photos/0"), .unknown)
        var count = await runner.listings()
        XCTAssertEqual(count, CloudDriveFolders.glanceLimit)
        _ = try await service.list("Photos/3", ticket: UUID())
        count = await runner.listings()
        XCTAssertEqual(count, CloudDriveFolders.glanceLimit)
    }

    func testAGlanceTellsCompiledGamesFromROMs() async throws {
        let title = "Fixture [0100000000001000]"
        for (item, isCompiled) in [(#"{"Name":"manifests","IsDir":true}"#, true), (#"{"Name":"Base.nsp","IsDir":false,"Size":1}"#, false)] {
            let service = CloudDriveFolders(remote: "fixture", executable: URL(fileURLWithPath: "/synthetic/rclone")) { _, args, _ in
                switch args.prefix(2).joined(separator: " ") {
                case "lsjson fixture:Elsewhere/Games": .init(status: 0, stdout: #"[{"Name":"\#(title)","IsDir":true}]"#, stderr: "")
                case "lsjson fixture:Elsewhere/Games/\(title)": .init(status: 0, stdout: "[\(item)]", stderr: "")
                default: .init(status: 0, stdout: #"[{"name":"fixture","type":"drive","source":"file"}]"#, stderr: "")
                }
            }
            let index = await service.glance(at: ["Elsewhere/Games"], into: try CloudFolderIndex(entries: []))
            XCTAssertEqual(index.kind(of: "Elsewhere/Games"), isCompiled ? .compiled(count: 1, names: ["Fixture"]) : .roms(count: 1, names: ["Fixture"]))
        }
    }
}
