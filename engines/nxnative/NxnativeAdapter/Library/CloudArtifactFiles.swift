import CryptoKit
import Darwin
import Foundation
import NXLibraryCore

/// The manifest describes the bytes as stored by rclone (including link sidecars).
enum CloudArtifactFiles {
    static let linkSuffix = ".rclonelink"

    struct Entry: Codable, Equatable, Sendable {
        let path: String
        let size: Int64
        let md5: String

        var relative: String { path.hasSuffix(linkSuffix) ? String(path.dropLast(linkSuffix.count)) : path }
        var isLink: Bool { relative != path }

        func matches(_ file: StorageObject) -> Bool { size == file.size && md5 == file.md5 }

        func matches(_ url: URL) throws -> Bool {
            try SaveFiles.safePath(url)
            guard let st = try? CloudArchiveInventory.node(at: url), st.st_mode & S_IFMT == S_IFREG,
                  st.st_size == size else { return false }
            return try CloudArchiveInventory.hashes(at: url, includeSHA256: false)["md5"] == md5
        }
    }

    struct Tree: Codable, Equatable, Sendable {
        let folder: String
        let entries: [Entry]

        var key: StorageObjectKey { .init(folder) }
        var objects: [StorageObject] {
            entries.map { .init(key: .init(folder + "/" + $0.path), size: $0.size, hashes: ["md5": $0.md5]) }
        }

        func validate(titleID: String, kind: CloudArtifactKind, digest: String, bytes: Int64) throws {
            let parts = folder.components(separatedBy: "/")
            guard parts.count == (kind == .app ? 4 : 3), parts.allSatisfy(CloudDriveFolders.validName),
                  parts[0].hasSuffix(" [\(titleID)]"), parts[1] == kind.rawValue, parts[2] == digest,
                  kind != .app || (parts[3] as NSString).pathExtension.lowercased() == "app",
                  try CloudArtifactFiles.digest(entries) == digest,
                  try CloudArtifactFiles.validate(entries, kind: kind) == bytes else {
                throw CloudArchiveError.invalidManifest
            }
        }

        func verify(on backend: RcloneStorageBackend) async throws {
            let listing = try await backend.tree(in: key)
            let expected = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
            guard listing.count == entries.count, listing.allSatisfy({
                expected[$0.key.value]?.matches($0) == true
            }) else { throw StorageBackendError.hashMismatch }
        }
    }

    static func entries(at root: URL, snapshot: CloudArchiveInventory.Snapshot,
                        excludingSignatures: Bool = false) throws -> [Entry] {
        try snapshot.entries.compactMap { entry in
            try Task.checkCancellation()
            guard entry.type != "D" else { return nil }
            if excludingSignatures && isSignaturePath(entry.path) { return nil }
            guard !entry.path.lowercased().hasSuffix(linkSuffix) else { throw CloudArchiveError.unsafePath }
            if let link = entry.link {
                let data = Data(link.utf8)
                return Entry(path: entry.path + linkSuffix, size: Int64(data.count),
                             md5: CloudArchiveInventory.hex(Insecure.MD5.hash(data: data)))
            }
            let file = root.appendingPathComponent(entry.path)
            try SaveFiles.safePath(file)
            return Entry(path: entry.path, size: entry.size!, md5: try CloudArchiveInventory.hashes(at: file, includeSHA256: false)["md5"]!)
        }.sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
    }

    static func isSignaturePath(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.lowercased() == "_codesignature" }
    }

    static func digest(_ entries: [Entry]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return CloudArchiveInventory.hex(SHA256.hash(data: try encoder.encode(entries)))
    }

    static func isUsableSubset(_ entries: [Entry], of tree: Tree) -> Bool {
        let expected = Dictionary(uniqueKeysWithValues: tree.entries.map { ($0.path, $0) })
        return (tree.entries.isEmpty || entries.contains { !$0.isLink })
            && entries.allSatisfy { expected[$0.path] == $0 }
    }

    static func validate(_ entries: [Entry], kind: CloudArtifactKind) throws -> Int64 {
        var paths: [String: (String, Bool)] = [:]
        var bytes: Int64 = 0
        guard entries.count <= CloudArchiveInventory.maximumEntries else { throw CloudArchiveError.invalidManifest }
        for entry in entries {
            try Task.checkCancellation()
            let path = entry.relative
            guard !path.isEmpty, SaveFiles.validRelative(path), CloudLibraryPreference.safePath(path),
                  !path.lowercased().hasSuffix(linkSuffix), !CloudArchiveInventory.isExcluded(path, kind),
                  entry.size >= 0, !entry.isLink || (1...4096).contains(entry.size),
                  entry.md5.utf8.count == 32, entry.md5.utf8.allSatisfy({ "0123456789abcdef".utf8.contains($0) }),
                  bytes <= Int64.max - entry.size else { throw CloudArchiveError.invalidManifest }
            bytes += entry.size
            var prefix = ""
            let parts = path.split(separator: "/")
            for (index, part) in parts.enumerated() {
                prefix += (prefix.isEmpty ? "" : "/") + part
                let directory = index < parts.count - 1
                let key = prefix.precomposedStringWithCanonicalMapping.lowercased()
                if let old = paths[key] {
                    guard directory, old.1, old.0.utf8.elementsEqual(prefix.utf8) else { throw CloudArchiveError.unsafePath }
                } else {
                    // A link's wire name must not also be a directory.
                    guard !directory || !part.lowercased().hasSuffix(linkSuffix) else { throw CloudArchiveError.unsafePath }
                    paths[key] = (prefix, directory)
                }
            }
        }
        return bytes
    }

    /// Inspect sidecars before creating any symlink, rather than letting remote data create arbitrary links.
    static func restoreLink(_ sidecar: URL, to file: URL, relative: String, kind: CloudArtifactKind) throws {
        let data = try SaveFiles.readRegular(sidecar, limit: 4096)
        guard let target = String(data: data, encoding: .utf8),
              CloudArchiveInventory.safeLink(target, at: relative, kind: kind) else { throw CloudArchiveError.unsafePath }
        try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: target)
    }
}
