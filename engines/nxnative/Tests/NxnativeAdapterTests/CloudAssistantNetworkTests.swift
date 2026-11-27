import CryptoKit
import Foundation
import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

/// What the cloud assistant costs on a synthetic Drive that answers in 200 ms.
/// Off unless OORT_MEASURE_CLOUD names the report to write: it waits for real.
final class CloudAssistantNetworkTests: XCTestCase {
    private var root: URL!
    private var log: URL!
    private var tool: URL!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["OORT_MEASURE_CLOUD"] != nil else {
            throw XCTSkip("Set OORT_MEASURE_CLOUD to measure")
        }
        root = URL(fileURLWithPath: "/private/tmp/oort-measure-\(UUID().uuidString.prefix(8))")
        let drive = root.appendingPathComponent("drive")
        log = root.appendingPathComponent("log")
        tool = root.appendingPathComponent("rclone")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        try Data().write(to: log)
        try Self.fill(drive)
        let fake = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("apps/mac/Tests/CatalogAppChecks/fake_rclone.py")
        try Data("#!/bin/sh\nFAKE_DRIVE='\(drive.path)' FAKE_LOG='\(log.path)' FAKE_DELAY=0.2 exec /usr/bin/python3 '\(fake.path)' \"$@\"\n".utf8)
            .write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    }

    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    /// One compiled game in Games/Switch/Oort-nx, fifteen ROM folders in Games/Switch/Jeux: the maintainer's own shape.
    static func fill(_ drive: URL) throws {
        let fm = FileManager.default
        let title = "0100123456789ABC"
        let hash = String(repeating: "0", count: 64)
        let artifacts = CloudArtifactKind.allCases.map {
            CloudGameManifest.Artifact(kind: $0, size: 7, sha256: hash, md5: String(hash.prefix(32)), unpackedSize: 1, entryCount: 1,
                inventorySHA256: hash, engineCommit: nil, shaderChain: nil, options: [:])
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(CloudGameManifest(version: 1, titleID: title, createdAt: Date(), artifacts: artifacts))
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let manifests = drive.appendingPathComponent("Games/Switch/Oort-nx/Lunar Observatory [\(title)]/manifests")
        try fm.createDirectory(at: manifests, withIntermediateDirectories: true)
        try bytes.write(to: manifests.appendingPathComponent("0000000000000001-\(digest).json"))
        for index in 0..<15 {
            let folder = drive.appendingPathComponent(String(format: "Games/Switch/Jeux/Fixture %02d [0100000000%06X]", index, 0x1000 + index * 0x2000))
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([0]).write(to: folder.appendingPathComponent("Fixture.nsp"))
        }
        for name in ["Documents", "Photos"] {
            try fm.createDirectory(at: drive.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }

    private func report(_ name: String, seconds: Double) throws {
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map { $0.split(separator: " ") }
        let processes = lines.filter { $0[1] == "process" }.count, requests = lines.filter { $0[1] == "request" }.count
        let line = String(format: "%@\t%d processes\t%d requests\t%.1f s\n", name, processes, requests, seconds)
        print(line)
        let file = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["OORT_MEASURE_CLOUD"]))
        let previous = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try Data((previous + line).utf8).write(to: file)
    }

    private func elapsed(since start: ContinuousClock.Instant) -> Double {
        Double((ContinuousClock.now - start).components.seconds)
            + Double((ContinuousClock.now - start).components.attoseconds) / 1e18
    }

    /// The calls of the assistant, in its order, without the player's own time. At ecfc72b4 the same Drive took
    /// 105 processes, 48 requests and 28.1 s to show both folders, 113, 52 and 29.5 s to be ready: the player
    /// had to open seven folders, and each one started a process per question.
    func testAssistant() async throws {
        let start = ContinuousClock.now
        let remotes = try await RcloneConfiguration(executable: tool).remotes()
        XCTAssertEqual(remotes.map(\.name), ["fixture"])
        try report("account shown", seconds: elapsed(since: start))
        let reads = CloudDriveReads()
        let shown = CloudDriveFolders(remote: "fixture", executable: tool, reads: reads)
        let found = try await shown.discoverFolders(kept: .init(account: nil, library: "Games/Switch/Oort-nx", sources: "Games/Switch/Jeux"))
        XCTAssertEqual(found.library?.path, "Games/Switch/Oort-nx")
        XCTAssertEqual(found.sources?.games, 15)
        try report("both folders shown", seconds: elapsed(since: start))
        let fresh = CloudDriveFolders(remote: "fixture", executable: tool)
        async let library: Void = fresh.verifyAccess(to: "Games/Switch/Oort-nx")
        async let sources: Void = fresh.verifyAccess(to: "Games/Switch/Jeux")
        _ = try await (library, sources)
        try report("ready", seconds: elapsed(since: start))
    }

    /// Opening a folder, then the same one again.
    func testBrowsing() async throws {
        let shown = CloudDriveFolders(remote: "fixture", executable: tool, reads: CloudDriveReads())
        var start = ContinuousClock.now
        let names = try await shown.list("Games/Switch", ticket: UUID()).names
        try report("folder opened", seconds: elapsed(since: start))
        _ = await shown.glance(at: names.map { "Games/Switch/\($0)" }, into: try CloudFolderIndex(entries: []))
        try report("its folders glanced at", seconds: elapsed(since: start))
        start = .now
        _ = try await shown.list("Games/Switch/Jeux", ticket: UUID())
        _ = try await shown.list("Games/Switch", ticket: UUID())
        try report("two folders opened again", seconds: elapsed(since: start))
    }
}
