import Foundation
import Darwin

/// A game's build cache on this Mac (`<title ID>_build`): what the engine reuses so a rebuild compiles no shader twice.
public enum LocalBuildCache {
    /// The shader chain in a `b-<12 hex>.img` folder (`shader/cache` or an app's `msl`); nil unless there is exactly one.
    public static func chain(in folder: URL) -> String? {
        try? readChain(in: folder)
    }

    private static func readChain(in folder: URL) throws -> String? {
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: folder.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
        let ids = names.compactMap { name -> String? in
            guard name.hasPrefix("b-"), name.hasSuffix(".img") else { return nil }
            let id = String(name.dropFirst(2).dropLast(4))
            return id.utf8.count == 12 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } ? id : nil
        }
        return ids.count == 1 ? ids[0] : nil
    }

    public static func readChain(ofCache cache: URL) throws -> String? {
        let parts = cache.standardizedFileURL.pathComponents
        if parts.count > 2, parts[1] == "Volumes" {
            _ = try CloudArchiveInventory.node(at: URL(fileURLWithPath: "/Volumes/\(parts[2])"))
        }
        for directory in [cache, cache.appendingPathComponent("shader"), cache.appendingPathComponent("shader/cache")] {
            do {
                guard try CloudArchiveInventory.node(at: directory).st_mode & S_IFMT == S_IFDIR else {
                    throw CloudArchiveError.unsafePath
                }
            } catch CloudArchiveError.localMissing { return nil }
        }
        let folder = cache.appendingPathComponent("shader/cache")
        guard let chain = try readChain(in: folder) else { return nil }
        let image = try CloudArchiveInventory.node(at: folder.appendingPathComponent("b-\(chain).img"))
        guard image.st_mode & S_IFMT == S_IFREG, image.st_size > 0 else { throw CloudArchiveError.localChanged }
        return chain
    }

    public static func matchesInstalledApp(_ cache: URL, app: URL?) throws -> Bool {
        guard let app, let chain = try readChain(ofCache: cache) else { return false }
        return try readChain(in: app.appendingPathComponent("Contents/Resources/msl")) == chain
    }

    /// The chain of a cache folder; nil when it holds no finished shader image.
    public static func chain(ofCache cache: URL) -> String? {
        chain(in: cache.appendingPathComponent("shader/cache"))
    }

    /// The game's cache folder when it holds a finished shader image: the one a rebuild falls back on when the
    /// cloud can't be read or its cache download failed. A missing, empty or ambiguous folder is not a cache.
    public static func usable(atPath path: String?) -> URL? {
        path.map { URL(fileURLWithPath: $0) }.flatMap { chain(ofCache: $0) == nil ? nil : $0 }
    }

    /// Shaders the cache holds, from the engine's own "28,603 of 28,603 shaders ready" line.
    public static func shaderCount(ofCache cache: URL) -> Int? {
        guard let chain = chain(ofCache: cache),
              let text = try? String(contentsOf: cache.appendingPathComponent("shader/mac-b-\(chain).key"), encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.contains(" shaders ready") }),
              let ready = line.components(separatedBy: " of ").first else { return nil }
        return Int(ready.filter(\.isNumber))
    }

    /// A finished build's work folder becomes the game's cache; the cache it replaces goes to the Trash.
    public static func adopt(_ work: URL, as cache: URL,
                             retire: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        try adopt(work, as: cache, prepare: { source, candidate in
            if renamex_np(source.path, candidate.path, UInt32(RENAME_EXCL)) == 0 { return }
            guard errno == EXDEV else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let original = try CloudArchiveInventory.scan(source, kind: .cache)
            try FileManager.default.copyItem(at: source, to: candidate)
            guard try CloudArchiveInventory.scan(candidate, kind: .cache).withoutRootMtime == original.withoutRootMtime else {
                throw CloudArchiveError.localChanged
            }
        }, retire: retire)
    }

    static func adopt(_ work: URL, as cache: URL, prepare: (URL, URL) throws -> Void,
                      retire: (URL) throws -> Void) throws {
        let fm = FileManager.default
        guard work.standardizedFileURL.path != cache.standardizedFileURL.path else { return }
        guard let chain = try readChain(ofCache: work) else { throw CloudArchiveError.localChanged }
        let parent = cache.deletingLastPathComponent()
        let parts = parent.standardizedFileURL.pathComponents
        if parts.count > 2, parts[1] == "Volumes" {
            _ = try CloudArchiveInventory.node(at: URL(fileURLWithPath: "/Volumes/\(parts[2])"))
        }
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let volume = try CloudArchiveInventory.node(at: parent)
        func previousNode() throws -> stat? {
            do { return try CloudArchiveInventory.node(at: cache) }
            catch CloudArchiveError.localMissing { return nil }
        }
        let previous = try previousNode()
        guard previous.map({ $0.st_mode & S_IFMT == S_IFDIR }) ?? true else { throw CloudArchiveError.unsafePath }
        let stage = parent.appendingPathComponent(".arcane-build-cache-\(UUID())")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let candidate = stage.appendingPathComponent(cache.lastPathComponent)
        // Never recursively remove this directory: after the swap it holds the old cache.
        defer { _ = rmdir(stage.path) }
        do {
            try prepare(work, candidate)
            guard Self.chain(ofCache: candidate) == chain else { throw CloudArchiveError.localChanged }
            let image = candidate.appendingPathComponent("shader/cache/b-\(chain).img")
            let node = try CloudArchiveInventory.node(at: image)
            guard node.st_mode & S_IFMT == S_IFREG, node.st_size > 0 else { throw CloudArchiveError.localChanged }
            let current = try previousNode()
            let parentNow = try CloudArchiveInventory.node(at: parent)
            guard volume.st_dev == parentNow.st_dev, volume.st_ino == parentNow.st_ino,
                  previous?.st_dev == current?.st_dev, previous?.st_ino == current?.st_ino else {
                throw CloudArchiveError.localChanged
            }
            let exists = previous != nil
            guard renamex_np(candidate.path, cache.path, UInt32(exists ? RENAME_SWAP : RENAME_EXCL)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if !exists { return }
        } catch {
            // Before publication the only possible resident is the new, disposable candidate.
            try? fm.removeItem(at: candidate)
            throw error
        }
        try retire(candidate)
    }
}
