import CryptoKit
import Foundation
import OortCore

/// Google Drive as a library source: two calls, `files.list` and `files.get`, with a read-only scope. Nothing here can write.
public struct DriveSource: ShelfSource {
    public let root: String
    let access: DriveAccess
    let transport: any DriveTransport
    /// What large ranges go through; the same as `transport` unless the app downloads in the background.
    let large: any DriveTransport
    let endpoints: DriveEndpoints
    let scratch: URL

    static let listLimit: Int64 = 8 << 20
    static let maximumPages = 200

    init(root: String, access: DriveAccess, transport: any DriveTransport, large: (any DriveTransport)? = nil, endpoints: DriveEndpoints = .google,
         scratch: URL) {
        self.large = large ?? transport
        self.root = root
        self.access = access
        self.transport = transport
        self.endpoints = endpoints
        self.scratch = scratch
    }

    static func isID(_ text: String) -> Bool {
        text != "root" && text != "appDataFolder" && text.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_-]{0,127}\z"#, options: .regularExpression) != nil
    }

    private struct Page: Decodable {
        struct File: Decodable {
            let id: String, name: String, mimeType: String, size: String?, sha256Checksum: String?, md5Checksum: String?
        }
        let files: [File], nextPageToken: String?, incompleteSearch: Bool?
    }

    public func children(of folder: String) async throws -> [ShelfNode] {
        guard Self.isID(folder) else { throw ShelfError.badResponse }
        // "If the token is rejected for any reason, it should be discarded, and pagination should be restarted."
        do { return try await pages(of: folder) }
        catch is PageRefused { }
        do { return try await pages(of: folder) }
        catch is PageRefused { throw ShelfError.badResponse }
    }

    private struct PageRefused: Error {}

    private func pages(of folder: String) async throws -> [ShelfNode] {
        var nodes: [ShelfNode] = []
        var token: String?
        var seen: Set<String> = []
        for _ in 0..<Self.maximumPages {
            var parts = URLComponents(url: endpoints.files, resolvingAgainstBaseURL: false)!
            parts.queryItems = [.init(name: "q", value: "'\(folder)' in parents and trashed = false"),
                                .init(name: "fields", value: "nextPageToken,incompleteSearch,files(id,name,mimeType,size,sha256Checksum,md5Checksum)"),
                                .init(name: "pageSize", value: "1000"), .init(name: "supportsAllDrives", value: "true"),
                                .init(name: "includeItemsFromAllDrives", value: "true")]
            if let token { parts.queryItems!.append(.init(name: "pageToken", value: token)) }
            // A plus is a space in a query string, and a page token may hold one.
            parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            let data = try await send(URLRequest(url: parts.url!), limit: Self.listLimit, accepts: [200]) { status in
                status == 400 && token != nil ? PageRefused() : nil
            } read: { try Data(contentsOf: $0) }
            guard let page = try? JSONDecoder().decode(Page.self, from: data), page.incompleteSearch != true else { throw ShelfError.badResponse }
            for file in page.files {
                guard Self.isID(file.id) else { throw ShelfError.badResponse }
                let kind: ShelfNode.Kind = switch file.mimeType {
                case "application/vnd.google-apps.folder": .folder
                case let type where type.hasPrefix("application/vnd.google-apps."): .other
                default: .file
                }
                let size = try file.size.map { text in
                    guard let size = Int64(text), size >= 0 else { throw ShelfError.badResponse }
                    return size
                }
                nodes.append(.init(id: file.id, name: file.name, kind: kind, size: size, sha256: file.sha256Checksum?.lowercased(),
                                   md5: file.md5Checksum?.lowercased()))
            }
            guard let next = page.nextPageToken, !next.isEmpty else { return nodes }
            guard seen.insert(next).inserted else { throw ShelfError.badResponse }
            token = next
        }
        throw ShelfError.badResponse
    }

    public func fetch(_ file: ShelfNode, range: Range<Int64>, to destination: URL) async throws {
        guard Self.isID(file.id), !range.isEmpty, let size = file.size, range.upperBound <= size else { throw ShelfError.badResponse }
        var parts = URLComponents(url: endpoints.files.appendingPathComponent(file.id), resolvingAgainstBaseURL: false)!
        // `acknowledgeAbuse` is never sent: a file Drive calls abusive stays where it is.
        parts.queryItems = [.init(name: "alt", value: "media"), .init(name: "supportsAllDrives", value: "true")]
        var request = URLRequest(url: parts.url!)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        // A manifest or a small file is not worth a background task.
        let isLarge = range.count > 256 << 10
        do { try await fetch(request, range, size, destination, through: isLarge ? large : transport) }
        // The system left it waiting: once more, in this process.
        catch ShelfError.interrupted where isLarge { try await fetch(request, range, size, destination, through: transport) }
    }

    private func fetch(_ request: URLRequest, _ range: Range<Int64>, _ size: Int64, _ destination: URL, through: any DriveTransport) async throws {
        try await send(request, through: through, limit: Int64(range.count), accepts: [206], check: { reply in
            guard let value = reply.header("Content-Range"),
                  let match = value.wholeMatch(of: /bytes (\d{1,18})-(\d{1,18})\/(\d{1,18})/) else { throw ShelfError.badResponse }
            guard Int64(match.3) == size else { throw ShelfError.wrongSize }
            guard Int64(match.1) == range.lowerBound, Int64(match.2) == range.upperBound - 1 else { throw ShelfError.badResponse }
        }, read: { body in
            let length = try FileManager.default.attributesOfItem(atPath: body.path)[.size] as? NSNumber
            guard length?.int64Value == Int64(range.count) else { throw ShelfError.interrupted }
            try FileManager.default.moveItem(at: body, to: destination)
        })
    }

    @discardableResult
    private func send<T: Sendable>(_ request: URLRequest, through: (any DriveTransport)? = nil, limit: Int64, accepts: Set<Int>, special: (Int) -> (any Error)? = { _ in nil },
                                   check: (DriveReply) throws -> Void = { _ in }, read: (URL) throws -> T) async throws -> T {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var refused: DriveSecret?
        while true {
            let token = try await access.token(refused: refused)
            var request = request
            request.setValue("Bearer " + token.reveal(), forHTTPHeaderField: "Authorization")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let body = scratch.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: body) }
            // An error body may be longer than the range.
            let reply = try await (through ?? transport).send(request, to: body, limit: max(limit, 64 * 1024))
            if reply.status == 401, refused == nil {
                refused = token
                continue
            }
            if let error = special(reply.status) { throw error }
            guard accepts.contains(reply.status) else { throw Self.failure(reply, body: body) }
            guard ["", "identity"].contains(reply.header("Content-Encoding") ?? "") else { throw ShelfError.badResponse }
            let length = try FileManager.default.attributesOfItem(atPath: body.path)[.size] as? NSNumber
            guard let length, length.int64Value <= limit else { throw ShelfError.badResponse }
            try check(reply)
            do { return try read(body) }
            catch let error as ShelfError { throw error }
            catch { throw ShelfError.localFile }
        }
    }

    private struct Failure: Decodable {
        struct Body: Decodable { struct Reason: Decodable { let reason: String }; let errors: [Reason]? }
        let error: Body
    }

    /// Only Drive's reason word is read; its message may repeat the request.
    private static func failure(_ reply: DriveReply, body: URL) -> ShelfError {
        let reason = (try? Data(contentsOf: body)).flatMap { try? JSONDecoder().decode(Failure.self, from: $0) }?.error.errors?.first?.reason ?? ""
        let after = reply.header("Retry-After").flatMap { Int($0) }
        switch reply.status {
        case 401: return .signInNeeded
        case 403:
            switch reason {
            case "rateLimitExceeded", "userRateLimitExceeded": return .busy(retryAfter: after)
            case "dailyLimitExceeded", "downloadQuotaExceeded", "quotaExceeded": return .quotaExceeded
            default: return .accessDenied
            }
        case 404: return .notFound
        case 416: return .wrongSize
        case 429: return .busy(retryAfter: after)
        case 500...: return .server
        default: return .badResponse
        }
    }
}

extension ShelfCrypto {
    private struct Hasher: ShelfHasher {
        var hash = SHA256()
        mutating func update(_ data: Data) { hash.update(data: data) }
        func hex() -> String { hash.finalize().map { String(format: "%02x", $0) }.joined() }
    }

    /// CryptoKit, with the Mac's public key as the only signer.
    public static func apple(signer: Data) -> Self {
        Self(sha256: { Hasher() }, isSigned: { message, signature in
            guard let key = try? P256.Signing.PublicKey(derRepresentation: signer),
                  let seal = try? P256.Signing.ECDSASignature(derRepresentation: signature) else { return false }
            return key.isValidSignature(seal, for: message)
        })
    }
}

/// The optional connector, off until the player turns it on. An app that does not list it cannot reach Google.
public struct DriveConnection: Sendable {
    public static let id = "google-drive"

    public let connector: ShelfConnector
    /// For the sign-in screen.
    public let access: DriveAccess
    let client: DriveClient
    let vault: any DriveVault
    let endpoints: DriveEndpoints

    /// `background`: the session that goes on while the app is suspended, and the folder where an answer waits for a process that was ended.
    public init(invite: DriveInvite, scratch: URL, background: DriveSession, allowsMeteredNetwork: @escaping @Sendable () -> Bool) {
        self.init(invite: invite, vault: DriveKeychain(account: invite.client.id), transport: DriveSession(allowsMeteredNetwork: allowsMeteredNetwork),
                  large: background, endpoints: .google, scratch: scratch)
    }

    @_spi(Checks) public init(invite: DriveInvite, scratch: URL, background: DriveSession, allowsMeteredNetwork: @escaping @Sendable () -> Bool,
                              endpoints: DriveEndpoints) {
        self.init(invite: invite, vault: DriveKeychain(account: invite.client.id), transport: DriveSession(allowsMeteredNetwork: allowsMeteredNetwork),
                  large: background, endpoints: endpoints, scratch: scratch)
    }

    /// The hosts and the permissions, for the screen that asks before any code is known.
    public static var outline: ShelfConnector {
        ShelfConnector(id: id, hosts: DriveEndpoints.google.hosts, permissions: [.network, .readLibrary, .storeBuilds],
                       open: { throw ShelfError.sourceOff }, forget: {})
    }

    public func signIn() -> DriveSignIn { DriveSignIn(client: client, endpoints: endpoints) }
    /// Whether this device holds a sign-in. Asks nothing of the network.
    public var isSignedIn: Bool { (try? vault.read()) != nil }

    init(invite: DriveInvite, vault: any DriveVault, transport: any DriveTransport, large: (any DriveTransport)? = nil, endpoints: DriveEndpoints, scratch: URL) {
        (client, self.vault, self.endpoints) = (invite.client, vault, endpoints)
        let access = DriveAccess(client: invite.client, vault: vault, transport: transport, endpoints: endpoints, scratch: scratch)
        self.access = access
        connector = ShelfConnector(id: Self.id, hosts: endpoints.hosts, permissions: [.network, .readLibrary, .storeBuilds],
                                   open: { DriveSource(root: invite.folder, access: access, transport: transport, large: large, endpoints: endpoints, scratch: scratch) },
                                   forget: { try await access.forget() })
    }
}
