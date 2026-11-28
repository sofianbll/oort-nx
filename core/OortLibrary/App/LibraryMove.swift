import Crypto
import Foundation

/// Oort NX used to keep its data in Arcane's folder, under Arcane's identifier. The first launch under its own
/// identifier copies that folder into Oort NX's, checks every file, moves the paths the copy names (`LibraryPaths`),
/// then uses it. The original is only read: an interrupted or refused copy changes nothing, and Oort NX 0.3.0 still
/// opens it.
public struct LibraryMove {
    public enum Failure: Error, LocalizedError, Equatable {
        case unsafeFile, sourceChanged, interrupted, preferencesUnavailable

        public var errorDescription: String? {
            let context = AppLocale(language: .automatic, region: nil)
            switch self {
            case .unsafeFile: return L10n.text("The library copy contains a symbolic link or an unsupported file. The original data has not been changed.", context: context)
            case .sourceChanged: return L10n.text("The original library changed during the copy. Close the other launcher copy and try again.", context: context)
            case .interrupted: return L10n.text("Some launcher data could not be read. The original data has not been changed.", context: context)
            case .preferencesUnavailable: return L10n.text("The development preferences could not be saved. Try again.", context: context)
            }
        }
    }

    static let marker = ".moved-library.json"
    static let preferenceFile = ".moved-preferences.plist"
    /// Never carried over: scratch, logs, Finder's layout, and the old folder's own way back.
    static let skipped: Set<String> = ["Temp", "Logs", ".DS_Store", "DowngradeProtection", ".catalog.lock"]
    /// The update choices name the old repository.
    static let skippedPreferences: Set<String> = [
        "NXLibrary_UpdateRepository", "NXLibrary_UpdateLastCheck", "NXLibrary_UpdateLaterAt", "NXLibrary_UpdateLaterVersion",
    ]
    /// A cloned file above this is compared by size: reading gigabytes again would hold the first launch.
    static let hashedBytes: Int64 = 64 * 1024 * 1024

    private struct State: Codable {
        var version = 1
        var ready: Bool
        var files: Int
    }
    private enum Entry: Equatable { case folder, file(Int64, String), link(String) }

    private let fm: FileManager
    private let source: URL
    private let destination: URL

    public init(from source: URL, to destination: URL, fileManager: FileManager = .default) {
        fm = fileManager
        self.source = source
        self.destination = destination
    }

    /// True when this folder began as a verified copy, so the old one is still the way back.
    public static func moved(_ destination: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: destination.appendingPathComponent(marker).path)
    }

    package static func contains(_ url: URL, in root: URL) -> Bool {
        guard url.isFileURL else { return false }
        func starts(_ path: URL, _ prefix: URL) -> Bool {
            path.pathComponents.starts(with: prefix.pathComponents) { $0.caseInsensitiveCompare($1) == .orderedSame }
        }
        return starts(url.standardizedFileURL, root.standardizedFileURL)
            || starts(url.resolvingSymlinksInPath(), root.resolvingSymlinksInPath())
    }

    /// Returns true when the copy was made or completed now.
    public func prepare(preferences: () throws -> [String: Any], savePreferences: ([String: Any]) throws -> Void) throws -> Bool {
        if try kind(destination) != nil {
            let marker = destination.appendingPathComponent(Self.marker)
            if try kind(marker) != nil {
                guard let state = try? JSONDecoder().decode(State.self, from: Data(contentsOf: marker)) else { throw Failure.interrupted }
                if state.ready { return false }
                try finish(state, savePreferences: savePreferences)
                return true
            }
            guard try !hasLibrary(destination) else { return false }
        }
        guard try kind(source) == S_IFDIR, try hasLibrary(source) else { return false }
        // Copies from 0.3.1 on hold this lease while they run; the caller refuses a running 0.3.0.
        let lease = open(source.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard lease >= 0 else { throw Failure.interrupted }
        defer { close(lease) }
        guard flock(lease, LOCK_EX | LOCK_NB) == 0 else { throw Failure.sourceChanged }

        let before = try snapshot(source)
        let values = carried(try preferences())
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent("." + destination.lastPathComponent + "-copy-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) } // Only the staging folder created by this call; moved away on success.
        for relative in before.keys.sorted() { // A folder sorts before what it holds.
            let from = source.appendingPathComponent(relative), to = stage.appendingPathComponent(relative)
            switch before[relative]! {
            case .folder:
                let mode = try fm.attributesOfItem(atPath: from.path)[.posixPermissions] as? NSNumber
                try fm.createDirectory(at: to, withIntermediateDirectories: false, attributes: [.posixPermissions: mode ?? 0o755])
            case .file: try fm.copyItem(at: from, to: to)
            case .link(let target): try fm.createSymbolicLink(atPath: to.path, withDestinationPath: rebased(target))
            }
        }
        guard try snapshot(source) == before,
              try snapshot(stage) == before.mapValues({ if case .link(let target) = $0 { return .link(rebased(target)) } else { return $0 } }),
              NSDictionary(dictionary: carried(try preferences())).isEqual(to: values)
        else { throw Failure.sourceChanged }
        // A path follows the copy. What was not copied (logs, scratch) keeps naming the only file there is.
        let paths = LibraryPaths(old: source, new: destination) { relative in
            (try? kind(source.appendingPathComponent(relative))) == nil || (try? kind(stage.appendingPathComponent(relative))) != nil
        }
        // This intent owns identities and absolute paths in the original library; it is not a transaction in the copy.
        if before[LibraryPaths.removalJournal] != nil {
            try fm.moveItem(at: stage.appendingPathComponent(LibraryPaths.removalJournal),
                            to: stage.appendingPathComponent(LibraryPaths.inheritedRemoval))
        }
        for name in LibraryPaths.files {
            let file = stage.appendingPathComponent(name)
            if let data = try LibraryPaths.read(file), let moved = paths.rewritten(json: data) {
                try LibraryPaths.replace(file, with: moved)
            }
        }
        try PropertyListSerialization.data(fromPropertyList: values.mapValues { paths.rebased(value: $0) }, format: .binary, options: 0)
            .write(to: stage.appendingPathComponent(Self.preferenceFile), options: .atomic)
        let state = State(ready: false, files: before.count)
        try JSONEncoder().encode(state).write(to: stage.appendingPathComponent(Self.marker), options: .atomic)
        try CatalogPublication.synchronize(stage)
        // A folder without a library (logs, a launch that stopped early) is kept beside, never mixed in or deleted.
        if try kind(destination) != nil {
            let aside = parent.appendingPathComponent(destination.lastPathComponent + " (before the move) " + UUID().uuidString)
            guard OortSystem.rename(destination.path, aside.path, .noReplace) == 0 else { throw Failure.interrupted }
        }
        // Never replaces a folder: a second copy starting at the same moment stops here.
        guard OortSystem.rename(stage.path, destination.path, .noReplace) == 0 else { throw Failure.interrupted }
        try CatalogPublication.synchronize(parent)
        try finish(state, savePreferences: savePreferences)
        return true
    }

    private func hasLibrary(_ root: URL) throws -> Bool {
        try ["catalog.json", "library.json", "settings.json"].contains { try kind(root.appendingPathComponent($0)) == S_IFREG }
    }

    private func finish(_ state: State, savePreferences: ([String: Any]) throws -> Void) throws {
        let file = destination.appendingPathComponent(Self.preferenceFile)
        guard try kind(file) == S_IFREG,
              let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any]
        else { throw Failure.interrupted }
        try savePreferences(values)
        var ready = state
        ready.ready = true
        try JSONEncoder().encode(ready).write(to: destination.appendingPathComponent(Self.marker), options: .atomic)
        try? fm.removeItem(at: file)
    }

    private func carried(_ values: [String: Any]) -> [String: Any] {
        values.filter { !Self.skippedPreferences.contains($0.key) && !$0.key.hasPrefix("com.apple.") }
    }

    /// A link into the old folder leads to the same place in the new one.
    private func rebased(_ target: String) -> String {
        LibraryPaths(old: source, new: destination) { _ in true }.rebased(target)
    }

    private func snapshot(_ root: URL) throws -> [String: Entry] {
        var result: [String: Entry] = [:]
        func visit(_ folder: String, depth: Int) throws {
            guard depth < 64, result.count < 1_000_000 else { throw Failure.unsafeFile }
            for name in try fm.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)
            where !(folder.isEmpty && (Self.skipped.contains(name) || name == Self.marker || name == Self.preferenceFile)) {
                let relative = folder.isEmpty ? name : folder + "/" + name
                let url = root.appendingPathComponent(relative)
                switch try kind(url) {
                case S_IFDIR?:
                    result[relative] = .folder
                    try visit(relative, depth: depth + 1)
                case S_IFREG?:
                    let size = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1
                    result[relative] = .file(size, size > Self.hashedBytes ? "" : try digest(url))
                case S_IFLNK?: result[relative] = .link(try fm.destinationOfSymbolicLink(atPath: url.path))
                default: throw Failure.unsafeFile
                }
            }
        }
        try visit("", depth: 0)
        return result
    }

    private func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        try handle.forEachChunk { hash.update(data: $0) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func kind(_ url: URL) throws -> mode_t? {
        var status = stat()
        if lstat(url.path, &status) == 0 { return status.st_mode & mode_t(S_IFMT) }
        if errno == ENOENT { return nil }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
