import Darwin
import Foundation

/// nxnative's shared credential, not part of either Arcane profile. The host can rotate it at any time.
public struct NextendoTokenStore: Sendable {
    public let directory: URL
    private static let name = "refresh_token"
    private static let limit = 8192

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/nxnative/nextendo", isDirectory: true)) {
        self.directory = directory
    }

    /// A rename exposes either complete version to a reader, even without the writer's lock.
    public func hasToken() throws -> Bool {
        guard let fd = try openDirectory(create: false) else { return false }
        defer { close(fd) }
        return try Self.read(in: fd) != nil
    }

    /// Keep the same cross-process lock across the refresh request and publication of the rotated token.
    func withLock<T>(create: Bool = true, _ operation: (Locked) async throws -> T) async throws -> T? {
        guard let parent = try openDirectory(create: create) else { return nil }
        defer { close(parent) }
        let fd = openat(parent, ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw NextendoError.storage }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
              info.st_mode & 0o777 == 0o600 else { throw NextendoError.storage }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(30)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR, clock.now < deadline else { throw NextendoError.storage }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try Task.checkCancellation()
        return try await operation(Locked(parent: parent))
    }

    struct Locked {
        fileprivate let parent: Int32

        func read() throws -> String? { try NextendoTokenStore.read(in: parent) }

        func write(_ token: String?) throws {
            guard let token else {
                guard unlinkat(parent, name, 0) == 0 || errno == ENOENT else { throw NextendoError.storage }
                return
            }
            guard NextendoTokenStore.valid(token) else { throw NextendoError.storage }
            let stage = ".refresh_token.\(UUID().uuidString)"
            let fd = openat(parent, stage, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw NextendoError.storage }
            defer { _ = unlinkat(parent, stage, 0) }
            let data = Data(token.utf8)
            let saved = data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { return false }
                    offset += count
                }
                return fchmod(fd, 0o600) == 0 && fsync(fd) == 0
            }
            guard close(fd) == 0, saved, renameat(parent, stage, parent, name) == 0 else { throw NextendoError.storage }
        }
    }

    static func valid(_ token: String) -> Bool {
        (1...limit).contains(token.utf8.count) && !token.utf8.contains(0)
            && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func openDirectory(create: Bool) throws -> Int32? {
        if create {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
            } catch {
                throw NextendoError.storage
            }
        }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if !create && errno == ENOENT { return nil }
            throw NextendoError.storage
        }
        var info = stat()
        if fstat(fd, &info) == 0, info.st_uid == geteuid(),
           info.st_mode & 0o777 == 0o700 || (create && fchmod(fd, 0o700) == 0) { return fd }
        close(fd)
        throw NextendoError.storage
    }

    private static func read(in parent: Int32) throws -> String? {
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw NextendoError.storage
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0, (1...Int64(limit)).contains(info.st_size) else { throw NextendoError.storage }
        var data = Data(count: Int(info.st_size))
        let complete = data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard complete, let token = String(data: data, encoding: .utf8),
              valid(token) else { throw NextendoError.storage }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
