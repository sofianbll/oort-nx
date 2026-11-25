import Foundation

/// One entry of a library folder. Nothing here says which service holds it.
public struct ShelfNode: Equatable, Sendable {
    /// `other` is anything that is neither a plain file nor a folder (a shortcut, an online document): never followed, never read.
    public enum Kind: Equatable, Sendable { case folder, file, other }

    public let id: String
    public let name: String
    public let kind: Kind
    public let size: Int64?
    public let sha256: String?
    public let md5: String?

    public init(id: String, name: String, kind: Kind, size: Int64? = nil, sha256: String? = nil, md5: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.size = size
        self.sha256 = sha256
        self.md5 = md5
    }
}

/// Where a phone reads the player's library: a cloud drive, a chosen folder, the Mac over Wi-Fi. Read only by construction:
/// there is no call that writes, renames or deletes.
public protocol ShelfSource: Sendable {
    /// The library's own folder. A source never reads above it.
    var root: String { get }
    /// Every child of the folder, all pages read. Throws rather than returning part of the list.
    func children(of folder: String) async throws -> [ShelfNode]
    /// Writes exactly these bytes of the file to `destination`, which does not exist yet. The range is never empty.
    func fetch(_ file: ShelfNode, range: Range<Int64>, to destination: URL) async throws
}

/// Why a source or a download stopped. Cases carry no address, no identifier and no credential, so any of them can be shown or logged.
public enum ShelfError: Error, Equatable, Sendable {
    /// The player has not turned this source on.
    case sourceOff
    /// The player's rules do not allow this connection (mobile data).
    case networkNotAllowed
    case offline
    /// The connection broke on the way; the next try resumes.
    case interrupted
    case signInNeeded
    case accessDenied
    case notFound
    /// The account has no download left for now; trying again at once would not help.
    case quotaExceeded
    case busy(retryAfter: Int?)
    case server
    /// The source answered something this code does not accept.
    case badResponse
    case ambiguous
    case unsafeName
    case invalidManifest
    case unsigned
    case filesMissing
    case wrongSize
    case wrongDigest
    case noSpace(needed: Int64)
    case localFile

    /// A stable word for tests, logs and translations.
    public var code: String {
        switch self {
        case .sourceOff: "sourceOff"
        case .networkNotAllowed: "networkNotAllowed"
        case .offline: "offline"
        case .interrupted: "interrupted"
        case .signInNeeded: "signInNeeded"
        case .accessDenied: "accessDenied"
        case .notFound: "notFound"
        case .quotaExceeded: "quotaExceeded"
        case .busy: "busy"
        case .server: "server"
        case .badResponse: "badResponse"
        case .ambiguous: "ambiguous"
        case .unsafeName: "unsafeName"
        case .invalidManifest: "invalidManifest"
        case .unsigned: "unsigned"
        case .filesMissing: "filesMissing"
        case .wrongSize: "wrongSize"
        case .wrongDigest: "wrongDigest"
        case .noSpace: "noSpace"
        case .localFile: "localFile"
        }
    }

    var isTransient: Bool {
        switch self {
        case .interrupted, .server, .busy: true
        default: false
        }
    }
}

/// How often a transient failure is tried again. The waiting itself is injected, so a test never waits.
public struct ShelfRetry: Sendable {
    public static let longestWait = 60

    public let attempts: Int
    let wait: @Sendable (Int) async throws -> Void

    public init(attempts: Int = 4, wait: @escaping @Sendable (Int) async throws -> Void) {
        self.attempts = max(1, attempts)
        self.wait = wait
    }

    /// Seconds: 1, 2, 4… plus up to one second of jitter, or what the source asked for.
    public static let standard = Self { seconds in
        try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000 + UInt64.random(in: 0..<1_000_000_000))
    }

    public func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        for attempt in 1... {
            try Task.checkCancellation()
            do {
                return try await body()
            } catch let error as ShelfError where error.isTransient && attempt < attempts {
                var seconds = min(1 << (attempt - 1), 32)
                if case .busy(let asked?) = error {
                    guard asked <= Self.longestWait else { throw error }
                    seconds = max(seconds, asked)
                }
                try await wait(seconds)
            }
        }
        throw ShelfError.server
    }
}

/// SHA-256, injected: the portable core has no cryptography of its own.
public protocol ShelfHasher {
    mutating func update(_ data: Data)
    func hex() -> String
}

/// What the core asks of the system it runs on.
public struct ShelfCrypto: Sendable {
    public let sha256: @Sendable () -> any ShelfHasher
    /// Whether the signature over these bytes is the player's own Mac's.
    public let isSigned: @Sendable (_ message: Data, _ signature: Data) -> Bool

    public init(sha256: @escaping @Sendable () -> any ShelfHasher, isSigned: @escaping @Sendable (Data, Data) -> Bool) {
        self.sha256 = sha256
        self.isSigned = isSigned
    }

    public func digest(_ data: Data) -> String {
        var hasher = sha256()
        hasher.update(data)
        return hasher.hex()
    }
}
