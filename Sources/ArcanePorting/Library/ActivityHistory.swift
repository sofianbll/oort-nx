import Foundation
import NXLibraryCore
import Darwin

package struct ActivityHistory {
    package enum Job: Equatable, Codable, Sendable {
        case build(BuildRequest)
        case cloud(CloudTransferQueue.Entry)
        case move(LibraryMoveRequest)
    }

    package enum Outcome: Equatable, Codable, Sendable {
        case succeeded, failed(String), cancelled
    }

    package struct Result: Identifiable, Codable, Sendable {
        package let id: UUID
        package let job: Job
        package let name: String?
        package let outcome: Outcome

        package var canRetry: Bool {
            if case .failed = outcome { return true }
            if case .cancelled = outcome, case .move = job { return true }
            return false
        }
    }

    package private(set) var entries: [Result] = []

    package init() {}

    package mutating func restore(_ previous: [Result]) {
        var seen = Set(entries.map(\.id))
        entries += previous.filter { result in
            if case .build(let request) = result.job, result.id != request.id { return false }
            if case .cloud(let request) = result.job, let token = request.token, token != result.id { return false }
            return seen.insert(result.id).inserted
        }
    }

    package mutating func record(id: UUID, job: Job, name: String?, outcome: Outcome) {
        clear(id)
        entries.insert(.init(id: id, job: job, name: name, outcome: outcome), at: 0)
    }

    package mutating func clear(_ id: UUID? = nil) {
        if let id { entries.removeAll { $0.id == id } }
        else { entries.removeAll() }
    }

    package func retry(_ id: UUID, submit: (Result) -> Bool) -> Bool {
        guard let result = entries.first(where: { $0.id == id && $0.canRetry }) else { return false }
        return submit(result)
    }
}

package struct LibraryMoveRequest: Equatable, Codable, Sendable {
    package let plan: CloudDriveFolders.MovePlan
    package let destination: String

    package init(plan: CloudDriveFolders.MovePlan, destination: String) {
        self.plan = plan
        self.destination = destination
    }
}

/// Separate from dismissible activity results. The confirmed plan, not a new scan of
/// the now partial source library, is the only safe input for another attempt.
package struct LibraryMoveJournal {
    package struct Pending: Codable, Equatable, Sendable {
        private let version: Int
        package let id: UUID
        package let request: LibraryMoveRequest
        package let sourcesRoot: String

        package init(id: UUID, request: LibraryMoveRequest, sourcesRoot: String) {
            version = 1
            self.id = id
            self.request = request
            self.sourcesRoot = sourcesRoot
        }

        fileprivate var isValid: Bool {
            version == 1 && CloudLibraryPreference.validSourcesRoot(sourcesRoot)
                && CloudDriveFolders.validMove(request.plan, to: request.destination)
        }
    }

    private let file: URL
    private static let maximumBytes = 64 * 1024 * 1024
    package init(in directory: URL) { file = directory.appendingPathComponent("cloud-library-move.json") }

    package func load() throws -> Pending? {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var status = stat()
        guard fstat(fd, &status) == 0, status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              (1...Self.maximumBytes).contains(Int(status.st_size)),
              let data = try handle.read(upToCount: Self.maximumBytes + 1), data.count <= Self.maximumBytes else {
            throw StorageBackendError.invalidConfiguration
        }
        let pending = try JSONDecoder().decode(Pending.self, from: data)
        guard pending.isValid else { throw StorageBackendError.invalidConfiguration }
        return pending
    }

    package func begin(_ pending: Pending) throws {
        guard pending.isValid else { throw StorageBackendError.invalidConfiguration }
        let fm = FileManager.default
        let directory = file.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stage = directory.appendingPathComponent(".cloud-move-\(UUID())")
        defer { try? fm.removeItem(at: stage) }
        let bytes = try JSONEncoder().encode(pending)
        guard bytes.count <= Self.maximumBytes else { throw StorageBackendError.invalidConfiguration }
        guard fm.createFile(atPath: stage.path, contents: bytes, attributes: [.posixPermissions: 0o600]) else {
            throw StorageBackendError.invalidConfiguration
        }
        let handle = try FileHandle(forWritingTo: stage)
        try handle.synchronize()
        try handle.close()
        try fm.linkItem(at: stage, to: file)
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    package func finish(_ pending: Pending) throws {
        guard try load() == pending else { throw StorageBackendError.invalidConfiguration }
        try FileManager.default.removeItem(at: file)
    }
}
