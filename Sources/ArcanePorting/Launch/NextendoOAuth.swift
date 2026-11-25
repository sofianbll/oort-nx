import CryptoKit
import Foundation
import NXLibraryCore
import OSLog
import Security

public enum NextendoError: LocalizedError, Equatable {
    case clientID, browser, timeout, authorization, service, expired, storage, signedOut, onlinePlayUnavailable, profileHost, presenceHost
    case check(NextendoCheckDiagnostic)
    case discordUnlinked, emailUnverified

    public var checkDiagnostic: NextendoCheckDiagnostic? {
        if case .check(let diagnostic) = self { return diagnostic }
        return nil
    }

    public var errorDescription: String? {
        switch self {
        case .clientID: return L10n.text("Enter a valid public Nextendo client ID in Online services.")
        case .browser: return L10n.text("Could not open the Nextendo sign-in window.")
        case .timeout: return L10n.text("Nextendo sign-in timed out. Try again.")
        case .authorization: return L10n.text("Nextendo did not authorize sign-in. Check the client ID and its permissions.")
        case .service, .check: return L10n.text("Could not check the Nextendo account. Try again.")
        case .expired: return L10n.text("Nextendo sign-in expired. Sign in again.")
        case .storage: return L10n.text("Could not access the shared Nextendo sign-in. Close any running games and try again.")
        case .signedOut: return L10n.text("Sign in to Nextendo in Online services before playing online.")
        case .onlinePlayUnavailable, .discordUnlinked, .emailUnverified:
            return L10n.text("Nextendo does not allow online play for this account. Check your profile on the website.")
        case .profileHost: return L10n.text("Rebuild this game to use this profile’s Nextendo account.")
        case .presenceHost: return L10n.text("Rebuild this game to play online without sharing its title.")
        }
    }
}

/// One authorization request. The browser never sees the verifier; the token endpoint never gets the state.
public struct NextendoAuthorization: Sendable {
    public let clientID: String
    public let redirect: URL
    public let url: URL
    let verifier: String
    let state: String

    public init(clientID: String, port: UInt16) throws {
        guard Self.validClientID(clientID) else { throw NextendoError.clientID }
        self.clientID = clientID
        verifier = try Self.random(bytes: 32)
        state = try Self.random(bytes: 16)
        redirect = URL(string: "http://127.0.0.1:\(port)/callback")!
        var request = URLComponents(string: "https://nextendo.network/oauth/authorize")!
        // Request the same permissions the host uses, including `profil` for the player's Mii.
        request.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect.absoluteString),
            .init(name: "scope", value: "identity friends game.matchmaking presence profil"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: Self.challenge(verifier)),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        url = request.url!
    }

    public static func validClientID(_ value: String) -> Bool {
        (1...128).contains(value.utf8.count) && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || $0 == 45 || $0 == 46 || $0 == 95
        }
    }

    static func challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func random(bytes: Int) throws -> String {
        var data = Data(count: bytes)
        guard data.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }) == errSecSuccess
        else { throw NextendoError.browser }
        return base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Ignore unrelated loopback traffic; report a refusal only for a callback with our state.
    public func code(from callback: URL) throws -> String? {
        guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.scheme == redirect.scheme, parts.host == redirect.host, parts.port == redirect.port,
              parts.percentEncodedPath == redirect.path, parts.user == nil, parts.password == nil, parts.fragment == nil,
              let fields = parts.queryItems else { return nil }
        guard fields.filter({ $0.name == "state" }).map(\.value) == [state] else { return nil }
        let codes = fields.filter { $0.name == "code" }
        if fields.contains(where: { $0.name == "error" }) { throw NextendoError.authorization }
        guard codes.count == 1, let code = codes.first?.value, !code.isEmpty, code.utf8.count <= 4096 else { return nil }
        return code
    }
}

public struct NextendoOAuth: Sendable {
    // Use the same endpoint as nxnative for both authorization-code and refresh grants.
    private static let tokenEndpoint = URL(string: "https://nextendo.network/api/oauth/token")!
    public let store: NextendoTokenStore
    private let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let onResult: @Sendable (NextendoCheckDiagnostic) -> Void
    private static let log = Logger(subsystem: "io.github.sofianbll.oortnx", category: "nextendo")

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 12
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    public init(store: NextendoTokenStore = NextendoTokenStore(),
                onResult: @escaping @Sendable (NextendoCheckDiagnostic) -> Void = { _ in }) {
        self.init(store: store, onResult: onResult) { request in
            let path = request.url?.path ?? ""
            let limit = ["/api/friends", "/api/profile", "/api/avatar", "/api/recent-players"].contains(path)
                || path.hasPrefix("/api/friends/") ? 1_048_576 : 65_536
            return try await BoundedDownload.data(for: request, session: Self.session, limit: limit)
        }
    }

    package init(store: NextendoTokenStore,
                 onResult: @escaping @Sendable (NextendoCheckDiagnostic) -> Void = { _ in },
                 send: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.store = store
        self.onResult = onResult
        self.send = send
    }

    public func signIn(_ attempt: NextendoAuthorization, code: String) async throws -> String {
        try await signInSession(attempt, code: code).user.username
    }

    func signInSession(_ attempt: NextendoAuthorization, code: String) async throws -> (user: UserInfo, access: String) {
        guard let session = try await store.withLock({ file in
            let token = try await exchange(clientID: attempt.clientID, grant: "authorization_code", [
                "code": code, "redirect_uri": attempt.redirect.absoluteString, "code_verifier": attempt.verifier,
            ])
            let user: UserInfo
            do { user = try await userInfo(clientID: attempt.clientID, access: token.access) }
            catch NextendoHTTPError.unauthorized { throw NextendoError.service }
            try file.write(token.refresh)
            return (user, token.access)
        }) else { throw NextendoError.storage }
        return session
    }

    /// Checking an account rotates the token under the same lock the engine takes.
    public func accountName(clientID: String) async throws -> String? {
        guard let access = try await refreshAccess(clientID: clientID) else { return nil }
        do { return try await userInfo(clientID: clientID, access: access).username }
        catch NextendoHTTPError.unauthorized { throw NextendoError.service }
    }

    func refreshAccess(clientID: String) async throws -> String? {
        guard try store.hasToken() else { return nil }
        return try await store.withLock(create: false) { file -> String? in
            guard let refresh = try file.read() else { return nil }
            // Once sent, finish the rotation even if the UI leaves; the old token may already be invalid.
            let token = try await Task.detached {
                try await exchange(clientID: clientID, grant: "refresh_token", ["refresh_token": refresh])
            }.value
            try file.write(token.refresh)
            return token.access
        } ?? nil
    }

    public func signOut() async throws {
        try await store.withLock(create: false) { file in try file.write(nil) }
    }

    private struct Token: Decodable {
        let access: String
        let refresh: String
        enum CodingKeys: String, CodingKey {
            case access = "access_token", refresh = "refresh_token"
        }
    }

    private func exchange(clientID: String, grant: String, _ fields: [String: String]) async throws -> Token {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let fields = fields.merging(["client_id": clientID, "grant_type": grant]) { _, value in value }
        var request = try request(Self.tokenEndpoint, clientID: clientID)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved)!)"
        }.joined(separator: "&").utf8)
        let (body, status) = try await response(request)
        if status == 400 || status == 401,
           (try? JSONDecoder().decode(Refusal.self, from: body))?.error == "invalid_grant" {
            // Another front end may have signed in with a different client. Don't delete its credential.
            throw grant == "refresh_token" ? NextendoError.expired : NextendoError.authorization
        }
        if status != 200, grant == "refresh_token" {
            throw NextendoError.check(.init(route: Self.tokenEndpoint.path, code: status))
        }
        if [400, 401, 403].contains(status) { throw NextendoError.authorization }
        guard status == 200, let token = try? JSONDecoder().decode(Token.self, from: body),
              Self.validBearer(token.access),
              NextendoTokenStore.valid(token.refresh) else { throw NextendoError.service }
        return token
    }

    private struct Refusal: Decodable { let error: String }
    static func validBearer(_ token: String) -> Bool {
        (1...8192).contains(token.utf8.count) && token.utf8.allSatisfy { (33...126).contains($0) }
    }

    struct UserInfo {
        let username: String
        let displayName: String?
        let pid: UInt64?
        let friendCode: String?
    }

    func userInfo(clientID: String, access: String) async throws -> UserInfo {
        let (body, status) = try await get("/api/oauth/userinfo", clientID: clientID, access: access)
        if status == 401 { throw NextendoHTTPError.unauthorized }
        guard status == 200, let account = try? NextendoDocument(data: body) else {
            throw NextendoError.check(.init(route: "/api/oauth/userinfo", code: status))
        }
        let fields = [account, account.object("account"), account.object("identity")].compactMap { $0 }
        let names = fields.compactMap { $0.text("username") }
        let pids = fields.compactMap { $0.pid }
        guard let username = names.first, names.allSatisfy({ $0 == username }),
              pids.allSatisfy({ $0 == pids.first }) else { throw NextendoError.service }
        return UserInfo(username: username, displayName: fields.lazy.compactMap { $0.text("display_name") }.first,
                        pid: pids.first, friendCode: fields.lazy.compactMap { $0.text("friend_code") }.first)
    }

    func get(_ path: String, query: [URLQueryItem] = [], clientID: String?, access: String?) async throws -> (Data, Int) {
        try await api(path, query: query, clientID: clientID, access: access)
    }

    func post(_ path: String, json: Data, clientID: String, access: String) async throws -> (Data, Int) {
        try await api(path, clientID: clientID, access: access, json: json)
    }

    private func api(_ path: String, query: [URLQueryItem] = [], clientID: String?, access: String?,
                     json: Data? = nil) async throws -> (Data, Int) {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "nextendo.network"
        url.path = path
        if !query.isEmpty { url.queryItems = query }
        guard let endpoint = url.url else { throw NextendoError.service }
        var request = try request(endpoint, clientID: clientID)
        if let access { request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization") }
        if let json {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json
        }
        let result = try await response(request)
        try Task.checkCancellation()
        return result
    }

    private func request(_ endpoint: URL, clientID: String?) throws -> URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        if let clientID {
            guard NextendoAuthorization.validClientID(clientID) else { throw NextendoError.clientID }
            request.setValue(clientID, forHTTPHeaderField: "X-Nextendo-Client-Id")
        }
        return request
    }

    private func response(_ request: URLRequest) async throws -> (Data, Int) {
        // These paths are fixed by the callers. Never include query items or error userInfo.
        let route = request.url?.path ?? ""
        do {
            let (data, response) = try await send(request)
            guard let http = response as? HTTPURLResponse, http.url == request.url else { throw NextendoError.service }
            record(.init(route: route, code: http.statusCode))
            return (data, http.statusCode)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            let diagnostic = NextendoCheckDiagnostic(route: route, code: error.code.rawValue)
            record(diagnostic)
            throw NextendoError.check(diagnostic)
        } catch {
            throw NextendoError.service
        }
    }

    private func record(_ diagnostic: NextendoCheckDiagnostic) {
        Self.log.log(level: (200..<300).contains(diagnostic.code) ? .default : .error,
                     "\(diagnostic.route, privacy: .public) · \(diagnostic.code, privacy: .public)")
        onResult(diagnostic)
    }
}

enum NextendoHTTPError: Error { case unauthorized }
