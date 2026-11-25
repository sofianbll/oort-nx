import Darwin
import Foundation

/// A library copied by Oort NX 0.5.0 still names files in the old folder. Once, at launch, each of those paths that
/// also exists in the new folder moves there. Every changed file and preference is first kept in `path-repair-backup`,
/// nothing is removed, and the old folder is never opened for writing.
public struct LibraryPathRepair {
    public enum Failure: Error, Equatable { case removalPending, unsafeBackup }

    static let marker = ".repaired-paths.json"
    static let backupFolder = "path-repair-backup"
    private static let preferenceBackup = "preferences.plist"

    private let paths: LibraryPaths
    private let replace: (URL, Data) throws -> Void

    public init(from old: URL, to new: URL) {
        self.init(from: old, to: new, replace: LibraryPaths.replace)
    }

    init(from old: URL, to new: URL, replace: @escaping (URL, Data) throws -> Void) {
        paths = LibraryPaths(old: old, new: new) { relative in
            // Follows links: a dead one is not an equivalent.
            FileManager.default.fileExists(atPath: new.appendingPathComponent(relative).path)
        }
        self.replace = replace
    }

    /// Returns true when the repair ran now. When it throws, or while a file fails its check, the next launch tries
    /// again: each step can be repeated.
    @discardableResult
    public func prepare(checks: [String: DevelopmentProfileImporter.Check], preferences: () throws -> [String: Any],
                        savePreferences: ([String: Any]) throws -> Void) throws -> Bool {
        let root = paths.new
        func present(_ name: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) }
        guard LibraryMove.moved(root), !present(Self.marker) else { return false }
        // No other copy writes this library, and no catalog writer runs, while it is rewritten.
        let lease = try DowngradeCheckpoint.ProfileLease(in: root)
        defer { withExtendedLifetime(lease) {} }
        return try CatalogStore(directory: root, kinds: .base, legacy: nil).locked {
            guard !present(LibraryPaths.removalJournal) else { throw Failure.removalPending }
            var changes: [(name: String, old: Data, new: Data)] = []
            var waiting = false
            for name in LibraryPaths.files {
                guard let data = try LibraryPaths.read(root.appendingPathComponent(name)) else { continue }
                // A damaged file is left to its own recovery.
                do { try checks[name]?(data, root) } catch { waiting = true; continue }
                guard let moved = paths.rewritten(json: data) else { continue }
                try checks[name]?(moved, root)
                changes.append((name, data, moved))
            }
            let values = try preferences()
            var moved: [String: Any] = [:], kept: [String: Any] = [:]
            for (key, value) in values {
                let next = paths.rebased(value: value)
                if !(value as AnyObject).isEqual(next) { moved[key] = next; kept[key] = value }
            }
            if !changes.isEmpty || !moved.isEmpty { try backUp(changes.map { ($0.name, $0.old) }, preferences: kept) }
            for change in changes {
                let file = root.appendingPathComponent(change.name)
                guard try LibraryPaths.read(file) == change.old else { throw InstallationFileReadError.sourceChanged }
                try replace(file, change.new)
            }
            if !moved.isEmpty { try savePreferences(moved) }
            if !waiting {
                let done = ["files": changes.map(\.name), "preferences": moved.keys.sorted()]
                try JSONEncoder().encode(done).write(to: root.appendingPathComponent(Self.marker), options: .atomic)
            }
            return true
        }
    }

    /// A copy already kept is never overwritten: a later attempt that finds something else keeps it beside, numbered.
    private func backUp(_ files: [(String, Data)], preferences: [String: Any]) throws {
        let folder = paths.new.appendingPathComponent(Self.backupFolder, isDirectory: true)
        guard mkdir(folder.path, 0o700) == 0 || errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var status = stat()
        guard lstat(folder.path, &status) == 0, status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure.unsafeBackup }
        var files = files
        if !preferences.isEmpty {
            files.append((Self.preferenceBackup,
                          try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)))
        }
        for (name, data) in files {
            var file = folder.appendingPathComponent(name), number = 1
            while let kept = try LibraryPaths.read(file), kept != data {
                number += 1
                file = folder.appendingPathComponent("\(name).\(number)")
            }
            if try LibraryPaths.read(file) != nil { continue }
            let stage = try CatalogPublication.stage(data, in: folder)
            defer { try? FileManager.default.removeItem(at: stage) }
            try CatalogPublication.atomic.publish(stage, file, false) {}
        }
        try CatalogPublication.synchronize(folder)
        try CatalogPublication.synchronize(paths.new)
    }
}
