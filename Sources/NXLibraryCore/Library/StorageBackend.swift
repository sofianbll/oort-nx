import Foundation

package final class CloudTitleLeases: @unchecked Sendable {
    private let lock = NSLock()
    private var titles: [String: UUID] = [:]

    package init() {}

    package func begin(_ title: String) -> UUID? {
        lock.withLock {
            guard titles[title] == nil else { return nil }
            let token = UUID()
            titles[title] = token
            return token
        }
    }

    package func end(_ title: String, token: UUID) {
        lock.withLock { if titles[title] == token { titles[title] = nil } }
    }
}

/// A backend-relative identifier, not a filesystem URL or a remote specification.
public struct StorageObjectKey: Codable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) { self.value = value }
}

public struct StorageObject: Hashable, Codable, Sendable {
    public let key: StorageObjectKey
    public let size: Int64
    /// Lowercase algorithm names (e.g. `sha256`, `md5`) and hexadecimal values.
    public let hashes: [String: String]

    public init(key: StorageObjectKey, size: Int64, hashes: [String: String]) {
        self.key = key
        self.size = size
        self.hashes = hashes
    }
}

public struct StorageProgress: Equatable, Sendable {
    public let bytesTransferred: Int64
    public let totalBytes: Int64
    public let bytesPerSecond: Double?
    public let etaSeconds: Double?
    public let isVerifying: Bool

    public init(bytesTransferred: Int64, totalBytes: Int64, bytesPerSecond: Double? = nil,
                etaSeconds: Double? = nil, isVerifying: Bool = false) {
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.etaSeconds = etaSeconds
        self.isVerifying = isVerifying
    }
}

public enum StorageBackendError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidKey
    case invalidLocalFile
    case invalidFingerprint
    case alreadyExists
    case notFound
    case hashMismatch
    case publicationFailed
    case backendUnavailable
    case processFailed(status: Int32)
    case invalidResponse
}

/// Operations throw `CancellationError` when cancelled. Transfer callbacks run off the caller's executor.
public protocol StorageBackend: Sendable {
    func list() async throws -> [StorageObject]
    /// Lists the immediate directory names at the root, without reading descendants.
    func rootDirectories() async throws -> [String]
    /// Lists immediate objects under a directory prefix, with keys relative to the same root.
    func list(in prefix: StorageObjectKey) async throws -> [StorageObject]
    /// Publishes a new object only after verification. Serialise writers for a key; this is not compare-and-swap.
    func put(_ source: URL, as object: StorageObject, progress: (@Sendable (StorageProgress) -> Void)?) async throws
    /// Downloads to a new local file; does not replace an existing destination.
    func get(_ key: StorageObjectKey, to destination: URL, progress: (@Sendable (StorageProgress) -> Void)?) async throws
    func delete(_ key: StorageObjectKey) async throws
    /// Requires matching size and SHA-256, downloading the bytes to hash if necessary.
    func verify(_ object: StorageObject) async throws
}

extension StorageBackend {
    public func list(in prefix: StorageObjectKey) async throws -> [StorageObject] {
        let parent = prefix.value + "/"
        return try await list().filter {
            $0.key.value.hasPrefix(parent) && !$0.key.value.dropFirst(parent.count).contains("/")
        }
    }

    public func put(_ source: URL, as object: StorageObject) async throws {
        try await put(source, as: object, progress: nil)
    }

    public func get(_ key: StorageObjectKey, to destination: URL) async throws {
        try await get(key, to: destination, progress: nil)
    }
}
