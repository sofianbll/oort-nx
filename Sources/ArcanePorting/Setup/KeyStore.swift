import Foundation
import Darwin
import NXLibraryCore

extension KeyIssue {
    public var message: String {
        switch self {
        case .unreadable: return L10n.text("The key file could not be read.")
        case .missingHeaderKey: return L10n.text("The key file has no header_key.")
        case .invalidLine(let line): return L10n.format("Invalid key line number %@.", [String(describing: line)])
        }
    }
}

public final class KeyStore {
    public let keyURL: URL
    private let fm: FileManager
    /// Publication is one same-directory rename: failure leaves the existing key in place.
    internal var publish: (URL, URL) throws -> Void = { incoming, destination in
        guard rename(incoming.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fm = fileManager
        self.keyURL = directory.appendingPathComponent("prod.keys")
    }

    func readStatus() -> LocalKeyStatus {
        do {
            guard let mode = try permissions(at: keyURL, kind: S_IFREG) else { return .required }
            let parent = try permissions(at: keyURL.deletingLastPathComponent(), kind: S_IFDIR)
            let count = try readValidated(at: keyURL).count
            return .available(applicationGenerations: count, needsPrivatePermissions: mode != 0o600 || parent != 0o700)
        } catch let issue as KeyIssue {
            return .invalid(issue)
        } catch {
            return .invalid(.unreadable)
        }
    }

    private func permissions(at url: URL, kind: mode_t) throws -> mode_t? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw KeyIssue.unreadable
        }
        guard info.st_mode & S_IFMT == kind else { throw KeyIssue.unreadable }
        return info.st_mode & 0o7777
    }

    private func readValidated(at url: URL) throws -> (count: Int, data: Data) {
        let managed = url.standardizedFileURL == keyURL.standardizedFileURL
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | (managed ? O_NOFOLLOW : 0))
        guard fd >= 0 else { throw KeyIssue.unreadable }
        let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let limit = 1_048_576
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              let data = try? input.read(upToCount: limit + 1), data.count <= limit,
              let text = String(data: data, encoding: .utf8) else {
            throw KeyIssue.unreadable
        }
        var hasHeader = false
        var generations: Set<Int> = []
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, !parts[1].isEmpty else {
                throw KeyIssue.invalidLine(index + 1)
            }
            if parts[0] == "header_key" {
                guard KeyCheck.hex(parts[1])?.count == 32 else { throw KeyIssue.invalidLine(index + 1) }
                hasHeader = true
            }
            if parts[0].hasPrefix("key_area_key_application_"),
               let n = Int(parts[0].suffix(2), radix: 16) {
                generations.insert(n)
            }
        }
        guard hasHeader else { throw KeyIssue.missingHeaderKey }
        return (generations.count, data)
    }

    /// Only the existing install/import paths may tighten a managed copy. Never follow a symlink.
    package func secureManagedCopy() throws {
        try restrict(keyURL.deletingLastPathComponent(), to: 0o700, kind: S_IFDIR)
        try restrict(keyURL, to: 0o600, kind: S_IFREG)
    }

    private func restrict(_ url: URL, to mode: mode_t, kind: mode_t) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return }
            throw CocoaError(.fileWriteNoPermission)
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == kind,
              kind != S_IFREG || info.st_nlink == 1 else { throw CocoaError(.fileWriteNoPermission) }
        if info.st_mode & 0o7777 != mode, fchmod(fd, mode) != 0 { throw CocoaError(.fileWriteNoPermission) }
    }

    @discardableResult
    public func importKey(from source: URL) throws -> Int {
        let (count, data) = try readValidated(at: source)
        try fm.createDirectory(at: keyURL.deletingLastPathComponent(),
                               withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try restrict(keyURL.deletingLastPathComponent(), to: 0o700, kind: S_IFDIR)
        let tmp = keyURL.deletingLastPathComponent()
            .appendingPathComponent(".prod.keys-\(UUID()).tmp")
        defer { try? fm.removeItem(at: tmp) }
        // Created private: the copy is never readable by others, not even between the write and a chmod.
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: tmp.path]) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        try publish(tmp, keyURL)
        return count
    }
}
