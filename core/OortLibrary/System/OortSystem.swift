#if canImport(Darwin)
import Darwin
import os
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Foundation
import Synchronization

/// The calls that differ from one system to the next, in one place (R3: scripts/check_oort_core.py allows the C
/// library and a branch on the system only in this folder). The Mac's variant is the code the app has always run;
/// the others give the same answer, or throw `Unsupported` where the system has no equivalent yet.
public enum OortSystem {
    /// The system has no equivalent of this operation yet.
    public struct Unsupported: Error, Equatable, Sendable {
        public let operation: String
    }

    // MARK: - C library calls whose names a type's own methods hide

    public static func open(_ path: String, _ flags: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.open(path, flags)
        #elseif canImport(Glibc)
        Glibc.open(path, flags)
        #else
        Musl.open(path, flags)
        #endif
    }

    @discardableResult
    public static func close(_ descriptor: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.close(descriptor)
        #elseif canImport(Glibc)
        Glibc.close(descriptor)
        #else
        Musl.close(descriptor)
        #endif
    }

    public static func read(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.read(descriptor, buffer, count)
        #elseif canImport(Glibc)
        Glibc.read(descriptor, buffer, count)
        #else
        Musl.read(descriptor, buffer, count)
        #endif
    }

    // MARK: - File status

    /// A time stamp of a file, as the file system keeps it.
    public struct FileTime: Equatable, Sendable {
        public let seconds: Int
        public let nanoseconds: Int
    }

    public static func modified(_ status: stat) -> FileTime {
        #if canImport(Darwin)
        FileTime(seconds: Int(status.st_mtimespec.tv_sec), nanoseconds: Int(status.st_mtimespec.tv_nsec))
        #else
        FileTime(seconds: Int(status.st_mtim.tv_sec), nanoseconds: Int(status.st_mtim.tv_nsec))
        #endif
    }

    public static func changed(_ status: stat) -> FileTime {
        #if canImport(Darwin)
        FileTime(seconds: Int(status.st_ctimespec.tv_sec), nanoseconds: Int(status.st_ctimespec.tv_nsec))
        #else
        FileTime(seconds: Int(status.st_ctim.tv_sec), nanoseconds: Int(status.st_ctim.tv_nsec))
        #endif
    }

    /// When the file was created, where `stat` says it (Apple systems); nil where it does not.
    public static func born(_ status: stat) -> FileTime? {
        #if canImport(Darwin)
        FileTime(seconds: Int(status.st_birthtimespec.tv_sec), nanoseconds: Int(status.st_birthtimespec.tv_nsec))
        #else
        nil
        #endif
    }

    /// The bytes of a directory entry's name.
    public static func nameLength(_ entry: UnsafeMutablePointer<dirent>) -> Int {
        #if canImport(Darwin)
        Int(entry.pointee.d_namlen)
        #else
        withUnsafeBytes(of: &entry.pointee.d_name) { $0.firstIndex(of: 0) ?? $0.count }
        #endif
    }

    // MARK: - Files

    /// How `rename` treats an existing destination.
    public enum RenameMode: Sendable {
        /// Fail with `EEXIST` rather than replace it.
        case noReplace
        /// Exchange the two, atomically.
        case swap
    }

    /// Renames `from` to `to` atomically, never replacing what is there unless the two are swapped. Returns 0, or -1
    /// with `errno` set, like `rename(2)`; a system that cannot do it atomically refuses with `ENOSYS` and never falls
    /// back to a rename that replaces.
    public static func rename(_ from: String, _ to: String, _ mode: RenameMode) -> Int32 {
        #if canImport(Darwin)
        renamex_np(from, to, UInt32(mode == .swap ? RENAME_SWAP : RENAME_EXCL))
        #else
        errno = ENOSYS
        return -1
        #endif
    }

    /// Clones an open file to `path` when the file system can share its blocks; false when the caller must copy.
    public static func clone(_ descriptor: Int32, to path: String) -> Bool {
        #if canImport(Darwin)
        fclonefileat(descriptor, AT_FDCWD, path, 0) == 0
        #else
        false
        #endif
    }

    /// Where removed files go. Only the app, run from its `.app` bundle, uses the system's Trash. Any other process (a
    /// test, a probe, a throwaway executable, however it was started) gets a folder of its own: `OORT_TRASH` when
    /// scripts/check sets it, a new temporary folder otherwise.
    public struct Trash: Sendable {
        /// Moves a file or folder there.
        public let put: @Sendable (URL) throws -> Void
        /// The folder a file of this volume can be renamed into.
        public let folder: @Sendable (URL) throws -> URL
        /// The folder of a test or probe Trash; nil for the system's.
        public let root: URL?

        public init(put: @escaping @Sendable (URL) throws -> Void, folder: @escaping @Sendable (URL) throws -> URL,
                    root: URL? = nil) {
            self.put = put
            self.folder = folder
            self.root = root
        }

        /// The user's Trash.
        public static let system = Trash(put: { url in
            #if canImport(Darwin)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            #else
            throw Unsupported(operation: "trash")
            #endif
        }, folder: { url in
            #if canImport(Darwin)
            try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)
            #else
            throw Unsupported(operation: "trash")
            #endif
        })

        /// A Trash in `root`: an item keeps its name, with a number when the name is taken.
        public static func folder(at root: URL) -> Trash {
            Trash(put: { url in
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var target = root.appendingPathComponent(url.lastPathComponent)
                var number = 1
                while FileManager.default.fileExists(atPath: target.path) {
                    number += 1
                    target = root.appendingPathComponent("\(url.lastPathComponent) \(number)")
                }
                try FileManager.default.moveItem(at: url, to: target)
            }, folder: { _ in
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                return root
            }, root: root)
        }
    }

    /// Whether this system has a Trash of its own.
    public static var hasTrash: Bool {
        #if canImport(Darwin)
        true
        #else
        false
        #endif
    }

    private static let chosenTrash = Mutex<Trash?>(nil)

    /// The Trash this process uses: `OORT_TRASH`; the system's for the app run from its bundle; else a folder of its own.
    public static var currentTrash: Trash {
        chosenTrash.withLock { chosen in
            if let chosen { return chosen }
            let trash: Trash
            if let path = ProcessInfo.processInfo.environment["OORT_TRASH"], !path.isEmpty {
                trash = .folder(at: URL(fileURLWithPath: path, isDirectory: true))
            } else if isBundledApp && !isTestProcess {
                trash = .system
            } else {
                trash = .folder(at: FileManager.default.temporaryDirectory
                    .appendingPathComponent("oort-trash-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true))
            }
            chosen = trash
            return trash
        }
    }

    /// Replaces the Trash of this process (a test that checks how a failing Trash is handled).
    public static func useTrash(_ trash: Trash) { chosenTrash.withLock { $0 = trash } }

    /// The app as players run it: from an `.app` bundle (probes and tests run bare executables or test bundles).
    private static var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private static var isTestProcess: Bool {
        if NSClassFromString("XCTestCase") != nil { return true }
        let name = ProcessInfo.processInfo.processName
        return name.hasSuffix(".xctest") || name.hasSuffix("PackageTests") || name.hasSuffix("-test-runner")
    }

    /// Moves a file or folder to this process's Trash.
    public static func trash(_ url: URL) throws { try currentTrash.put(url) }

    /// The Trash folder a file of `url`'s volume can be renamed into.
    public static func trashFolder(for url: URL) throws -> URL { try currentTrash.folder(url) }

    /// Runs `body` so that the objects it leaves to the system are released at its end (Apple systems).
    public static func withPool<T>(_ body: () throws -> T) rethrows -> T {
        #if canImport(Darwin)
        try autoreleasepool(invoking: body)
        #else
        try body()
        #endif
    }

    /// The free bytes of the volume of `url`: what macOS can free for an important write, then the plain figure.
    public static func freeSpace(at url: URL) -> (important: Int64?, plain: Int64?) {
        #if canImport(Darwin)
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                      .volumeAvailableCapacityKey])
        return (values?.volumeAvailableCapacityForImportantUsage, values?.volumeAvailableCapacity.map(Int64.init))
        #else
        let free = (try? FileManager.default.attributesOfFileSystem(forPath: url.path))?[.systemFreeSize] as? NSNumber
        return (nil, free?.int64Value)
        #endif
    }

    /// The bytes of the regular files under `path`, without following links; with `includingHidden` false, entries
    /// whose name starts with a dot (and what they hold) are skipped. One `lstat` per entry, as `du` does.
    public static func regularFileBytes(at path: String, includingHidden: Bool) -> Int64 {
        #if canImport(Darwin)
        var total: Int64 = 0
        guard let root = strdup(path) else { return 0 }
        defer { free(root) }
        var roots: [UnsafeMutablePointer<CChar>?] = [root, nil]
        guard let fts = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return 0 }
        defer { fts_close(fts) }
        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            if !includingHidden, entry.pointee.fts_level > 0, entry.pointee.fts_name == CChar(UInt8(ascii: ".")) {
                if info == FTS_D { fts_set(fts, entry, FTS_SKIP) }
                continue
            }
            if info == FTS_F, let stat = entry.pointee.fts_statp {
                total += Int64(stat.pointee.st_size)
            }
        }
        return total
        #else
        var status = stat()
        guard lstat(path, &status) == 0 else { return 0 }
        if status.st_mode & S_IFMT == S_IFREG { return Int64(status.st_size) }
        guard status.st_mode & S_IFMT == S_IFDIR, let directory = opendir(path) else { return 0 }
        defer { closedir(directory) }
        var total: Int64 = 0
        while let entry = readdir(directory) {
            let length = nameLength(entry)
            let name = withUnsafeBytes(of: &entry.pointee.d_name) { String(decoding: $0.prefix(length), as: UTF8.self) }
            if name == "." || name == ".." || (!includingHidden && name.hasPrefix(".")) { continue }
            total += regularFileBytes(at: path + "/" + name, includingHidden: includingHidden)
        }
        return total
        #endif
    }

    // MARK: - Preferences and the system log

    /// Writes the preferences of `domain` to disk now; false when the system refuses.
    public static func synchronizePreferences(domain: String) -> Bool {
        #if canImport(Darwin)
        CFPreferencesAppSynchronize(domain as CFString)
        #else
        UserDefaults(suiteName: domain)?.synchronize() ?? false
        #endif
    }

    /// Records an error in the system log; the message stays private there (Apple systems), on standard error elsewhere.
    public static func logError(subsystem: String, category: String, _ message: String) {
        #if canImport(Darwin)
        Logger(subsystem: subsystem, category: category).error("\(message, privacy: .private)")
        #else
        FileHandle.standardError.write(Data("\(subsystem) [\(category)] \(message)\n".utf8))
        #endif
    }
}
