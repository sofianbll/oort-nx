import CryptoKit
import Foundation
import OortCore

/// The player's own Google client. Nobody else's: Oort has none, and the Mac's token never travels.
public struct DriveClient: Equatable, Sendable {
    /// `ios`: no secret, Google answers on a private address of the app. `desktop`: Google answers on 127.0.0.1 (Android).
    public enum Kind: String, Sendable { case ios, desktop }

    public let id: String
    public let kind: Kind
    /// Google gives desktop clients one and says it is not confidential. Never present for `ios`.
    let secret: DriveSecret?

    static let suffix = ".apps.googleusercontent.com"

    /// The scheme Google reserves for an iOS client: the identifier, reversed.
    public var callbackScheme: String { "com.googleusercontent.apps." + id.dropLast(Self.suffix.count) }
    var redirect: String { callbackScheme + ":/oauth2redirect" }
}

/// What the Mac shows as a code to scan: which client, which folder, whose builds to trust. It opens nothing by itself.
public struct DriveInvite: Equatable, Sendable {
    public let client: DriveClient
    /// Identifier of the library folder.
    public let folder: String
    /// The Mac's public key (P-256, DER): the only signer of builds this phone shows.
    public let signer: Data

    static let limit = 1024

    /// Nil for anything unexpected. A code that carries a token is refused, so that a Mac can never learn to send one.
    public static func parse(_ text: String) -> Self? {
        guard text.utf8.count <= limit, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              Set(object.keys).isSubset(of: ["oort", "kind", "client", "secret", "folder", "signer"]), object["oort"] == "drive-1",
              let kind = object["kind"].flatMap(DriveClient.Kind.init), let id = object["client"],
              id.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,127}\.apps\.googleusercontent\.com\z"#, options: .regularExpression) != nil,
              let folder = object["folder"], DriveSource.isID(folder), let signer = object["signer"].flatMap({ Data(base64Encoded: $0) }),
              (try? P256.Signing.PublicKey(derRepresentation: signer)) != nil else { return nil }
        let secret = object["secret"]
        guard kind == .desktop || secret == nil,
              secret.map({ $0.range(of: #"^[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) != nil }) ?? true else { return nil }
        return Self(client: .init(id: id, kind: kind, secret: secret.map(DriveSecret.init)), folder: folder, signer: signer)
    }
}

/// Google's addresses. Nothing else is ever contacted.
struct DriveEndpoints: Sendable {
    let authorize: URL
    let token: URL
    let revoke: URL
    let files: URL

    static let google = Self(authorize: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                             token: URL(string: "https://oauth2.googleapis.com/token")!,
                             revoke: URL(string: "https://oauth2.googleapis.com/revoke")!,
                             files: URL(string: "https://www.googleapis.com/drive/v3/files")!)

    var hosts: [String] { Set([authorize, token, revoke, files].compactMap(\.host)).sorted() }
}

/// The sign-in page's address, and what comes back from it. The browser itself belongs to the app.
public struct DriveSignIn: Sendable {
    /// Reading only. Nothing wider is ever asked for or accepted.
    public static let scope = "https://www.googleapis.com/auth/drive.readonly"

    public let client: DriveClient
    let verifier: DriveSecret
    let state: DriveSecret
    let redirect: String
    let endpoints: DriveEndpoints

    /// One per sign-in. Both values come from the system's random generator.
    public init(client: DriveClient) {
        self.init(client: client, verifier: Self.random(), state: Self.random(), redirect: client.redirect, endpoints: .google)
    }

    init(client: DriveClient, verifier: String, state: String, redirect: String, endpoints: DriveEndpoints) {
        self.client = client
        self.verifier = DriveSecret(verifier)
        self.state = DriveSecret(state)
        self.redirect = redirect
        self.endpoints = endpoints
    }

    public var page: URL {
        var parts = URLComponents(url: endpoints.authorize, resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "client_id", value: client.id), .init(name: "redirect_uri", value: redirect),
                            .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scope),
                            .init(name: "code_challenge", value: Self.challenge(verifier.reveal())),
                            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state.reveal())]
        return parts.url!
    }

    /// The code in the address Google came back on, only for this very request.
    func code(in callback: URL) throws -> DriveSecret {
        guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false), let asked = URLComponents(string: redirect),
              parts.scheme?.lowercased() == asked.scheme?.lowercased(), parts.host == asked.host, parts.path == asked.path else { throw ShelfError.badResponse }
        let items = parts.queryItems ?? []
        func only(_ name: String) -> String? {
            let values = items.filter { $0.name == name }
            return values.count == 1 ? values[0].value : nil
        }
        guard only("state") == state.reveal() else { throw ShelfError.badResponse }
        if items.contains(where: { $0.name == "error" }) { throw ShelfError.accessDenied }
        guard let code = only("code"), !code.isEmpty else { throw ShelfError.badResponse }
        return DriveSecret(code)
    }

    static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    static func random() -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<48).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The one place that holds the access token, in memory only, and renews it.
public actor DriveAccess {
    private let client: DriveClient
    private let vault: any DriveVault
    private let transport: any DriveTransport
    private let endpoints: DriveEndpoints
    private let scratch: URL
    private let now: @Sendable () -> Date
    private var current: (token: DriveSecret, until: Date)?
    private var renewal: Task<DriveSecret, any Error>?

    init(client: DriveClient, vault: any DriveVault, transport: any DriveTransport, endpoints: DriveEndpoints = .google, scratch: URL,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.vault = vault
        self.transport = transport
        self.endpoints = endpoints
        self.scratch = scratch
        self.now = now
    }

    /// `refused`: a token the source just turned down.
    func token(refused: DriveSecret? = nil) async throws -> DriveSecret {
        if let current, current.token != refused, current.until > now() { return current.token }
        // Two requests refused together renew once.
        if let renewal { return try await renewal.value }
        let task = Task { try await renew() }
        renewal = task
        defer { renewal = nil }
        return try await task.value
    }

    /// Ends a sign-in. The refresh token goes straight to the vault.
    public func finish(_ signIn: DriveSignIn, callback: URL) async throws {
        let code = try signIn.code(in: callback)
        var fields = ["grant_type": "authorization_code", "code": code.reveal(), "code_verifier": signIn.verifier.reveal(),
                      "redirect_uri": signIn.redirect, "client_id": client.id]
        fields["client_secret"] = client.secret?.reveal()
        let answer = try await ask(fields)
        guard answer.scope?.split(separator: " ") == [Substring(DriveSignIn.scope)], let refresh = answer.refresh_token, !refresh.isEmpty
        else { throw ShelfError.accessDenied }
        try vault.write(DriveSecret(refresh))
        keep(answer)
    }

    /// Erases what this device holds. Google's own list of connections is where the player withdraws the permission itself:
    /// Google's revocation call would cut every client of the same project, the Mac's included.
    public func forget() throws {
        current = nil
        renewal?.cancel()
        try vault.erase()
    }

    private struct Answer: Decodable {
        let access_token: String, expires_in: Double, token_type: String, scope: String?, refresh_token: String?
    }

    private func renew() async throws -> DriveSecret {
        guard let refresh = try vault.read() else { throw ShelfError.signInNeeded }
        var fields = ["grant_type": "refresh_token", "refresh_token": refresh.reveal(), "client_id": client.id]
        fields["client_secret"] = client.secret?.reveal()
        do {
            let answer = try await ask(fields)
            guard answer.scope.map({ $0 == DriveSignIn.scope }) ?? true else { throw ShelfError.accessDenied }
            if let next = answer.refresh_token { try vault.write(DriveSecret(next)) }
            return keep(answer)
        } catch ShelfError.signInNeeded {
            // Google will not take it again.
            current = nil
            try? vault.erase()
            throw ShelfError.signInNeeded
        }
    }

    @discardableResult
    private func keep(_ answer: Answer) -> DriveSecret {
        let token = DriveSecret(answer.access_token)
        current = (token, now().addingTimeInterval(max(0, answer.expires_in - 60)))
        return token
    }

    private func ask(_ fields: [String: String]) async throws -> Answer {
        var request = URLRequest(url: endpoints.token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(fields.sorted { $0.key < $1.key }
            .map { $0.key + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "&").utf8)
        let file = scratch.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let reply = try await transport.send(request, to: file, limit: 64 * 1024)
        switch reply.status {
        case 200:
            guard let answer = try? JSONDecoder().decode(Answer.self, from: Data(contentsOf: file)), answer.token_type == "Bearer",
                  !answer.access_token.isEmpty else { throw ShelfError.badResponse }
            return answer
        case 400, 401: throw ShelfError.signInNeeded
        case 429: throw ShelfError.busy(retryAfter: reply.header("Retry-After").flatMap { Int($0) })
        case 500...: throw ShelfError.server
        default: throw ShelfError.badResponse
        }
    }
}
