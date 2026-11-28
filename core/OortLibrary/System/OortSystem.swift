#if canImport(Darwin)
import Darwin
import os
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Foundation

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

    /// Whether this system has a Trash that `trash` can move to.
    public static var hasTrash: Bool {
        #if canImport(Darwin)
        true
        #else
        false
        #endif
    }

    /// Moves a file or folder to the user's Trash.
    public static func trash(_ url: URL) throws {
        #if canImport(Darwin)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        #else
        throw Unsupported(operation: "trash")
        #endif
    }

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
