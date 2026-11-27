import Combine
import Foundation
import NXLibraryCore
import ArcanePorting

/// Owns only the state of the Online services connection; tokens stay in the engine's store.
@MainActor final class NextendoSettings: ObservableObject {
    static let shared = NextendoSettings()
    enum Status: Equatable { case signedOut, signedIn, expired, unavailable }

    @Published private(set) var status: Status = .signedOut
    @Published private(set) var account: NextendoAccountSnapshot?
    @Published private(set) var accountName: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isWaitingForBrowser = false
    @Published private(set) var failure: NextendoError?
    private(set) var revision = UUID()
    private(set) var overlayUsername: String?
    private(set) var overlayFriends: [NextendoAccountSnapshot.Friend]?
    private(set) var knownGameTitles: [String: String] = [:]
    @Published var isEditingClient = false
    @Published var friendToRemove: NextendoAccountSnapshot.Friend?
    @Published private(set) var friendMessage: (key: String, isError: Bool)?
    @Published private(set) var friendsNeedRefresh = false
    @Published private(set) var submittedFriendCode: String?
    @Published private(set) var friendsUpdatedAt: Date?
    @Published private(set) var isRefreshingFriends = false
    @Published private(set) var presenceShared: Bool?
    @Published private(set) var presenceRevision = UUID()
    private var operation: Task<Void, Never>?
    private var ticket = UUID()
    @Published private(set) var isSigningOut = false
    let store: NextendoTokenStore
    let accountService: NextendoAccountService

    init(store: NextendoTokenStore = .init(), service: NextendoAccountService? = nil,
         onResult: @escaping @Sendable (NextendoCheckDiagnostic) -> Void = { _ in }) {
        self.store = store
        accountService = service ?? NextendoAccountService(oauth: NextendoOAuth(store: store, onResult: onResult))
    }

    func check(clientID: String?) {
        run(checking: true) { model in
            if let clientID {
                try model.apply(await model.accountService.check(clientID: clientID))
            } else {
                let store = model.store
                let hasToken = try await Task.detached { try store.hasToken() }.value
                try Task.checkCancellation()
                if hasToken { throw NextendoError.clientID }
                try model.apply(nil)
            }
        }
    }

    func refreshFriends(clientID: String?) {
        guard let clientID, let account, status == .signedIn, !isBusy else { return }
        isRefreshingFriends = true
        run(friendAction: true) { model in
            guard let updated = try? await model.accountService.refreshFriends(in: account, clientID: clientID),
                  !Task.isCancelled else { return }
            model.account = updated
            model.overlayFriends = updated.friends
            model.friendsNeedRefresh = updated.requests == nil || updated.sent == nil
            model.friendsUpdatedAt = .now
        }
    }

    func publishPresence(clientID: String, eligible: () -> Bool) async {
        await accountService.maintainPresence(clientID: clientID, eligible: { !self.isSigningOut && eligible() }) {
            self.presenceShared = $0
        }
    }

    func clearPresence() {
        presenceShared = nil
    }

    func updateFriend(_ action: NextendoFriendAction, clientID: String?) {
        guard status == .signedIn, !friendsNeedRefresh, let username = account?.username, let clientID else { return }
        run(friendAction: true) { model in
            model.friendMessage = nil
            model.submittedFriendCode = nil
            do {
                let update = try await model.accountService.updateFriend(action, username: username, clientID: clientID)
                try Task.checkCancellation()
                if let snapshot = update.snapshot { try model.apply(snapshot) }
                model.friendsNeedRefresh = update.snapshot?.friends == nil
                    || update.snapshot?.requests == nil || update.snapshot?.sent == nil
                let key: String = switch update.result {
                case .sent: "Friend request sent."
                case .already: "You’re already friends or a request is pending."
                case .accepted: "Friend request accepted."
                case .declined: "Friend request declined."
                case .removed: "Friend removed."
                }
                model.friendMessage = (key, false)
                if case .send(let code) = action { model.submittedFriendCode = code }
            } catch let error as NextendoFriendError {
                try Task.checkCancellation()
                let key: String = switch error {
                case .invalidCode: "Enter a 12-digit friend code."
                case .unknownCode: "No player has that friend code."
                case .ownCode: "You can’t add your own friend code."
                case .listFull: "One of the friend lists is full."
                case .failed: "Could not confirm the friend action. Check status before trying again."
                }
                if error == .failed { model.friendsNeedRefresh = true }
                model.friendMessage = (key, true)
            } catch NextendoError.expired {
                throw NextendoError.expired
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                model.friendsNeedRefresh = true
                model.friendMessage = ("Could not confirm the friend action. Check status before trying again.", true)
            }
        }
    }

    func signIn(clientID: String?) {
        guard let clientID else { isEditingClient = true; return }
        run { model in
            let (authorization, code) = try await model.authorize(clientID: clientID)
            try Task.checkCancellation()
            model.isWaitingForBrowser = false
            try model.apply(await model.accountService.signIn(authorization, code: code))
            model.presenceRevision = UUID()
        }
    }

    func signOut() {
        run(signingOut: true) { model in
            try await NextendoOAuth(store: model.store).signOut()
            try model.apply(nil)
        }
    }

    func cancelBrowser() {
        if isWaitingForBrowser { operation?.cancel() }
    }

    func endVisit() {
        if !isSigningOut {
            ticket = UUID()
            operation?.cancel()
            operation = nil
            isBusy = false
            isWaitingForBrowser = false
        }
        account = nil
        accountName = nil
        friendsUpdatedAt = nil
        isRefreshingFriends = false
        failure = nil
        friendToRemove = nil
        friendMessage = nil
        friendsNeedRefresh = false
        submittedFriendCode = nil
    }

    func clientChanged() {
        endVisit()
        clearOverlayAccount()
        if status != .signedOut { status = .unavailable }
    }

    func rememberGameTitle(_ title: String, id: String) {
        guard let overlayFriends, overlayFriends.contains(where: { $0.gameID == id }) else { return }
        knownGameTitles[id.uppercased()] = title
    }

    private func clearOverlayAccount() {
        overlayUsername = nil
        overlayFriends = nil
        knownGameTitles = [:]
    }

    private func apply(_ snapshot: NextendoAccountSnapshot?) throws {
        try Task.checkCancellation()
        if snapshot?.username != overlayUsername || snapshot == nil { clearOverlayAccount() }
        if let snapshot {
            overlayUsername = snapshot.username
            if let friends = snapshot.friends { overlayFriends = friends }
        }
        revision = UUID()
        friendsNeedRefresh = false
        account = snapshot
        friendsUpdatedAt = snapshot?.friends == nil ? nil : .now
        accountName = snapshot?.name
        status = snapshot == nil ? .signedOut : .signedIn
        failure = snapshot?.failure
    }

    private func authorize(clientID: String) async throws -> (NextendoAuthorization, String) {
        isWaitingForBrowser = true
        do { return try await NextendoBrowserSignIn.authorize(clientID: clientID) }
        catch is CancellationError { throw CancellationError() }
        catch let error as NextendoError { throw error }
        catch { throw NextendoError.browser }
    }

    private func run(checking: Bool = false, signingOut: Bool = false, friendAction: Bool = false,
                     _ work: @escaping @MainActor (NextendoSettings) async throws -> Void) {
        guard !isBusy else { return }
        let ticket = UUID()
        self.ticket = ticket
        isSigningOut = signingOut
        if !friendAction { failure = nil; friendMessage = nil }
        isBusy = true
        operation = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.ticket == ticket {
                    self.isBusy = false
                    self.isWaitingForBrowser = false
                    self.isSigningOut = false
                    self.isRefreshingFriends = false
                    self.operation = nil
                }
            }
            do { try await work(self) }
            catch is CancellationError {}
            catch {
                guard self.ticket == ticket, !Task.isCancelled else { return }
                let problem = error as? NextendoError ?? .service
                if problem == .expired || problem.checkDiagnostic?.code == 401 || problem.checkDiagnostic?.code == 403 {
                    self.status = .expired
                    self.account = nil
                    self.clearOverlayAccount()
                } else if (checking || self.status != .signedOut),
                          problem == .service || problem.checkDiagnostic != nil || problem == .clientID || problem == .storage {
                    self.status = .unavailable
                    self.account = nil
                }
                self.failure = problem
            }
        }
    }
}
