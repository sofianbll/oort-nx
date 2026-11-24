import AppKit
import SwiftUI
import NXLibraryCore
import ArcanePorting

/// General, optional connections; moving them here leaves stored credentials and provider behaviour intact.
struct SettingsAPISection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    let showsMultiplayer: Bool
    let supportsNextendo: Bool
    var accountOnly = false
    var accountOffline = false
    var profile: LocalProfile? = nil
    var onProfilePreference: (WritableKeyPath<LocalProfile, Bool?>, Bool) -> Void = { _, _ in }
    @Binding var advanced: Bool
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneFocusedRowID) private var focusedRow
    @Environment(\.seleneFocusedButton) private var focusedButton
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.passiveSettingsArrival) private var passiveArrival
    @ObservedObject private var igdb = IGDBSettings.shared
    @ObservedObject var nextendo = NextendoSettings.shared
    @State private var friendsExpanded = false
    @State private var recentExpanded = false
    @State private var friendCode = ""
    @FocusState private var friendCodeFocused: Bool
    @State private var copiedCode: String?
    @State var remotePlayAdapters = RemotePlayAdapters()
    @State private var vpnAppURL: URL?
    @State private var nextendoRequested = false

    private var canContactNextendo: Bool { !passiveArrival || nextendoRequested }
    private var clientID: String? { settings.settings.nextendoClientID ?? NextendoLaunch.buildClientID }
    private let accountRowID = "Nextendo"
    private let friendsRowID = "nextendoFriends"
    private let refreshFriendsRowID = "nextendoRefreshFriends"
    private let addRowID = "nextendoAddFriend"
    private let recentRowID = "nextendoRecentPlayers"
    private let linksRowID = "nextendoLinks"
    private let advancedRowID = "Nextendo client ID"
    private var canActivateNextendo: Bool { !nextendo.isBusy || nextendo.isWaitingForBrowser }
    private var hasFriendCode: Bool { nextendo.account?.friendCode != nil }
    private var showFriends: Bool { nextendo.status == .signedIn && nextendo.account != nil }
    private var friendData: NextendoAccountSnapshot? { nextendo.friendsNeedRefresh ? nil : nextendo.account }
    private var friends: [NextendoAccountSnapshot.Friend]? { friendData?.friends }
    private var canUpdateFriends: Bool { !nextendo.isBusy && !nextendo.friendsNeedRefresh && clientID != nil }
    private var friendsRefreshClient: String? {
        supportsNextendo && showFriends && (accountOnly || friendsExpanded) && !accountOffline ? clientID : nil
    }
    private var canRefreshFriends: Bool { friendsRefreshClient != nil && !nextendo.isBusy }

    private var serviceRows: some View {
        Group {
            Text(L10n.text("Connect optional services to enrich your library with ratings and artwork. Public sources remain available without API keys."))
                .seleneFont(.caption)
                .foregroundColor(SeleneTheme.ink60)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, canvas.u(SeleneTokens.Space.compact))

            SettingsSubheading(L10n.text("Ratings"))
            SeleneRow("IGDB", subtitle: igdb.message ?? (igdb.isConfigured
                      ? "IGDB connected · Wikidata is the fallback"
                      : "Optional critic scores with your own credentials")) {
                HStack(spacing: canvas.u(18)) {
                    Button(L10n.text(igdb.isConfigured ? "Edit credentials" : "Connect")) { igdb.isEditing = true }
                        .foregroundColor(SeleneTheme.glyph)
                    if igdb.isConfigured {
                        Button(L10n.text("Remove")) { Task { await igdb.remove() } }
                            .foregroundColor(SeleneTheme.ink60).disabled(igdb.isRemoving)
                    }
                }
                .buttonStyle(.plain).seleneFont(.compactCaption, .semibold)
            }

            SettingsSubheading(L10n.text("Artwork"))
            SeleneButtonRow("SteamGridDB",
                            subtitle: viewModel.hasSteamGridDBKey
                                ? "Key saved · covers, backgrounds, logos and icons in Change artwork"
                                : "Add your free API key to find art in Change artwork",
                            buttonTitle: viewModel.hasSteamGridDBKey ? "Remove key" : "Add key") {
                steamGridDBAction()
            }

        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            if accountOnly {
                if let profile {
                    Text(L10n.format("Arcane works without an account. These settings only apply to %@.", [profile.name]))
                        .seleneFont(.caption).foregroundStyle(SeleneTheme.ink60)
                    SettingsSubheading("Presence")
                    SeleneToggleRow("Appear online", isOn: preference(\.appearsOnline))
                    SeleneToggleRow("Show current game", subtitle: "Applies the next time you start a game.",
                                    isOn: preference(\.showsCurrentGame))
                    SettingsSubheading("Account")
                }
                nextendoRows
            }
            else if showsMultiplayer { multiplayerRows } else { serviceRows }
        }
        .environment(\.passiveSettingsArrival, !canContactNextendo)
        .onAppear {
            refreshRemotePlay()
            publishActions()
            if canContactNextendo && supportsNextendo && accountOnly { nextendo.check(clientID: clientID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshRemotePlay()
            publishActions()
        }
        .onChange(of: settings.settings.multiplayerVPN) { _, _ in
            refreshRemotePlay()
            if showsMultiplayer { publishActions() }
        }
        .onChange(of: advanced) { if showsMultiplayer { publishActions() } }
        .onChange(of: igdb.revision) { publishActions() }
        .onChange(of: supportsNextendo) { _, supported in
            if canContactNextendo, accountOnly {
                if supported { nextendo.check(clientID: clientID) }
                else { endNextendoVisit() }
            }
            publishActions()
        }
        .onChange(of: clientID) {
            if canContactNextendo, supportsNextendo {
                nextendo.clientChanged()
                publishActions()
            }
        }
        .onChange(of: nextendo.status) { _, status in
            if status != .signedIn { resetFriendsPanel() }
            if supportsNextendo { publishActions() }
        }
        .onChange(of: showFriends) { if supportsNextendo { publishActions() } }
        .onChange(of: hasFriendCode) { if supportsNextendo { publishActions() } }
        .onChange(of: friendsExpanded) { if supportsNextendo { publishActions() } }
        .onChange(of: recentExpanded) { if supportsNextendo { publishActions() } }
        .onChange(of: nextendo.revision) { if supportsNextendo { publishActions() } }
        .onChange(of: nextendo.friendsNeedRefresh) { if supportsNextendo { publishActions() } }
        .onChange(of: nextendo.submittedFriendCode) { _, submitted in
            if submitted == friendCode { friendCode = "" }
        }
        .onChange(of: focusedRow) { _, row in
            if row != addRowID, friendCodeFocused { friendCodeFocused = false }
        }
        .onChange(of: focusedButton) { _, button in
            if focusedRow == addRowID, button == 1 { friendCodeFocused = false }
        }
        .onChange(of: nextendo.isBusy) { if supportsNextendo { publishActions() } }
        .onChange(of: nextendo.isWaitingForBrowser) { if supportsNextendo { publishActions() } }
        .onChange(of: profile?.appearsOnline) { if accountOnly { publishActions() } }
        .onChange(of: profile?.showsCurrentGame) { if accountOnly { publishActions() } }
        .onDisappear { if canContactNextendo && accountOnly { endNextendoVisit() } }
        .task(id: canContactNextendo ? friendsRefreshClient : nil) {
            guard canContactNextendo, let clientID = friendsRefreshClient else { return }
            if let date = nextendo.friendsUpdatedAt, Date.now.timeIntervalSince(date) >= 60 {
                nextendo.refreshFriends(clientID: clientID)
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard !Task.isCancelled else { return }
                nextendo.refreshFriends(clientID: clientID)
            }
        }
        .task(id: copiedCode) {
            guard let code = copiedCode else { return }
            do { try await Task.sleep(for: .seconds(1.4)) } catch { return }
            if !Task.isCancelled, copiedCode == code { copiedCode = nil }
        }
    }

    private var vpn: MultiplayerVPN { settings.settings.multiplayerVPN }
    private var connection: RemotePlayAdapters.Connection {
        remotePlayAdapters.connection(for: vpn, manual: settings.settings.multiplayerAdapter)
    }

    @ViewBuilder var multiplayerRows: some View {
        SeleneCycleRow("Private network (VPN)", value: vpn.label, cycle: stepVPN)
        if vpn != .none {
            SeleneRow(vpn.label, id: "multiplayerVPNStatus", subtitle: vpnSubtitle) {
                SeleneStatusDot(text: vpnStatus, color: vpnColor)
                Button(text(vpnActionTitle), action: openVPN)
                    .buttonStyle(.plain)
                    .seleneFont(.compactCaption, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
            }
        }
        SeleneCycleRow("Default for games", value: settings.settings.multiplayerDefault.label, cycle: stepDefault)
        SeleneButtonRow("Advanced", id: "multiplayerAdvanced", buttonTitle: advanced ? "Hide" : "Show") { advanced.toggle() }
            .accessibilityValue(text(advanced ? "Expanded" : "Collapsed"))
        if advanced {
            SeleneCycleRow("Local network mode", value: settings.settings.multiplayerLocalMode.label, cycle: stepLocalMode)
            SeleneCycleRow("Network adapter", value: settings.settings.multiplayerAdapter ?? text("Automatic"),
                           verbatimValue: true, cycle: stepAdapter)
            if supportsNextendo { nextendoClientRow }
        }
    }

    private var vpnSubtitle: String? {
        if case .ambiguous = connection { return "Choose the network adapter in Advanced." }
        return nil
    }

    private var vpnStatus: String {
        switch connection {
        case .connected(_, let ip): return L10n.format("Connected · %@", [ip], context: localization)
        case .ignored: return text("Ignored · another VPN is active")
        case .ambiguous: return text("Adapter not identified")
        case .disconnected: return text("Not connected")
        }
    }

    private var vpnColor: Color {
        if case .connected = connection { return SeleneTheme.statusOK }
        return SeleneTheme.untested
    }

    private var vpnActionTitle: String { vpnAppURL == nil ? "Download" : "Open" }

    private func refreshRemotePlay() {
        guard showsMultiplayer else { return }
        remotePlayAdapters = .current()
        let app = URL(fileURLWithPath: "/Applications/\(vpn.label).app")
        let identifiers: [String]
        switch vpn {
        case .none: identifiers = []
        case .zeroTier: identifiers = ["com.zerotier.ZeroTier-UI"]
        case .tailscale: identifiers = ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"]
        case .netBird: identifiers = ["io.netbird.client"]
        }
        vpnAppURL = identifiers.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
            ?? (FileManager.default.fileExists(atPath: app.path) ? app : nil)
    }

    private func openVPN() {
        if let vpnAppURL { NSWorkspace.shared.open(vpnAppURL); return }
        let url: String
        switch vpn {
        case .none: return
        case .zeroTier: url = "https://www.zerotier.com/download/"
        case .tailscale: url = "https://tailscale.com/download/mac"
        case .netBird: url = "https://netbird.io/download"
        }
        openURL(URL(string: url)!)
    }

    private func stepVPN(_ step: Int) {
        let before = vpn
        let next = before.stepped(step)
        guard next != before else { return }
        viewModel.confirmSetting(text("Private network (VPN)"),
            message: L10n.format("Local play will use the VPN setting “%@” and reset the adapter to Automatic without changing macOS network settings.",
                                 [text(next.label)], context: localization), action: "Save") {
            guard vpn == before else { return }
            var value = settings.settings
            value.multiplayerVPN = next
            value.multiplayerAdapter = nil
            settings.settings = value
        }
    }

    private func stepDefault(_ step: Int) {
        let next = settings.settings.multiplayerDefault.stepped(step)
        confirmNetworkValue("Default for games", \.multiplayerDefault, next, label: text(next.label),
            message: "The default will change to “%@” for future launches, but each game’s own choice will stay in place.")
    }

    private func stepLocalMode(_ step: Int) {
        let next = settings.settings.multiplayerLocalMode.stepped(step)
        confirmNetworkValue("Local network mode", \.multiplayerLocalMode, next, label: text(next.label),
            message: "Future local games will prefer “%@” without changing macOS network settings.")
    }

    private func stepAdapter(_ step: Int) {
        let values: [String?] = [nil] + remotePlayAdapters.interfaceNames.map(Optional.some)
        let next = values.stepped(from: settings.settings.multiplayerAdapter, step) ?? nil
        confirmNetworkValue("Network adapter", \.multiplayerAdapter, next, label: next ?? text("Automatic"),
            message: "Future local games will use the adapter setting “%@” without changing macOS network settings.")
    }

    private func confirmNetworkValue<Value: Equatable>(_ title: String, _ key: WritableKeyPath<AppSettings, Value>,
                                                       _ next: Value, label: String, message: String) {
        let before = settings.settings[keyPath: key]
        guard next != before else { return }
        viewModel.confirmSetting(text(title), message: L10n.format(message, [label], context: localization), action: "Save") {
            guard settings.settings[keyPath: key] == before else { return }
            settings.settings[keyPath: key] = next
        }
    }

    @ViewBuilder private var nextendoRows: some View {
        nextendoAccountRow
        if showFriends {
            let title = friends.map {
                L10n.format("Friends · %lld online out of %lld", [$0.filter { $0.presence != .offline }.count, $0.count],
                            context: localization)
            } ?? text("Friends")
            SeleneButtonRow(title, id: friendsRowID, verbatimTitle: true,
                            buttonTitle: friendsExpanded ? "Hide" : "Show", action: toggleFriends)
                .accessibilityValue(text(friendsExpanded ? "Expanded" : "Collapsed"))
            if accountOnly || friendsExpanded { refreshFriendsRow }
            if friendsExpanded {
                friendsPanel
            }
        }
    }

    private var refreshFriendsRow: some View {
        SeleneRow("Refresh friends", id: refreshFriendsRowID) {
            if let date = nextendo.friendsUpdatedAt {
                TimelineView(.periodic(from: date, by: 1)) { _ in
                    let age = date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)
                        .locale(localization.formatLocale))
                    NextendoValue(text: L10n.format("Updated %@", [age], context: localization))
                }
            }
            action(.init("Refresh", action: refreshFriends), row: refreshFriendsRowID, index: 0)
                .disabled(!canRefreshFriends)
        }
    }

    private func refreshFriends() {
        guard canRefreshFriends else { return }
        nextendo.refreshFriends(clientID: friendsRefreshClient)
    }

    private func checkNextendo() {
        nextendoRequested = true
        nextendo.check(clientID: clientID)
    }

    private var nextendoClientRow: some View {
        SeleneRow("Nextendo client ID", id: advancedRowID, subtitle: "Public client ID") {
            Text(settings.settings.nextendoClientID ?? text(clientID == nil ? "Not set" : "Built-in value"))
                .seleneFont(.compactCaption)
                .foregroundColor(SeleneTheme.ink60)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: canvas.u(200))
            Button(text("Edit")) { nextendo.isEditingClient = true }
                .buttonStyle(.plain)
                .seleneFont(.compactCaption, .semibold)
                .foregroundColor(SeleneTheme.glyph)
                .disabled(nextendo.isBusy)
        }
    }

    private var nextendoAccountRow: some View {
        let account = nextendo.account
        let country = account?.countryCode.map {
            Locale(identifier: localization.language.rawValue).localizedString(forRegionCode: $0) ?? $0
        }
        let details = [account?.friendCode, country].compactMap { $0 }.joined(separator: " · ")
        let signedOut = nextendo.status == .signedOut
        let buttons = accountButtons
        return SeleneOptionRow(icon: nil, title: nextendo.accountName ?? text("Nextendo"),
                               about: signedOut ? text("Free community online play for compatible nxnative games. Requires a Nextendo account.")
                                   : details.isEmpty ? nil : details,
                               focused: focusedRow == accountRowID,
                               leading: signedOut ? nil : AnyView(NextendoAvatar(service: nextendo.accountService, pid: account?.avatarPID, image: account?.avatar,
                                                                              revision: nextendo.revision)),
                               titleAccessory: signedOut ? nil : AnyView(accountStatus)) {
            VStack(alignment: .trailing, spacing: canvas.u(4)) {
                if let failure = nextendo.failure {
                    Text(failure.localizedDescription)
                        .seleneFont(.compactCaption)
                        .foregroundColor(SeleneTheme.danger)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: canvas.u(340), alignment: .trailing)
                    if let diagnostic = failure.checkDiagnostic {
                        Text(diagnostic.message(context: localization))
                            .seleneFont(.compactCaption)
                            .foregroundStyle(SeleneTheme.ink60)
                    } else if failure == .discordUnlinked || failure == .emailUnverified {
                        Text(text(failure == .discordUnlinked
                                  ? "Nextendo account not yet verified: link Discord on nextendo.network. Verification may take a few minutes."
                                  : "Nextendo account not yet verified: confirm your email address."))
                            .seleneFont(.compactCaption)
                            .foregroundStyle(SeleneTheme.ink60)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: canvas.u(340), alignment: .trailing)
                    }
                } else if nextendo.isWaitingForBrowser || nextendo.isBusy && !nextendo.isRefreshingFriends || signedOut {
                    NextendoValue(text: text(nextendo.isWaitingForBrowser ? "Waiting for your browser…"
                                             : nextendo.isBusy ? "Checking…"
                                             : canContactNextendo ? "Signed out" : "Connection not tested"))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: canvas.u(8)) { accountActions(buttons) }.fixedSize()
                    VStack(alignment: .trailing, spacing: canvas.u(2)) { accountActions(buttons) }
                }
                .disabled(!canActivateNextendo)
            }
        }
        .id("selene-row-\(accountRowID)")
    }

    private var accountStatus: some View {
        switch nextendo.status {
        case .signedIn: return SeleneStatusDot(text: text("Nextendo connected"), color: SeleneTheme.statusOK).fixedSize()
        case .expired: return SeleneStatusDot(text: text("Session expired"), color: SeleneTheme.danger).fixedSize()
        case .signedOut, .unavailable:
            let label = accountOnly && !accountOffline ? "Presence unknown" : "Offline"
            return SeleneStatusDot(text: text(label), color: SeleneTheme.ink60).fixedSize()
        }
    }

    private var accountButtons: [NextendoButton] {
        if nextendo.isWaitingForBrowser { return [.init("Cancel", action: nextendo.cancelBrowser)] }
        let signIn = NextendoButton("Sign in…") {
            nextendoRequested = true
            nextendo.signIn(clientID: clientID)
        }
        if nextendo.status == .signedOut {
            return canContactNextendo ? [signIn] : [.init("Check status", action: checkNextendo), signIn]
        }
        var buttons: [NextendoButton] = []
        if let code = nextendo.account?.friendCode {
            buttons.append(.init(copiedCode == code ? "Copied" : "Copy code",
                                 symbol: copiedCode == code ? "checkmark" : "doc.on.doc", action: copyCode))
        }
        if nextendo.status == .expired { buttons.append(signIn) }
        buttons.append(.init("Check status", action: checkNextendo))
        if nextendo.failure == .discordUnlinked || nextendo.failure == .emailUnverified {
            buttons.append(.init("Open Nextendo account") {
                NSWorkspace.shared.open(URL(string: "https://nextendo.network/compte.html")!)
            })
        }
        buttons.append(.init("Sign out", action: nextendo.signOut))
        return buttons
    }

    private func accountActions(_ buttons: [NextendoButton]) -> some View {
        ForEach(buttons.indices, id: \.self) { index in
            action(buttons[index], row: accountRowID, index: index, outline: buttons.count > 1)
        }
    }

    private var friendsPanel: some View {
        SelenePanel {
            addFriendRow
            if let message = nextendo.friendMessage {
                friendNotice(message.key, isError: message.isError)
            }
            if nextendo.friendsNeedRefresh, nextendo.friendMessage?.isError == false {
                friendNotice("Could not refresh the lists. Use Check status.", isError: true)
            }
            if let requests = friendData?.requests, !requests.isEmpty {
                SettingsSubheading(text("Received requests"))
                LazyVStack(spacing: canvas.u(8)) {
                    ForEach(requests) { player in
                        playerLine(player.name, row: requestRowID(player.id), buttons: requestButtons(player.id))
                    }
                }
            }
            if let sent = friendData?.sent, !sent.isEmpty {
                SettingsSubheading(text("Sent requests"))
                LazyVStack(spacing: canvas.u(8)) {
                    ForEach(sent) { player in
                        playerLine(player.name, row: "nextendoSent-\(player.id)", detail: text("Pending"))
                    }
                }
            }
            if friendData != nil, friendData?.requests == nil || friendData?.sent == nil {
                friendNotice("Friend requests unavailable", isError: true)
            }
            SeleneButtonRow("Recently played with", id: recentRowID, buttonTitle: recentExpanded ? "Hide" : "Show",
                            action: toggleRecent)
                .accessibilityValue(text(recentExpanded ? "Expanded" : "Collapsed"))
            if recentExpanded { recentPlayers }
            if let friends, !friends.isEmpty {
                LazyVStack(spacing: canvas.u(8)) {
                    ForEach(friends) { friend in
                        let row = friendRowID(friend.id)
                        NextendoFriendLine(friend: friend, revision: nextendo.revision, service: nextendo.accountService,
                                           rememberTitle: nextendo.rememberGameTitle) {
                            action(removeButton(friend), row: row, index: 0)
                                .disabled(!canUpdateFriends)
                        }
                        .id("selene-row-\(row)")
                    }
                }
            } else {
                NextendoValue(text: text(friends == nil ? "Friends unavailable" : "No friends yet."))
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
            }
            HStack(spacing: canvas.u(8)) {
                Spacer(minLength: 0)
                action(openProfile, row: linksRowID, index: 0)
            }
            .id("selene-row-\(linksRowID)")
        }
    }

    private var addFriendRow: some View {
        SeleneRow("Add a friend", id: addRowID) {
            TextField(text("Friend code"), text: $friendCode, prompt: Text(verbatim: "SW-0000-0000-0000"))
                .textFieldStyle(.plain)
                .focused($friendCodeFocused)
                .onSubmit(sendFriendCode)
                .accessibilityLabel(text("Friend code"))
                .seleneFont(.compactCaption)
                .foregroundColor(SeleneTheme.ink)
                .padding(canvas.u(SeleneTokens.Space.compact))
                .frame(maxWidth: canvas.u(195))
                .background(RoundedRectangle(cornerRadius: canvas.u(7)).fill(SeleneTheme.glassLight))
                .seleneRowFocus(friendCodeFocused || (focusedRow == addRowID && focusedButton == 0), radius: canvas.u(7))
            action(.init("Add", action: sendFriendCode), row: addRowID, index: 1)
        }
        .disabled(!canUpdateFriends)
    }

    private var recentPlayers: some View {
        Group {
            if let players = friendData?.recentPlayers, !players.isEmpty {
                LazyVStack(spacing: canvas.u(8)) {
                    ForEach(players) { player in
                        playerLine(player.name, row: recentPlayerRowID(player.id),
                                   buttons: recentButton(player).map { [$0] } ?? []) {
                            NextendoGameTitle(service: nextendo.accountService, name: player.game, id: player.gameID)
                        }
                    }
                }
            } else {
                NextendoValue(text: text(friendData?.recentPlayers == nil ? "Recent players unavailable" : "No recent players."))
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
            }
        }
    }

    private func playerLine(_ name: String, row: String, detail: String? = nil, buttons: [NextendoButton] = [],
                            @ViewBuilder game: () -> some View = { EmptyView() }) -> some View {
        HStack(spacing: canvas.u(8)) {
            Text(name).seleneFont(.compactCaption).foregroundColor(SeleneTheme.ink90).lineLimit(1)
            Spacer(minLength: canvas.u(8))
            if let detail { NextendoValue(text: detail) }
            game()
            ForEach(buttons.indices, id: \.self) { index in
                action(buttons[index], row: row, index: index)
                    .disabled(!canUpdateFriends)
            }
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
        .padding(.vertical, canvas.u(SeleneTokens.Space.hairline))
        .id("selene-row-\(row)")
    }

    private func friendNotice(_ key: String, isError: Bool) -> some View {
        Text(text(key))
            .seleneFont(.compactCaption)
            .foregroundColor(isError ? SeleneTheme.danger : SeleneTheme.ink90)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
    }

    private func sendFriendCode() {
        guard canUpdateFriends else { return }
        updateFriend(.send(code: friendCode))
    }

    private func requestButtons(_ pid: UInt64) -> [NextendoButton] {
        [.init("Accept") { updateFriend(.accept(pid: pid)) },
         .init("Decline") { updateFriend(.decline(pid: pid)) }]
    }

    private func removeButton(_ friend: NextendoAccountSnapshot.Friend) -> NextendoButton {
        .init("Remove friend") {
            guard canUpdateFriends else { return }
            friendCodeFocused = false
            nextendo.friendToRemove = friend
        }
    }

    private func recentButton(_ player: NextendoAccountSnapshot.Player) -> NextendoButton? {
        guard friendData?.canAdd(player) == true, let code = player.friendCode else { return nil }
        return .init("Add") { updateFriend(.send(code: code)) }
    }

    private func updateFriend(_ action: NextendoFriendAction) {
        friendCodeFocused = false
        nextendo.updateFriend(action, clientID: clientID)
    }

    private func requestRowID(_ pid: UInt64) -> String { "nextendoRequest-\(pid)" }
    private func friendRowID(_ pid: UInt64) -> String { "nextendoFriend-\(pid)" }
    private func recentPlayerRowID(_ pid: UInt64) -> String { "nextendoRecent-\(pid)" }

    private var openProfile: NextendoButton {
        .init("Open my profile", symbol: "arrow.up.right") { openURL(URL(string: "https://nextendo.network/account")!) }
    }

    private func action(_ button: NextendoButton, row: String, index: Int, outline: Bool = true) -> some View {
        Button(action: button.action) {
            HStack(spacing: canvas.u(4)) {
                Text(text(button.title))
                if let symbol = button.symbol {
                    Image(systemName: symbol).accessibilityHidden(true)
                }
            }
            .seleneFont(.compactCaption, .semibold)
            .foregroundColor(SeleneTheme.glyph)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
            .padding(.vertical, canvas.u(SeleneTokens.Space.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay {
            if outline && focusedRow == row && focusedButton == index {
                Capsule().strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(2)).allowsHitTesting(false)
            }
        }
    }

    private func toggleFriends() {
        withAnimation(reduceMotion ? nil : SeleneTheme.quick) { friendsExpanded.toggle() }
    }

    private func toggleRecent() {
        withAnimation(reduceMotion ? nil : SeleneTheme.quick) { recentExpanded.toggle() }
    }

    private func copyCode() {
        guard let code = nextendo.account?.friendCode, copiedCode != code else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(code, forType: .string) else { SoundEffectService.shared.play(.error); return }
        SoundEffectService.shared.play(.success)
        copiedCode = code
    }

    private func endNextendoVisit() {
        nextendo.endVisit()
        resetFriendsPanel()
        copiedCode = nil
    }

    private func resetFriendsPanel() {
        friendsExpanded = false
        recentExpanded = false
        friendCode = ""
        friendCodeFocused = false
    }

    private func text(_ key: String) -> String { L10n.text(key, context: localization) }

    private func steamGridDBAction() {
        if viewModel.hasSteamGridDBKey { viewModel.removeSteamGridDBKey() }
        else { viewModel.isEditingSteamGridDBKey = true }
    }

    private func preference(_ key: WritableKeyPath<LocalProfile, Bool?>) -> Binding<Bool> {
        Binding(get: { profile?[keyPath: key] == true }, set: { onProfilePreference(key, $0) })
    }

    private func publishActions() {
        if !showsMultiplayer {
            onActions([
            .init(id: "IGDB", title: "IGDB",
                  secondary: igdb.isConfigured ? (title: "Remove", activate: { Task { await igdb.remove() }; return }) : nil) {
                igdb.isEditing = true
            },
            .init(id: "SteamGridDB", title: "SteamGridDB") { steamGridDBAction() },
            ])
            return
        }
        var actions: [SettingsRowAction] = accountOnly ? [] : [.value("multiplayerVPN", "Private network (VPN)", cycle: stepVPN)]
        if !accountOnly && vpn != .none {
            actions.append(.init(id: "multiplayerVPNStatus", title: vpnActionTitle, rowID: "multiplayerVPNStatus", activate: openVPN))
        }
        if accountOnly {
            if profile != nil {
                let online = preference(\.appearsOnline)
                let game = preference(\.showsCurrentGame)
                actions += [
                    .init(id: "appearsOnline", title: "Appear online", rowID: "Appear online") { online.wrappedValue.toggle() },
                    .init(id: "showsCurrentGame", title: "Show current game", rowID: "Show current game") { game.wrappedValue.toggle() },
                ]
            }
            let buttons = accountButtons
            actions.append(.init(id: "nextendo", title: "Nextendo", rowID: accountRowID, isEnabled: canActivateNextendo,
                                 secondary: buttons.dropFirst().first.map { ($0.title, $0.action) },
                                 additionalButtons: buttons.dropFirst(2).map(\.action), activate: buttons[0].action))
            if showFriends {
                actions.append(.init(id: friendsRowID, title: "Friends", rowID: friendsRowID, activate: toggleFriends))
                if accountOnly || friendsExpanded {
                    actions.append(.init(id: refreshFriendsRowID, title: "Refresh friends", rowID: refreshFriendsRowID,
                                         isEnabled: canRefreshFriends, activate: refreshFriends))
                }
                if friendsExpanded {
                    actions.append(.init(id: addRowID, title: "Add a friend", rowID: addRowID, isEnabled: canUpdateFriends,
                                         secondary: ("Add", sendFriendCode)) { friendCodeFocused = true })
                    for player in friendData?.requests ?? [] {
                        actions.append(friendActionRow(requestRowID(player.id), buttons: requestButtons(player.id)))
                    }
                    actions.append(.init(id: recentRowID, title: "Recently played with", rowID: recentRowID, activate: toggleRecent))
                    if recentExpanded {
                        for player in friendData?.recentPlayers ?? [] {
                            if let button = recentButton(player) {
                                actions.append(friendActionRow(recentPlayerRowID(player.id), buttons: [button]))
                            }
                        }
                    }
                    for friend in friends ?? [] {
                        actions.append(friendActionRow(friendRowID(friend.id), buttons: [removeButton(friend)]))
                    }
                    actions.append(.init(id: linksRowID, title: openProfile.title, rowID: linksRowID, activate: openProfile.action))
                }
            }
        }
        if accountOnly {
            onActions(actions)
            return
        }
        actions += [
            .value("multiplayerDefault", "Default for games", cycle: stepDefault),
            .init(id: "multiplayerAdvanced", title: "Advanced") { advanced.toggle() },
        ]
        if advanced {
            actions += [.value("multiplayerLocalMode", "Local network mode", cycle: stepLocalMode),
                        .value("multiplayerAdapter", "Network adapter", cycle: stepAdapter)]
            if supportsNextendo {
                actions.append(.init(id: "nextendoClientID", title: "Nextendo client ID", rowID: advancedRowID, isEnabled: !nextendo.isBusy) {
                    nextendo.isEditingClient = true
                })
            }
        }
        onActions(actions)
    }

    private func friendActionRow(_ row: String, buttons: [NextendoButton]) -> SettingsRowAction {
        .init(id: row, title: buttons[0].title, rowID: row, isEnabled: canUpdateFriends,
              secondary: buttons.dropFirst().first.map { ($0.title, $0.action) }, activate: buttons[0].action)
    }
}

private struct NextendoButton {
    let title: String
    let symbol: String?
    let action: () -> Void

    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }
}

private struct NextendoValue: View {
    let text: String

    var body: some View {
        Text(text).seleneFont(.compactCaption).foregroundColor(SeleneTheme.ink60).lineLimit(1)
    }
}

private struct NextendoFriendLine<Trailing: View>: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    let friend: NextendoAccountSnapshot.Friend
    let revision: UUID
    let service: NextendoAccountService
    let rememberTitle: (String, String) -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: canvas.u(8)) {
            NextendoAvatar(service: service, pid: friend.id, initial: String(friend.name.prefix(1)), revision: revision)
            Text(friend.name).seleneFont(.compactCaption).foregroundColor(SeleneTheme.ink90).lineLimit(1)
            if friend.favorite {
                MaterialIconView(.favorite, size: 16).foregroundColor(SeleneTheme.glyph)
                    .accessibilityLabel(L10n.text("Favorite", context: locale))
            }
            Spacer(minLength: canvas.u(8))
            HStack(spacing: canvas.u(4)) {
                SeleneStatusDot(text: L10n.text(status, context: locale), color: color).fixedSize()
                if friend.presence == .playing {
                    NextendoGameTitle(service: service, name: friend.game, id: friend.gameID, prefix: "· ",
                                      rememberTitle: rememberTitle)
                }
            }
            trailing()
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
        .padding(.vertical, canvas.u(SeleneTokens.Space.hairline))
        .background(SeleneTheme.glass.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: canvas.u(7), style: .continuous))
    }

    private var status: String {
        switch friend.presence {
        case .offline: return "Offline"
        case .online: return "Online"
        case .playing: return "In game"
        }
    }

    private var color: Color {
        switch friend.presence {
        case .offline: return SeleneTheme.ink60
        case .online: return SeleneTheme.statusOK
        case .playing: return SeleneTheme.statusCloud
        }
    }
}

private struct NextendoGameTitle: View {
    @Environment(\.nxAppLocale) private var locale
    @Environment(\.passiveSettingsArrival) private var passiveArrival
    @State private var resolved: (key: String, title: String)?
    let service: NextendoAccountService
    let name: String?
    let id: String?
    var prefix = ""
    var rememberTitle: ((String, String) -> Void)? = nil
    private var key: String { "\(id ?? "")|\(locale.language.rawValue)" }

    var body: some View {
        Group {
            if let title = name ?? (resolved?.key == key ? resolved?.title : nil) {
                NextendoValue(text: prefix + title).help(title)
            }
        }
        .task(id: passiveArrival ? nil : key) {
            guard !passiveArrival, name == nil, let id,
                  let title = try? await service.gameTitle(id: id, language: locale.language),
                  !Task.isCancelled else { return }
            resolved = (key, title)
            rememberTitle?(title, id)
        }
    }
}

private struct NextendoAvatar: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.passiveSettingsArrival) private var passiveArrival
    @State private var loaded: (key: String, image: NSImage)?
    let service: NextendoAccountService
    let pid: UInt64?
    var image: Data? = nil
    var initial: String? = nil
    let revision: UUID
    private var key: String { "nextendo-avatar|\(revision)|\(pid ?? 0)" }

    var body: some View {
        let side = canvas.u(initial == nil ? 28 : 20)
        ZStack {
            Circle().fill(SeleneTheme.glassSolid)
            if let avatar = image.flatMap(NSImage.init(data:)) ?? TileArtMemo.shared.object(forKey: key as NSString)
                ?? (loaded?.key == key ? loaded?.image : nil) {
                Image(nsImage: avatar).resizable().scaledToFill()
            } else if let initial {
                Text(initial).seleneFont(.attribution, .semibold).foregroundColor(SeleneTheme.ink90)
            } else {
                Image(systemName: "person.fill").seleneFont(.caption, .semibold).foregroundColor(SeleneTheme.rowIcon)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(SeleneTheme.ink15, lineWidth: canvas.u(1)) }
        .accessibilityHidden(true)
        .task(id: passiveArrival ? nil : key) {
            guard !passiveArrival, image == nil, let pid, TileArtMemo.shared.object(forKey: key as NSString) == nil,
                  let data = try? await service.avatar(pid: pid),
                  !Task.isCancelled, let avatar = NSImage(data: data) else { return }
            TileArtMemo.store(avatar, for: key as NSString)
            loaded = (key, avatar)
        }
    }
}
