import CryptoKit
import Foundation
import OortCore
import Testing
@testable import OortMobile

/// Installing, updating and forgetting a build of the cloud; the queue that survives the app.
struct CloudTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("oort-cloud-\(UUID().uuidString)")
    private let id = "0100000000010000"
    private var games: URL { root.appendingPathComponent("Documents/games/\(id)") }
    private struct Hash: ShelfHasher {
        var hash = SHA256()
        mutating func update(_ data: Data) { hash.update(data: data) }
        func hex() -> String { hash.finalize().map { String(format: "%02x", $0) }.joined() }
    }
    private func installer(_ refusal: String? = nil) -> CloudInstall {
        let crypto = ShelfCrypto(sha256: { Hash() }, isSigned: { _, _ in false })
        return CloudInstall(store: ShelfStore(root: root.appendingPathComponent("builds"), crypto: crypto, available: { _ in .max }, keepOutOfBackup: { _ in }),
                            crypto: crypto, frameworks: root.appendingPathComponent("Documents/Frameworks"), games: games.deletingLastPathComponent(), check: { _ in refusal })
    }

    /// A build as the download leaves it, whole and checked.
    private func downloaded(_ version: String, data: [String: String], code: String = "code") throws -> ShelfBuild {
        let manifest: [String: Any] = ["schema": 1, "title_id": id, "name": "Orbit", "display_version": "1", "package_version": "1", "modules": ["main"], "nro_count": 0,
            "chain": "b-abc", "loader": "FH", "framework": "DmGame\(id).framework", "framework_executable": "DmGame", "image_marker": "m", "profile": "p", "shader_map": "s",
            "launcher": "l", "romfs_marker": "r", "romfs_identity": "i", "min_os": "26.0"]
        var files = ["Game.framework/game.manifest.json": try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys), "Game.framework/DmGame": Data(code.utf8)]
        for (name, text) in data { files[name] = Data(text.utf8) }
        func sha(_ data: Data) -> String { var h = Hash(); h.update(data); return h.hex() }
        let entries = files.sorted { $0.key < $1.key }.map { ["path": $0.key, "size": $0.value.count, "sha256": sha($0.value)] as [String: Any] }
        let fields: [String: Any] = ["titleID": id, "name": "Orbit", "platform": "ios", "gameVersion": version, "engineCommit": "c", "minimumSystem": "26.0", "architecture": "arm64",
            "features": [String](), "host": 1, "package": "Game.framework", "bytes": files.values.reduce(0) { $0 + $1.count }, "entries": entries,
            "digest": sha(Data(version.utf8)), "stamp": 1]
        let build = try JSONDecoder().decode(ShelfBuild.self, from: JSONSerialization.data(withJSONObject: fields))
        for (path, body) in files {
            let file = installer().store.visible(build).appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: file)
        }
        return build
    }
    private func read(_ path: String) -> String? { try? String(contentsOf: games.appendingPathComponent(path), encoding: .utf8) }
    private func save() throws {
        try FileManager.default.createDirectory(at: games.appendingPathComponent("save"), withIntermediateDirectories: true)
        try Data("precious".utf8).write(to: games.appendingPathComponent("save/slot"))
    }

    @Test func aGameIsInstalledThenUpdatedAndItsSavesStay() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try save()
        let one = try downloaded("1", data: ["data/romfs/a": "a1", "data/romfs/b": "b1"])
        try installer().install(one, freeSpace: { _ in .max })
        #expect(installer().installed()[id]?.version == "1")
        #expect(read("romfs/a") == "a1" && read("romfs/b") == "b1" && read("save/slot") == "precious")
        #expect(!installer().isDownloaded(one), "the download does not stay twice")
        let two = try downloaded("2", data: ["data/romfs/a": "a2"])
        #expect(installer().installed()[id]?.version == "1", "a newer download is not an installed one")
        try installer().install(two, freeSpace: { _ in .max })
        #expect(installer().installed()[id]?.version == "2")
        #expect(read("romfs/a") == "a2" && read("romfs/b") == nil && read("save/slot") == "precious")
        #expect(!FileManager.default.fileExists(atPath: games.appendingPathComponent(".oort-new").path))
    }

    @Test func whatIsRefusedLeavesTheGameAndTheDownloadAsTheyWere() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try installer().install(try downloaded("1", data: ["data/romfs/a": "a1"]), freeSpace: { _ in .max })
        let two = try downloaded("2", data: ["data/romfs/a": "a2"])
        #expect(throws: FrameworkImport.Failure.wrongSigner("another team")) { try installer("another team").install(two, freeSpace: { _ in .max }) }
        #expect(read("romfs/a") == "a1" && installer().installed()[id]?.version == "1" && installer().isDownloaded(two))
        #expect(throws: FrameworkImport.Failure.noSpace) { try installer().install(two, freeSpace: { _ in 1000 }) }
        #expect(read("romfs/a") == "a1" && installer().isDownloaded(two), "the data went back to the download")
        try Data("other".utf8).write(to: installer().store.visible(two).appendingPathComponent("Game.framework/DmGame"))
        #expect(throws: ShelfError.wrongDigest) { try installer().install(two, freeSpace: { _ in .max }) }
        let bad = try downloaded("3", data: ["data/save/slot": "overwritten"])
        #expect(throws: ShelfError.unsafeName) { try installer().install(bad, freeSpace: { _ in .max }) }
        let outside = try downloaded("4", data: ["other/file": "x"])
        #expect(throws: ShelfError.unsafeName) { try installer().install(outside, freeSpace: { _ in .max }) }
        #expect(read("romfs/a") == "a1" && installer().installed()[id]?.version == "1")
    }

    @Test func discardingKeepsWhatIsInstalled() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try installer().install(try downloaded("1", data: ["data/romfs/a": "a1"]), freeSpace: { _ in .max })
        let two = try downloaded("2", data: [:])
        installer().discard(id)
        #expect(!installer().isDownloaded(two) && installer().installed()[id]?.version == "1")
    }

    @Test func theQueueSurvivesTheAppInOrder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("queue.json"), build = try downloaded("1", data: [:])
        var queue = ShelfQueue(file: file, keepOutOfBackup: { _ in })
        queue.add(build)
        queue.add(build)
        #expect(queue.jobs.count == 1 && queue.next?.id == id)
        queue.set(id, .running)
        #expect(queue.next == nil, "one at a time")
        #expect(ShelfQueue(file: file, keepOutOfBackup: { _ in }).next?.build == build, "what was running waits again")
        queue.set(id, .failed, reason: .noSpace(needed: 12))
        let again = ShelfQueue(file: file, keepOutOfBackup: { _ in })
        #expect(again.jobs.first?.reason == "noSpace" && again.jobs.first?.needed == 12 && again.next == nil)
        queue.remove(id)
        #expect(ShelfQueue(file: file, keepOutOfBackup: { _ in }).jobs.isEmpty)
    }
}
