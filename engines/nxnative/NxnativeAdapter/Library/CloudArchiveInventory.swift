import CryptoKit
import Darwin
import Foundation
import OortLibrary

/// `aa list` is checked before extracting. A separate filesystem fingerprint checks what was actually restored.
enum CloudArchiveInventory {
    struct Entry: Decodable, Equatable {
        let path: String
        let type: String
        let size: Int64?
        let link: String?
        let mode: Int

        enum CodingKeys: String, CodingKey { case path = "PAT", type = "TYP", size = "SIZ", link = "LNK", mode = "MOD" }
    }

    struct Snapshot {
        let entries: [Entry]
        let bytes: Int64
        let sha256: String
        let withoutRootMtime: String?
        let hasExcludedFiles: Bool
        let skippedRoots: [String]
        let latestFileWrite: Date?

        var isSkippedOnly: Bool { entries.count == 1 && !skippedRoots.isEmpty && !hasExcludedFiles }
    }

    struct ContentFingerprint {
        private var hash = SHA256()
        private var withoutRootMtime: SHA256?

        init(kind: CloudArtifactKind, includeContents: Bool = true) {
            withoutRootMtime = includeContents && kind == .cache ? SHA256() : nil
        }

        mutating func field(_ value: String, rootMtime: Bool = false) {
            let data = Data(value.utf8)
            let prefix = Data("\(data.count):".utf8)
            hash.update(data: prefix)
            hash.update(data: data)
            if !rootMtime {
                withoutRootMtime?.update(data: prefix)
                withoutRootMtime?.update(data: data)
            }
        }

        mutating func entry(_ entry: Entry, mtime: timespec) {
            for value in [entry.path, entry.type, String(entry.mode)] { field(value) }
            field(String(mtime.tv_sec), rootMtime: entry.path.isEmpty)
            field(String(mtime.tv_nsec), rootMtime: entry.path.isEmpty)
            field(entry.link ?? "")
        }

        mutating func contents(attributes: [(String, String)], fileSHA256: String?) {
            field(String(attributes.count))
            for (key, digest) in attributes { field(key); field(digest) }
            if let fileSHA256 { field(fileSHA256) }
        }

        var digest: String { hex(hash.finalize()) }
        var digestWithoutRootMtime: String? { withoutRootMtime.map { hex($0.finalize()) } }
    }

    static let maximumEntries = 100_000
    static let cacheFingerprintOption = "cache_inventory_without_root_mtime"
    static let excludedNames = ["prod.keys", "title.keys", "dev.keys", "keys.txt"]

    // The stream reaches private remote staging before validation: exclude case variants at the producer too.
    static let protectedArchiveExclusion: String = {
        let keys = excludedNames.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let saves = SaveLocation.archiveSaveNames.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return "(?i)(^|/)(\(keys))(/|$)|^(?:(?:Contents/Resources/)?(?:run/)?|tmp/[^/]+_run/)(\(saves)|save\\.users\\.[a-z0-9]{6})(/|$)"
    }()
    private static let protectedPaths = try! NSRegularExpression(pattern: protectedArchiveExclusion)
    private static let skippedCacheRoots = ["obsolete", "nsp"]

    static func archiveExclusions(_ kind: CloudArtifactKind) -> [String] {
        ["-exclude-regex", protectedArchiveExclusion]
            + (kind == .cache ? ["-exclude-regex", "(?i)^(\(skippedCacheRoots.joined(separator: "|")))(/|$)"] : [])
    }

    static func isExcluded(_ path: String, _ kind: CloudArtifactKind) -> Bool {
        let lower = path.lowercased()
        return protectedPaths.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
            || (kind == .cache && skippedCacheRoots.contains { lower == $0 || lower.hasPrefix($0 + "/") })
    }

    static func validate(_ entries: [Entry], kind: CloudArtifactKind) throws -> Int64 {
        var types: [String: String] = [:]
        var bytes: Int64 = 0
        for entry in entries {
            let path = entry.path
            let normalized = path.precomposedStringWithCanonicalMapping.lowercased()
            guard (path.isEmpty ? entry.type == "D" : SaveFiles.validRelative(path)),
                  (0...0o777).contains(entry.mode), !isExcluded(path, kind), types.updateValue(entry.type, forKey: normalized) == nil
            else { throw CloudArchiveError.unsafePath }
            switch entry.type {
            case "D": break
            case "F":
                guard let size = entry.size, size >= 0, size <= Int64.max - bytes else {
                    throw CloudArchiveError.invalidArchive
                }
                bytes += size
            case "L":
                guard let target = entry.link, safeLink(target, at: path, kind: kind) else {
                    throw CloudArchiveError.unsafePath
                }
            default: throw CloudArchiveError.unsafePath
            }
        }
        guard types[""] == "D" else { throw CloudArchiveError.invalidArchive }
        for entry in entries where !entry.path.isEmpty {
            let parent = entry.path.split(separator: "/").dropLast().joined(separator: "/")
            guard types[parent.precomposedStringWithCanonicalMapping.lowercased()] == "D" else {
                throw CloudArchiveError.unsafePath
            }
        }
        return bytes
    }

    static func safeLink(_ target: String, at path: String, kind: CloudArtifactKind) -> Bool {
        guard !target.isEmpty, !target.hasPrefix("/"), !target.contains("\0") else { return false }
        var parts = Array(path.split(separator: "/").dropLast())
        var descended = false
        for component in target.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                // Traversing back through a link after following it can escape the root.
                guard !descended, !parts.isEmpty else { return false }
                parts.removeLast()
            } else {
                descended = true
                parts.append(component)
            }
        }
        return !isExcluded(parts.joined(separator: "/"), kind)
    }

    static func scan(_ root: URL, kind: CloudArtifactKind) throws -> Snapshot {
        try scan(root, kind: kind, includeContents: true)
    }

    static func signature(_ root: URL, kind: CloudArtifactKind) throws -> Snapshot {
        try scan(root, kind: kind, includeContents: false)
    }

    static func fingerprintKey(_ root: URL, kind: CloudArtifactKind, portable: Bool = false) -> String {
        hex(SHA256.hash(data: Data("\(portable ? "files:" : "")\(kind.rawValue):\(root.path)".utf8)))
    }

    private static func scan(_ root: URL, kind: CloudArtifactKind, includeContents: Bool) throws -> Snapshot {
        var entries: [Entry] = []
        var fingerprint = ContentFingerprint(kind: kind, includeContents: includeContents)
        var hasExcludedFiles = false
        var skippedRoots: [String] = []
        var latestFileWrite: Date?
        let device = try node(at: root).st_dev
        func visit(_ url: URL, path: String) throws {
            try Task.checkCancellation()
            if isExcluded(path, kind) {
                if kind == .cache, skippedCacheRoots.contains(path.lowercased()),
                   try node(at: url).st_mode & S_IFMT == S_IFDIR {
                    skippedRoots.append(path)
                } else {
                    hasExcludedFiles = true
                }
                return
            }
            let st = try node(at: url)
            guard st.st_dev == device, st.st_mode & 0o7000 == 0,
                  entries.count < maximumEntries else { throw CloudArchiveError.unsafePath }
            let type: String
            switch st.st_mode & S_IFMT {
            case S_IFDIR: type = "D"
            case S_IFREG: type = "F"
            case S_IFLNK: type = "L"
            default: throw CloudArchiveError.unsafePath
            }
            guard !path.isEmpty || type == "D" else { throw CloudArchiveError.unsafePath }
            let link = type == "L" ? try FileManager.default.destinationOfSymbolicLink(atPath: url.path) : nil
            let entry = Entry(path: path, type: type, size: type == "F" ? st.st_size : nil,
                              link: link, mode: Int(st.st_mode & 0o777))
            entries.append(entry)
            fingerprint.entry(entry, mtime: st.st_mtimespec)
            if type == "F", kind == .cache {
                let mtime = Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
                latestFileWrite = max(latestFileWrite ?? mtime, mtime)
            }
            if includeContents {
                let attributes = attributeDigests(try SaveFiles.attributes(url))
                fingerprint.contents(attributes: attributes,
                                     fileSHA256: type == "F" ? try hashes(at: url, includeMD5: false)["sha256"] : nil)
            } else {
                // ctime also catches xattr and same-size edits with a preserved mtime.
                for value in [String(st.st_dev), String(st.st_ino), String(st.st_size),
                              String(st.st_ctimespec.tv_sec), String(st.st_ctimespec.tv_nsec)] { fingerprint.field(value) }
            }
            if type == "D" {
                for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                    .sorted(by: { $0.lastPathComponent.utf8.lexicographicallyPrecedes($1.lastPathComponent.utf8) }) {
                    try visit(child, path: path.isEmpty ? child.lastPathComponent : path + "/" + child.lastPathComponent)
                }
            }
        }
        try visit(root, path: "")
        return try Snapshot(entries: entries, bytes: validate(entries, kind: kind),
                            sha256: fingerprint.digest, withoutRootMtime: fingerprint.digestWithoutRootMtime,
                            hasExcludedFiles: hasExcludedFiles, skippedRoots: skippedRoots, latestFileWrite: latestFileWrite)
    }

    static func node(at url: URL) throws -> stat {
        var st = stat()
        guard lstat(url.path, &st) == 0 else {
            if errno == ENOENT { throw CloudArchiveError.localMissing }
            throw CloudArchiveError.unsafePath
        }
        return st
    }

    static func hashes(at url: URL, includeMD5: Bool = true, includeSHA256: Bool = true) throws -> [String: String] {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw CloudArchiveError.unsafePath }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var st = stat(), sha = SHA256(), md5 = Insecure.MD5()
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG else { throw CloudArchiveError.unsafePath }
        try handle.forEachChunk { chunk in
            try Task.checkCancellation()
            if includeSHA256 { sha.update(data: chunk) }
            if includeMD5 { md5.update(data: chunk) }
        }
        var hashes = includeSHA256 ? ["sha256": hex(sha.finalize())] : [:]
        if includeMD5 { hashes["md5"] = hex(md5.finalize()) }
        return hashes
    }

    static func attributeDigests(_ attributes: [String: Data]) -> [(String, String)] {
        attributes.sorted { $0.key < $1.key }.map { ($0.key, hex(SHA256.hash(data: $0.value))) }
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
