import Foundation
import OSLog
import NXLibraryCore

/// Disposable, profile-local cache. Keys are digests, never filesystem paths.
actor CloudArchiveFingerprintCache {
    struct Fingerprint: Codable, Sendable {
        let signature: String
        let sha256: String
        let withoutRootMtime: String?

        func matches(_ artifact: CloudGameManifest.Artifact) -> Bool {
            sha256 == artifact.inventorySHA256 || withoutRootMtime.map {
                $0 == artifact.options[CloudArchiveInventory.cacheFingerprintOption]
            } == true
        }
    }

    private struct Entry: Codable {
        let key: String
        let fingerprint: Fingerprint
    }

    private struct Snapshot: Codable {
        let version: Int
        let entries: [Entry]
    }

    static let shared = CloudArchiveFingerprintCache(file: AppData.cacheRoot.appendingPathComponent("cloud-fingerprints.json"))
    private static let log = Logger(subsystem: "io.github.sofianbll.oortnx", category: "cloud-fingerprints")
    private static let capacity = 500
    private let file: URL?
    private var ordered: [Entry]?

    init(file: URL? = nil) { self.file = file }

    func entries() -> [String: Fingerprint] {
        let entries = ordered ?? load()
        ordered = entries
        return Dictionary(entries.map { ($0.key, $0.fingerprint) }, uniquingKeysWith: { _, last in last })
    }

    /// One atomic write at the end of each comparison that actually computed hashes.
    func save(_ fresh: [String: Fingerprint]) {
        guard !fresh.isEmpty else { return }
        let previous = ordered ?? load()
        let updated = previous.filter { fresh[$0.key] == nil } + fresh.keys.sorted().compactMap { key in
            fresh[key].map { Entry(key: key, fingerprint: $0) }
        }
        let entries = Array(updated.suffix(Self.capacity))
        ordered = entries
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Snapshot(version: 1, entries: entries)).write(to: file, options: .atomic)
        } catch {
            Self.log.error("Could not save the cloud fingerprint cache")
        }
    }

    private func load() -> [Entry] {
        guard let file else { return [] }
        do {
            _ = try CloudArchiveInventory.node(at: file)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: SaveFiles.readRegular(file, limit: 256 * 1024))
            guard snapshot.version == 1 else {
                Self.log.warning("Unsupported cloud fingerprint cache version")
                return []
            }
            let entries = Array(snapshot.entries.suffix(Self.capacity))
            guard entries.allSatisfy({ entry in
                ([entry.key, entry.fingerprint.signature, entry.fingerprint.sha256]
                    + [entry.fingerprint.withoutRootMtime].compactMap { $0 }).allSatisfy(Self.isDigest)
            }) else { throw CocoaError(.fileReadCorruptFile) }
            return entries
        } catch CloudArchiveError.localMissing {
            // A new profile has no cache yet.
        } catch {
            Self.log.warning("Could not read the cloud fingerprint cache")
        }
        return []
    }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
