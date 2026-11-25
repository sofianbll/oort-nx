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
            .appendingPathComponent("CatalogAppChecks/fake_rclone.py")
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

    /// The calls of the assistant at ecfc72b4, in its order, without the player's own time.
    func testBefore() async throws {
        let start = ContinuousClock.now
        let config = RcloneConfiguration(executable: tool)
        _ = try await config.version()
        let remotes = try await config.remotes()
        XCTAssertEqual(remotes.map(\.name), ["fixture"])
        try report("before: account shown", seconds: elapsed(since: start))
        let drive = CloudDriveFolders(remote: "fixture", executable: tool)
        func browse(_ path: String) async throws {
            async let parent = try? drive.creationParent(path)
            let listing: CloudDriveFolders.Listing
            do { listing = try await drive.list(path, ticket: UUID()) }
            catch StorageBackendError.notFound {
                _ = try? await drive.creationParent(path.split(separator: "/").dropLast().joined(separator: "/"))
                _ = await parent
                return
            }
            _ = await parent
            if !path.isEmpty { _ = try? await drive.libraryCount(in: path, folders: listing.names) }
        }
        let library = try await drive.discoverLibrary()
        XCTAssertNil(library, "Games/Switch/Oort-nx is two levels down: not found today")
        // The player opens each folder down to the library.
        for path in ["", "Games", "Games/Switch", "Games/Switch/Oort-nx"] { try await browse(path) }
        let sources = try await drive.discoverSources(library: "Games/Switch/Oort-nx")
        XCTAssertNil(sources, "Games/Switch/Jeux is beside the library: not found today")
        // The default is shown, missing; the player climbs and opens the ROM folder.
        for path in ["Games/Switch/Oort-nx/GameFiles", "Games/Switch", "Games/Switch/Jeux"] {
            async let parent = try? drive.creationParent(path)
            do { _ = try await drive.list(path, ticket: UUID()) }
            catch StorageBackendError.notFound {
                _ = try? await drive.creationParent(path.split(separator: "/").dropLast().joined(separator: "/"))
            }
            _ = await parent
        }
        try report("before: both folders shown", seconds: elapsed(since: start))
        try await drive.verifyAccess(to: "Games/Switch/Oort-nx")
        try await drive.verifyPersonalFolder("Games/Switch/Oort-nx")
        try await drive.verifyAccess(to: "Games/Switch/Jeux")
        try await drive.verifyPersonalFolder("Games/Switch/Jeux")
        try report("before: ready", seconds: elapsed(since: start))
    }
}
