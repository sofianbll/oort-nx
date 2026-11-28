import Darwin
import Foundation
import OortLibrary

/// One filing proposal per physical file, independent of the build catalog's grouping and defaults.
public enum GameInbox {
    public struct Input {
        public let url: URL
        fileprivate let stamp: Stamp?
        public var canRead: Bool { stamp != nil && ["nsp", "nsz", "xci", "xcz"].contains(url.pathExtension.lowercased()) }
    }

    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: URL { source }
        public let source: URL
        public let destination: URL?
        public let content: PackageContent?
        public let issue: String?
        public let needsKeys: Bool
        public let duplicate: Bool
        fileprivate let stamp: Stamp?
    }

    /// Preview-only memoization. The confirmed sort always verifies both files again.
    public final class DuplicateReviews: @unchecked Sendable {
        private struct Pair: Equatable {
            let destination: URL
            let incoming: Stamp
            let stored: Stamp
        }

        private let lock = NSLock()
        private var verified: [URL: Pair] = [:]

        public init() {}

        fileprivate func matches(_ source: URL, _ destination: URL, stamp: Stamp) -> Bool {
            guard let existing = Stamp(destination) else { return false }
            let pair = Pair(destination: destination, incoming: stamp, stored: existing)
            if lock.withLock({ verified[source] == pair }) { return true }
            guard (try? verifySame(source, destination)) == existing, Stamp(source) == stamp else { return false }
            lock.withLock {
                if verified[source] == nil, verified.count >= 512, let evicted = verified.keys.first {
                    verified.removeValue(forKey: evicted)
                }
                verified[source] = pair
            }
            return true
        }
    }

    fileprivate struct Stamp: Equatable {
        let device: Int32, inode: UInt64, bytes: Int64
        let modificationSeconds: Int, modificationNanos: Int
        let changeSeconds: Int, changeNanos: Int

        init?(_ url: URL) {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0 else { return nil }
            device = info.st_dev; inode = info.st_ino; bytes = info.st_size
            modificationSeconds = info.st_mtimespec.tv_sec; modificationNanos = info.st_mtimespec.tv_nsec
            changeSeconds = info.st_ctimespec.tv_sec; changeNanos = info.st_ctimespec.tv_nsec
        }

        func matchesAfterRename(_ other: Stamp) -> Bool {
            device == other.device && inode == other.inode && bytes == other.bytes
                && modificationSeconds == other.modificationSeconds && modificationNanos == other.modificationNanos
        }
    }

    private enum Failure: LocalizedError {
        case changed, discovery

        var errorDescription: String? {
            switch self {
            case .changed: return L10n.text("A file or folder changed. Refresh and review the proposal again.")
            case .discovery: return L10n.text("Arcane did not discover the copy. The original was kept.")
            }
        }
    }

    public static func files(in folder: URL) throws -> [URL] {
        guard exists(folder) else { return [] }
        guard safe(folder) else { throw Failure.changed }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                          options: .skipsHiddenFiles)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func inputs(_ urls: [URL]) -> [Input] {
        var seen = Set<String>()
        return urls.filter { $0.isFileURL && seen.insert($0.standardizedFileURL.path).inserted }.map {
            Input(url: $0, stamp: safe($0) ? Stamp($0) : nil)
        }
    }

    /// A nil reading map means package identification could not start without keys.
    public static func plan(inputs: [Input], readings: [URL: PackageReading]?, root: URL,
                            duplicateReviews: DuplicateReviews? = nil, names: (UInt64) -> String?) -> [Entry] {
        let folders = (try? files(in: root)) ?? []
        let entries: [Entry] = inputs.map { input in
            let url = input.url
            func ambiguous(_ issue: String, content: PackageContent? = nil) -> Entry {
                Entry(source: url, destination: nil, content: content, issue: issue, needsKeys: false, duplicate: false, stamp: nil)
            }
            guard input.canRead, safe(url), let stamp = input.stamp, stamp == Stamp(url), !within(url, root) else {
                return ambiguous(L10n.text("Not a supported incoming file."))
            }
            guard let readings else {
                return Entry(source: url, destination: nil, content: nil,
                             issue: L10n.text("Keys missing: import them to identify this file"),
                             needsKeys: true, duplicate: false, stamp: nil)
            }
            guard case .contents(let rows)? = readings[url], rows.count == 1, let row = rows.first,
                  row.kind != .unknown, let version = row.version else {
                return ambiguous(L10n.text("No single verified title, kind and version."))
            }
            let baseID = SourceCatalog.baseTitleId(for: row.titleId, kind: row.kind)
            let tag = " [\(hex(baseID))]"
            let matches = folders.filter {
                $0.lastPathComponent.uppercased().hasSuffix(tag) &&
                !$0.lastPathComponent.localizedCaseInsensitiveContains("Switch 2 Edition")
            }
            let existing = matches.count == 1 ? matches.first : nil
            let baseName = existing.map { String($0.lastPathComponent.dropLast(tag.count)) } ?? names(baseID)
            guard safe(root), matches.count <= 1, existing.map(safe) ?? true,
                  let title = baseName.flatMap(normalize),
                  existing.map({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) ?? true else {
                return ambiguous(L10n.text("No unambiguous game name or destination."), content: row)
            }
            let folder = existing ?? root.appendingPathComponent(title + tag, isDirectory: true)
            let stem: String
            if row.kind == .dlc {
                guard let dlc = names(row.titleId).flatMap(normalize), dlc != title else {
                    return ambiguous(L10n.text("No verified DLC name."), content: row)
                }
                stem = "\(dlc.hasPrefix(title + " - ") ? dlc : title + " - " + dlc) [\(hex(row.titleId))]"
            } else {
                stem = "\(title) [\(hex(row.titleId))] [v\(version)]"
            }
            let filename = "\(stem).\(url.pathExtension)"
            guard filename.utf8.count <= 255, folder.lastPathComponent.utf8.count <= 255 else {
                return ambiguous(L10n.text("The proposed name is too long."), content: row)
            }
            let destination = folder.appendingPathComponent(filename, isDirectory: false)
            let duplicate = exists(destination)
            if duplicate && (!safe(destination) || !(duplicateReviews?.matches(url, destination, stamp: stamp)
                ?? ((try? verifySame(url, destination)) != nil))) {
                return ambiguous(L10n.text("A different file already occupies the destination."), content: row)
            }
            return Entry(source: url, destination: destination, content: row, issue: nil, needsKeys: false,
                         duplicate: duplicate, stamp: input.stamp)
        }
        let destinations = Dictionary(grouping: entries.compactMap { $0.destination }, by: destinationKey)
        return entries.map { entry in
            guard let destination = entry.destination, destinations[destinationKey(destination), default: []].count > 1 else {
                return entry
            }
            return Entry(source: entry.source, destination: nil, content: entry.content,
                         issue: L10n.text("Multiple incoming files have the same destination."),
                         needsKeys: false, duplicate: false, stamp: nil)
        }
    }

    public static func store(_ entry: Entry, root: URL, discover: (URL, PackageContent) throws -> Bool,
                             trash: @escaping (URL) throws -> Void = OortSystem.trash,
                             withTrashPermission: (URL, () throws -> Void) throws -> Void = { _, commit in try commit() }) throws {
        try store(entry, root: root, discover: discover, trash: trash, copy: streamCopy, withTrashPermission: withTrashPermission)
    }

    static func store(_ entry: Entry, root: URL, discover: (URL, PackageContent) throws -> Bool,
                      trash: @escaping (URL) throws -> Void, copy: (URL, URL) throws -> Void,
                      withTrashPermission: (URL, () throws -> Void) throws -> Void = { _, commit in try commit() }) throws {
        guard let destination = entry.destination, let content = entry.content, let stamp = entry.stamp,
              within(destination, root), !within(entry.source, root) else { throw Failure.changed }
        let source = entry.source
        let folder = destination.deletingLastPathComponent()
        func recheck() throws {
            try Task.checkCancellation()
            guard safe(source), safe(destination), Stamp(source) == stamp else { throw Failure.changed }
        }
        try recheck()
        guard exists(destination) == entry.duplicate else { throw Failure.changed }
        let stored: Stamp
        if !entry.duplicate {
            let fm = FileManager.default
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let staging = folder.appendingPathComponent(".arcane-inbox-\(UUID().uuidString)", isDirectory: true)
            try recheck()
            try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: staging) }
            let candidate = staging.appendingPathComponent("copy")
            try copy(source, candidate)
            let verified = try verifySame(source, candidate)
            try recheck()
            guard renamex_np(candidate.path, destination.path, UInt32(RENAME_EXCL)) == 0,
                  let moved = Stamp(destination), verified.matchesAfterRename(moved) else { throw Failure.changed }
            stored = moved
        } else {
            stored = try verifySame(source, destination)
        }

        try recheck()
        guard Stamp(destination) == stored, try discover(destination, content) else { throw Failure.discovery }
        try Task.checkCancellation()
        try withTrashPermission(source) {
            try recheck()
            guard Stamp(destination) == stored else { throw Failure.changed }
            try trash(source)
        }
    }

    private static func verifySame(_ source: URL, _ destination: URL) throws -> Stamp {
        guard let lhs = Stamp(source), let rhs = Stamp(destination), lhs.bytes == rhs.bytes,
              lhs.device != rhs.device || lhs.inode != rhs.inode,
              try CloudArchiveInventory.hashes(at: source, includeMD5: false) ==
                CloudArchiveInventory.hashes(at: destination, includeMD5: false),
              Stamp(source) == lhs, Stamp(destination) == rhs else { throw Failure.changed }
        return rhs
    }

    private static func streamCopy(_ source: URL, _ candidate: URL) throws {
        let fd = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw Failure.changed }
        let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw Failure.changed }
        guard FileManager.default.createFile(atPath: candidate.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: candidate)
        defer { try? output.close() }
        try input.forEachChunk { chunk in
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
    }

    private static func hex(_ id: UInt64) -> String { String(format: "%016llX", id) }

    private static func normalize(_ name: String) -> String? {
        let text = name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: ":", with: " - ")
            .replacingOccurrences(of: "–", with: " - ")
            .replacingOccurrences(of: "—", with: " - ")
        let clean = text.components(separatedBy: CharacterSet(charactersIn: "/\\[]").union(.controlCharacters))
            .joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return clean.isEmpty || clean.hasPrefix(".") ? nil : clean
    }

    private static func destinationKey(_ url: URL) -> String {
        url.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func within(_ url: URL, _ root: URL) -> Bool {
        destinationKey(url.standardizedFileURL).hasPrefix(destinationKey(root.standardizedFileURL) + "/")
    }

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 || errno != ENOENT
    }

    /// Check every component, including a dangling link and a link in a not-yet-created destination.
    private static func safe(_ url: URL) -> Bool {
        let components = url.path.split(separator: "/")
        guard url.isFileURL, url.path.hasPrefix("/"),
              !components.contains("."), !components.contains("..") else { return false }
        var path = ""
        for component in components {
            path += "/" + component
            var info = stat()
            if lstat(path, &info) == 0 {
                if info.st_mode & S_IFMT == S_IFLNK { return false }
            } else if errno != ENOENT { return false }
        }
        return true
    }
}
