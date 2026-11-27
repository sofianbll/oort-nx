import Foundation
import OortLibrary

public struct NextendoCheckDiagnostic: Equatable, Sendable {
    public let route: String
    public let code: Int

    public func message(context: AppLocale) -> String {
        switch code {
        case 401, 403: return L10n.text("Session expired: sign in again", context: context)
        case URLError.notConnectedToInternet.rawValue, URLError.networkConnectionLost.rawValue:
            return L10n.text("Offline", context: context)
        case 500...599: return L10n.format("Nextendo server unavailable (%@)", [String(code)], context: context)
        default: return L10n.format("Error (%@ · %@)", [route, String(code)], context: context)
        }
    }
}

public struct NextendoAccountSnapshot: Sendable {
    public enum Presence: Equatable, Sendable { case offline, online, playing }

    public struct Friend: Identifiable, Equatable, Sendable {
        public let id: UInt64
        public let name: String
        public let favorite: Bool
        public let presence: Presence
        public let game: String?
        public let gameID: String?
    }

    public struct Player: Identifiable, Equatable, Sendable {
        public let id: UInt64
        public let name: String
        public let friendCode: String?
        public let game: String?
        public let gameID: String?
    }

    public let name: String
    public let username: String
    public let countryCode: String?
    public let friendCode: String?
    public let avatar: Data?
    public let avatarPID: UInt64?
    public package(set) var friends: [Friend]?
    public package(set) var requests: [Player]?
    public package(set) var sent: [Player]?
    public let recentPlayers: [Player]?
    public let failure: NextendoError?

    public func canAdd(_ player: Player) -> Bool {
        guard let friends, let requests, let sent, let code = player.friendCode, code != friendCode else { return false }
        return !friends.contains { $0.id == player.id }
            && !requests.contains { $0.id == player.id }
            && !sent.contains { $0.id == player.id }
    }
}

public enum NextendoFriendAction {
    case send(code: String), accept(pid: UInt64), decline(pid: UInt64), remove(pid: UInt64)
}

public enum NextendoFriendResult: Equatable {
    case sent, already, accepted, declined, removed
}

public enum NextendoFriendError: Error, Equatable {
    case invalidCode, unknownCode, ownCode, listFull, failed
}

public struct NextendoAccountService: Sendable {
    private let oauth: NextendoOAuth
    private static let mediaGate = GameBananaGate(limit: 4)

    public init() { self.init(oauth: NextendoOAuth()) }
    package init(oauth: NextendoOAuth) { self.oauth = oauth }

    public func check(clientID: String) async throws -> NextendoAccountSnapshot? {
        guard let access = try await oauth.refreshAccess(clientID: clientID) else { return nil }
        return try await snapshot(clientID: clientID, access: access)
    }

    /// Arcane only owns idle presence. Let the server expire it when this task stops.
    @MainActor package func maintainPresence(clientID: String, eligible: () -> Bool,
                                            sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                                            report: (Bool?) -> Void) async {
        while !Task.isCancelled && eligible() {
            var shared: Bool?
            do {
                if let access = try await oauth.refreshAccess(clientID: clientID) {
                    guard !Task.isCancelled, eligible() else { return }
                    let (_, status) = try await oauth.post("/api/presence", json: Data(#"{"status":1,"platform":"app"}"#.utf8),
                                                          clientID: clientID, access: access)
                    shared = (200..<300).contains(status)
                }
            } catch is CancellationError { return }
            catch { shared = false }
            guard !Task.isCancelled, eligible() else { return }
            report(shared)
            do { try await sleep(.seconds(45)) }
            catch { return }
        }
    }

    /// Refresh just the visible lists, retaining the rest of the account card.
    package func refreshFriends(in snapshot: NextendoAccountSnapshot, clientID: String) async throws -> NextendoAccountSnapshot? {
        guard let access = try await oauth.refreshAccess(clientID: clientID),
              try await oauth.userInfo(clientID: clientID, access: access).username == snapshot.username,
              let lists = try await friendLists(clientID: clientID, access: access).body,
              let friends = lists.objects("friends") else { return nil }
        var updated = snapshot
        updated.friends = Self.sortedFriends(friends)
        updated.requests = lists.objects("requests").map(Self.players)
        updated.sent = lists.objects("sent").map(Self.players)
        return updated
    }

    public func signIn(_ attempt: NextendoAuthorization, code: String) async throws -> NextendoAccountSnapshot? {
        let session = try await oauth.signInSession(attempt, code: code)
        return try await snapshot(clientID: attempt.clientID, access: session.access, knownUser: session.user)
    }

    /// Do not replay a social write if its outcome is uncertain. A confirmed write and its reload have separate results.
    public func updateFriend(_ action: NextendoFriendAction, username: String, clientID: String) async throws
        -> (result: NextendoFriendResult, snapshot: NextendoAccountSnapshot?) {
        let path: String, fields: [String: Any], result: NextendoFriendResult
        switch action {
        case .send(let code):
            guard let code = Self.friendCode(code) else { throw NextendoFriendError.invalidCode }
            (path, fields, result) = ("/api/friends", ["friend_code": code], .sent)
        case .accept(let pid):
            (path, fields, result) = ("/api/friends/accept", ["pid": pid], .accepted)
        case .decline(let pid):
            (path, fields, result) = ("/api/friends/decline", ["pid": pid], .declined)
        case .remove(let pid):
            (path, fields, result) = ("/api/friends/remove", ["pid": pid], .removed)
        }
        if let pid = fields["pid"] as? UInt64, pid == 0 { throw NextendoFriendError.failed }
        guard let access = try await oauth.refreshAccess(clientID: clientID) else { throw NextendoError.expired }
        try Task.checkCancellation()
        // The game shares the credential and may have changed accounts since the card was loaded.
        let user: NextendoOAuth.UserInfo
        do { user = try await oauth.userInfo(clientID: clientID, access: access) }
        catch NextendoHTTPError.unauthorized { throw NextendoError.expired }
        guard user.username == username else { throw NextendoFriendError.failed }
        let (body, status) = try await oauth.post(path, json: JSONSerialization.data(withJSONObject: fields),
                                                 clientID: clientID, access: access)
        switch (result, status) {
        case (_, 401): throw NextendoError.expired
        case (.sent, 400): throw NextendoFriendError.ownCode
        case (.sent, 404): throw NextendoFriendError.unknownCode
        case (.sent, 409): throw NextendoFriendError.listFull
        default: break
        }
        guard (200..<300).contains(status), let reply = try? NextendoDocument(data: body) else {
            throw NextendoFriendError.failed
        }
        let outcome: NextendoFriendResult
        switch result {
        case .sent, .accepted, .already:
            let already = result == .sent && reply.bool("already") == true
            guard already || reply.object("friend") != nil else { throw NextendoFriendError.failed }
            outcome = already ? .already : result
        case .declined, .removed:
            guard reply.bool("ok") == true else { throw NextendoFriendError.failed }
            outcome = result
        }
        do {
            let refreshed = try await snapshot(clientID: clientID, access: access, knownUser: user)
            return (outcome, refreshed?.username == username ? refreshed : nil)
        }
        catch is CancellationError { throw CancellationError() }
        catch { return (outcome, nil) }
    }

    /// Public, same-origin image; never pass an OAuth or game bearer for an avatar.
    public func avatar(pid: UInt64) async throws -> Data? {
        await Self.mediaGate.enter()
        defer { Task { await Self.mediaGate.leave() } }
        try Task.checkCancellation()
        let (body, status) = try await oauth.get("/api/avatar", query: [.init(name: "pid", value: String(pid))],
                                                clientID: nil, access: nil)
        return status == 200 ? ArtworkStore.downsample(body, maxPixelSize: 128, png: true) : nil
    }

    /// Resolve a missing title through the public catalog, as the Nextendo website does.
    public func gameTitle(id: String, language: AppLanguage) async throws -> String? {
        guard id.utf8.count == 16, UInt64(id, radix: 16) != nil else { return nil }
        await Self.mediaGate.enter()
        defer { Task { await Self.mediaGate.leave() } }
        try Task.checkCancellation()
        let (body, status) = try await oauth.get("/api/gameinfo", query: [
            .init(name: "title_id", value: id), .init(name: "langue", value: String(language.rawValue.prefix(2))),
        ], clientID: nil, access: nil)
        return status == 200 ? (try NextendoDocument(data: body)).text("name") : nil
    }

    private func snapshot(clientID: String, access: String, knownUser: NextendoOAuth.UserInfo? = nil) async throws
        -> NextendoAccountSnapshot? {
        do { return try await fetch(clientID: clientID, access: access, knownUser: knownUser, mayRefresh: true) }
        catch NextendoHTTPError.unauthorized {
            guard let fresh = try await oauth.refreshAccess(clientID: clientID) else { return nil }
            do { return try await fetch(clientID: clientID, access: fresh, mayRefresh: false) }
            catch NextendoHTTPError.unauthorized {
                throw NextendoError.check(.init(route: "/api/oauth/userinfo", code: 401))
            }
        }
    }

    private func fetch(clientID: String, access: String, knownUser: NextendoOAuth.UserInfo? = nil,
                       mayRefresh: Bool) async throws -> NextendoAccountSnapshot {
        let user: NextendoOAuth.UserInfo
        if let knownUser { user = knownUser }
        else { user = try await oauth.userInfo(clientID: clientID, access: access) }
        async let me = read("/api/me", clientID: clientID, access: access)
        async let profileSection = read("/api/profile", clientID: clientID, access: access)
        async let friendsSection = friendLists(clientID: clientID, access: access)
        async let online = onlineStatus(clientID: clientID, access: access)
        async let recent = read("/api/recent-players", clientID: clientID, access: access)
        let sections = try await [me, profileSection, friendsSection, online]
        let recentSection = try await recent
        if mayRefresh && (sections.contains(where: { $0.unauthorized }) || recentSection.unauthorized) {
            throw NextendoHTTPError.unauthorized
        }
        let account = sections[0].body?.object("account")
        if let pid = account?.pid, let userPID = user.pid, pid != userPID { throw NextendoError.service }
        let profile = sections[1].body?.object("profile")
        let avatar = profile?.text("image", limit: 1_048_576)
            .flatMap { Data(base64Encoded: $0) }
            .flatMap { ArtworkStore.downsample($0, maxPixelSize: 128, png: true) }
        // `mii` is a Switch StoreData, not a bitmap. Use Nextendo's image endpoint for that portrait.
        let hasAvatar = ["mii", "avatar", "image"].contains { profile?.text($0, limit: 1_048_576) != nil }
        let friends = sections[2].body?.objects("friends").map(Self.sortedFriends)
        let incomplete = sections.enumerated().filter { $0.element.body == nil || ($0.offset == 2 && friends == nil) }
        let diagnostic = incomplete.compactMap(\.element.diagnostic).first
            ?? recentSection.diagnostic.flatMap { $0.code == 200 ? nil : $0 }
        let failure: NextendoError? = if sections[3].forbidden, let diagnostic = sections[3].diagnostic {
            .check(diagnostic)
        } else if let onlineStatus = sections[3].body, onlineStatus.bool("allow") == false {
            switch onlineStatus.text("reason", limit: 32) {
            case "discord_unlinked": .discordUnlinked
            case "unverified": .emailUnverified
            default: .onlinePlayUnavailable
            }
        } else if let diagnostic {
            .check(diagnostic)
        } else if !incomplete.isEmpty {
            .service
        } else {
            nil
        }
        return NextendoAccountSnapshot(name: user.displayName ?? profile?.text("name") ?? user.username, username: user.username,
                                       countryCode: Self.country(account?.text("country")),
                                       friendCode: Self.friendCode(user.friendCode) ?? Self.friendCode(account?.text("friend_code")),
                                       avatar: avatar, avatarPID: hasAvatar ? user.pid ?? account?.pid : nil,
                                       friends: friends,
                                       requests: sections[2].body?.objects("requests").map(Self.players),
                                       sent: sections[2].body?.objects("sent").map(Self.players),
                                       recentPlayers: recentSection.body?.objects("players").map(Self.players),
                                       failure: failure)
    }

    private struct Section {
        var body: NextendoDocument? = nil
        var diagnostic: NextendoCheckDiagnostic? = nil
        var unauthorized: Bool { diagnostic?.code == 401 }
        var forbidden: Bool { diagnostic?.code == 403 }
    }

    private func friendLists(clientID: String, access: String) async throws -> Section {
        try await read("/api/friends", query: [.init(name: "images", value: "0")], clientID: clientID, access: access)
    }

    private func read(_ path: String, query: [URLQueryItem] = [], clientID: String, access: String) async throws -> Section {
        do {
            let (body, status) = try await oauth.get(path, query: query, clientID: clientID, access: access)
            return Section(body: status == 200 ? try? NextendoDocument(data: body) : nil,
                           diagnostic: .init(route: path, code: status))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NextendoError {
            return Section(diagnostic: error.checkDiagnostic)
        } catch {
            return Section()
        }
    }

    private func onlineStatus(clientID: String, access: String) async throws -> Section {
        let game = try await read("/api/nex-token", clientID: clientID, access: access)
        guard let gameToken = game.body?.text("nex_token", limit: 8192), NextendoOAuth.validBearer(gameToken)
        else { return Section(diagnostic: game.diagnostic) }
        // The status route takes a game bearer, not the OAuth access token.
        let status = try await read("/api/online-status", clientID: clientID, access: gameToken)
        guard status.body?.bool("allow") != nil else {
            return Section(diagnostic: status.diagnostic)
        }
        return status
    }

    private static func country(_ value: String?) -> String? {
        guard let value = value?.uppercased(), value.utf8.count == 2, value.utf8.allSatisfy({ (65...90).contains($0) })
        else { return nil }
        return value
    }

    private static func friendCode(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 64 else { return nil }
        let stripped = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: "SW-", with: "", options: .anchored)
        let digits = stripped.filter { $0 != "-" && $0 != " " }
        guard digits.utf8.count == 12, digits.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return "SW-\(digits.prefix(4))-\(digits.dropFirst(4).prefix(4))-\(digits.suffix(4))"
    }

    private static func players(_ rows: [NextendoDocument]) -> [NextendoAccountSnapshot.Player] {
        var seen = Set<UInt64>()
        return rows.compactMap { row in
            guard let pid = row.pid, let name = row.text("name") ?? row.text("username"),
                  seen.insert(pid).inserted else { return nil }
            return .init(id: pid, name: name, friendCode: friendCode(row.text("friend_code")),
                         game: row.text("jeu"), gameID: row.text("title_id"))
        }
    }

    private static func sortedFriends(_ rows: [NextendoDocument]) -> [NextendoAccountSnapshot.Friend] {
        var seen = Set<UInt64>()
        return rows.compactMap { row -> NextendoAccountSnapshot.Friend? in
            guard let pid = row.pid, let name = row.text("name") ?? row.text("username"), seen.insert(pid).inserted else { return nil }
            let activity = row.object("presence")
            let status = activity?.number("status") ?? 0
            let id = activity?.text("app_id")
            let playing = status == 2 || (status == 1 && id != nil)
            let presence: NextendoAccountSnapshot.Presence = playing ? .playing : status == 1 ? .online : .offline
            return .init(id: pid, name: name, favorite: row.bool("favorite") ?? false, presence: presence,
                         game: playing ? activity?.text("jeu") : nil, gameID: playing ? id : nil)
        }.sorted {
            let a = $0.presence != .offline, b = $1.presence != .offline
            if a != b { return a }
            if $0.favorite != $1.favorite { return $0.favorite }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}

/// Account fields are additive; a missing or differently typed optional value does not erase its siblings.
struct NextendoDocument {
    private let fields: [String: Any]
    private init(_ fields: [String: Any]) { self.fields = fields }

    init(data: Data) throws {
        guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NextendoError.service }
        self.init(fields)
    }

    func object(_ key: String) -> Self? { (fields[key] as? [String: Any]).map(Self.init) }
    func objects(_ key: String) -> [Self]? {
        (fields[key] as? [Any])?.compactMap { ($0 as? [String: Any]).map(Self.init) }
    }

    func text(_ key: String, limit: Int = 256) -> String? {
        guard let raw = fields[key] as? String, raw.utf8.count <= limit else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.rangeOfCharacter(from: .controlCharacters) != nil ? nil : text
    }

    func number(_ key: String) -> UInt64? {
        guard let n = fields[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return UInt64(n.stringValue)
    }

    func bool(_ key: String) -> Bool? {
        guard let n = fields[key] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    var pid: UInt64? {
        if let value = number("pid"), value > 0 { return value }
        return text("pid").flatMap { UInt64($0) }.flatMap { $0 > 0 ? $0 : nil }
    }
}
