import Darwin
import Foundation

/// A library's files name each other by absolute path. This turns a path under the folder Oort NX used up to 0.3.0
/// into the same path under its own, in JSON files and preferences.
public struct LibraryPaths {
    /// The files at the library's root that hold paths, or the games, profiles, sessions, queues and settings that may.
    /// Not here, on purpose: `library.json` (the catalog keeps its fingerprint), `cloud-library-move.json` (Drive
    /// folders only), the removal journal (it recognises files by their identity on disk) and every backup.
    static let files = [
        "catalog.json", "catalog.json.bak", "settings.json", "profiles.json", "players.json",
        "play-sessions.json", "play-sessions-totals.json", SessionHistoryState.filename,
        "activity-results.json", "build-queue.json", "cloud-transfer-queue.json",
    ]
    /// While this is there, an interrupted removal still has to be undone against the catalog as written.
    package static let removalJournal = "catalog-removal-pending.json"
    package static let inheritedRemoval = "catalog-removal-from-previous-library.json"
    private static let maximumBytes = 64 * 1024 * 1024

    let old: URL
    let new: URL
    /// Whether the path at this place under the old folder (empty for the folder itself) moves.
    let accepts: (_ relative: String) -> Bool

    /// A plain path or a `file:` URL under the old folder, moved; anything else as it is. Names are compared as macOS
    /// does, composed or decomposed, and what follows the folder keeps its own spelling.
    func rebased(_ text: String) -> String {
        let isURL = text.hasPrefix("file:///")
        let parts = text.dropFirst(isURL ? 7 : 0).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        func plain(_ part: String) -> String { isURL ? part.removingPercentEncoding ?? part : part }
        let root = old.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= root.count, zip(root, parts).allSatisfy({ $0 == plain($1) }) else { return text }
        let tail = parts.dropFirst(root.count)
        let names = tail.map(plain).filter { !$0.isEmpty }
        guard !names.contains(".."), accepts(names.joined(separator: "/")) else { return text }
        let head = isURL ? URL(fileURLWithPath: new.path, isDirectory: false).absoluteString : new.path
        return ([head] + tail).joined(separator: "/")
    }

    /// A preference value, however deep the path sits: text, list, dictionary or JSON kept as data.
    func rebased(value: Any) -> Any {
        switch value {
        case let text as String: return rebased(text)
        case let list as [Any]: return list.map { rebased(value: $0) }
        case let map as [String: Any]:
            var result: [String: Any] = [:]
            for (key, value) in map {
                let moved = rebased(key)
                result[map[moved] == nil ? moved : key] = rebased(value: value)
            }
            return result
        case let data as Data: return rewritten(json: data) ?? data
        default: return value
        }
    }

    /// Only the strings that move are written again: numbers, order, spacing and unknown fields stay byte for byte.
    /// Nil when nothing moves or the bytes are not JSON.
    func rewritten(json data: Data) -> Data? {
        func isJSON(_ data: Data) -> Bool { (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil }
        guard isJSON(data) else { return nil }
        let bytes = [UInt8](data), quote = UInt8(ascii: "\""), escape = UInt8(ascii: "\\"), slash = UInt8(ascii: "/")
        var result = Data(), copied = 0, index = 0
        while index < bytes.count {
            guard bytes[index] == quote else { index += 1; continue }
            var end = index + 1
            while end < bytes.count, bytes[end] != quote { end += bytes[end] == escape ? 2 : 1 }
            guard end < bytes.count else { return nil }
            let literal = bytes[index...end]
            if literal.contains(slash), let text = try? JSONDecoder().decode(String.self, from: Data(literal)) {
                let moved = rebased(text)
                if moved != text {
                    let encoder = JSONEncoder()
                    if !zip(literal, literal.dropFirst()).contains(where: { $0 == (escape, slash) }) {
                        encoder.outputFormatting = .withoutEscapingSlashes
                    }
                    guard let replacement = try? encoder.encode(moved) else { return nil }
                    result.append(contentsOf: bytes[copied..<index])
                    result.append(replacement)
                    copied = end + 1
                }
            }
            index = end + 1
        }
        guard copied > 0 else { return nil }
        result.append(contentsOf: bytes[copied...])
        return isJSON(result) ? result : nil
    }

    /// The bytes of a regular file of a plausible size; nil for anything else, which is left alone.
    static func read(_ file: URL) throws -> Data? {
        var status = stat()
        if lstat(file.path, &status) != 0 {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), status.st_size <= maximumBytes else { return nil }
        return try Data(contentsOf: file)
    }

    /// Writes aside, then swaps: the file is the old one or the new one, with the same permissions.
    static func replace(_ file: URL, with data: Data) throws {
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        let stage = try CatalogPublication.stage(data, in: file.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.setAttributes([.posixPermissions: mode ?? 0o600], ofItemAtPath: stage.path)
        guard rename(stage.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try CatalogPublication.synchronize(file.deletingLastPathComponent())
    }

    /// The links under `workspaces` that lead nowhere, relative to the library: reported, never removed. Build caches,
    /// which hold no source link and many files, are not read.
    public static func deadWorkspaceLinks(in root: URL) -> [String] {
        let fm = FileManager.default
        var dead: [String] = []
        func visit(_ folder: String, depth: Int) {
            for name in (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)) ?? [] {
                let relative = folder + "/" + name, path = root.appendingPathComponent(relative).path
                var status = stat()
                guard lstat(path, &status) == 0 else { continue }
                switch status.st_mode & mode_t(S_IFMT) {
                case mode_t(S_IFLNK): if stat(path, &status) != 0 { dead.append(relative) }
                case mode_t(S_IFDIR): if depth < 5 && !name.hasSuffix("_build") { visit(relative, depth: depth + 1) }
                default: break
                }
            }
        }
        visit("workspaces", depth: 0)
        return dead.sorted()
    }
}
