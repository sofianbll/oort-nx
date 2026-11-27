import AppKit
import LocalAuthentication
import SwiftUI
import OortLibrary
import ArcanePorting

struct ProfileFlow {
    enum Page { case picker }
    var page: Page
    var selected: UUID?
    var atStartup = false
    var returnsToMenu = false
    var change: Change?

    struct Change: Equatable {
        enum Step { case unlock, confirm, wait }
        var target: LocalProfile
        var startsGuest: Bool
        var step: Step
        var quits = false

        func requiresConfirmation(current: UUID?, running: Bool, endsGuest: Bool) -> Bool {
            target.id != current && (running || startsGuest || endsGuest)
        }

        func canCommit(current: UUID?, running: Bool) -> Bool {
            (!quits && target.id == current) || !running
        }
    }

    static func requestPicker() {
        NotificationCenter.default.post(name: .nxToggleProfilePicker, object: nil)
    }
}

extension EnvironmentValues {
    @Entry var profilePortrait: LocalProfile?
}

extension Notification.Name {
    static let nxProfileInput = Self("NXProfileInput")
    static let nxSettingsPINInput = Self("NXSettingsPINInput")
    static let nxOpenLocalProfile = Self("NXOpenLocalProfile")
    static let nxToggleProfilePicker = Self("NXToggleProfilePicker")
}

extension AppShellView {
    @ViewBuilder var profilePresenceTask: some View {
        if viewModel.setupCompleted, let profile = profiles.active, let nextendo = viewModel.profileNextendo {
            let clientID = settings.settings.nextendoClientID ?? NextendoLaunch.buildClientID
            let eligible = {
                profiles.active?.id == profile.id && profiles.active?.sharesPresence == true && !profiles.failed
                    && profileFlow?.atStartup != true
                    && (runningGames.runningGameIDs.isEmpty || profiles.active?.sharesCurrentGame == false)
                    && !SteamPlayCoordinator.blocksIdlePresence(SteamPlayCoordinator.shared.states)
                    && viewModel.launchingGameId == nil && viewModel.launchOverlay == nil
                    && (settings.settings.nextendoClientID ?? NextendoLaunch.buildClientID) == clientID
            }
            NextendoPresenceTask(account: nextendo, clientID: !steamBlocksIdlePresence && eligible() ? clientID : nil,
                                 eligible: eligible)
                .id(profile.id)
        }
    }

    @ViewBuilder var profileLayer: some View {
        if let flow = profileFlow, profiles.active != nil {
            switch flow.page {
            case .picker:
                ZStack {
                    ProfilePickerView(profiles: profiles, initialSelection: flow.selected,
                                      canClose: !flow.atStartup, isOverlay: !flow.atStartup, games: viewModel.libraryGames,
                                      avatarGames: viewModel.visibleCatalogGames, artwork: artwork,
                                      onChoose: chooseProfile, onClose: closeProfile,
                                      onActiveEdited: applyActiveProfile, onRemoved: { id in
                        if settings.settings.profileStartup == .profile(id) { settings.settings.profileStartup = .ask }
                    }, onGuest: { requestProfile($0, startsGuest: true) }, canRemove: canRemoveProfile,
                       onEditActive: flow.atStartup || profiles.guest != nil ? nil : {
                           closeProfile()
                           router.closeMenu()
                           router.openSettings(.profileIdentity)
                       },
                       dialogOwnsInput: flow.change != nil)
                    .seleneOverlayOwnership(flow.change == nil)
                    if let change = flow.change {
                        SeleneOverlay(style: .profileRemoval, onOutside: cancelProfileChange) {
                            if change.step == .unlock {
                                ProfilePINDialog(title: "Unlock profile", allowsTouchID: true, onCancel: cancelProfileChange,
                                                 onTouchID: { verifiedProfile(change) }) { pin in
                                    guard change.target.matchesPIN(pin) else { return "Incorrect code." }
                                    verifiedProfile(change)
                                    return nil
                                }
                            } else {
                                ProfileSwitchDialog(startsGuest: change.startsGuest, endsGuest: profiles.guest != nil,
                                                    hasGame: !profileRunningGames.isEmpty, hasSteam: steamBlocksIdlePresence,
                                                    waiting: change.step == .wait, onCancel: cancelProfileChange,
                                                    onConfirm: { confirmProfileChange(change) })
                                    .task(id: change.step) {
                                        guard change.step == .wait else { return }
                                        while !Task.isCancelled {
                                            if !profileSwitchBlocked() { finishProfileChange(change); return }
                                            try? await Task.sleep(for: .milliseconds(250))
                                        }
                                    }
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .animation(Motion.overlay(reduceMotion), value: flow.change?.step)
            }
        }
    }

    func openProfile(_ page: ProfileFlow.Page, fromMenu: Bool = false) {
        guard let active = profiles.active, profileFlow == nil, viewModel.launchOverlay == nil,
              !viewModel.showSetupCheck, !showsWelcome, !isCloseGameOpen else { return }
        guard !router.requestSettingsDeparture({ openProfile(page, fromMenu: fromMenu) }) else { return }
        router.isPalettePresented = false
        viewModel.profileOwnsInput = true
        profileFlow = ProfileFlow(page: page, selected: active.id, returnsToMenu: fromMenu)
    }

    var launcherIsFrontmost: Bool {
        NSApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    func openProfilePage() {
        guard profiles.active != nil, profileFlow == nil, viewModel.launchOverlay == nil,
              !viewModel.showSetupCheck, !showsWelcome, !isCloseGameOpen, router.route != .profile else { return }
        profilePageFocus = nil
        router.navigate(to: .profile)
    }

    func toggleProfilePicker() {
        guard launcherIsFrontmost, !nativeMenus.isTracking, !nativeDialogOwnsInput,
              !router.isScreenshotViewerOpen, !isCloseGameOpen else { return }
        if let profileFlow {
            if profileFlow.change != nil { self.profileFlow?.change = nil }
            else if profileFlow.page == .picker, !profileFlow.atStartup { closeProfile() }
        } else {
            openProfile(.picker, fromMenu: router.isMenuPresented)
        }
    }

    func closeProfile() {
        profileFlow = nil
        viewModel.profileOwnsInput = false
    }

    func chooseProfile(_ id: UUID) {
        if let target = (profiles.profiles + (profiles.guest.map { [$0] } ?? [])).first(where: { $0.id == id }) {
            requestProfile(target, startsGuest: false)
        }
    }

    private var profileRunningGames: [PortedGame] {
        viewModel.libraryGames.filter { runningGames.isRunningForProfileSwitch($0) }
    }

    private func profileSwitchBlocked() -> Bool {
        runningGames.refresh()
        let steam = SteamPlayCoordinator.shared
        steam.refresh()
        return !profileRunningGames.isEmpty || SteamPlayCoordinator.blocksIdlePresence(steam.states)
            || viewModel.launchingGameId != nil || viewModel.launchOverlay != nil
    }

    private func canRemoveProfile(_ profile: LocalProfile) -> Bool {
        guard !profile.isLocked, profiles.guest == nil else { return false }
        guard profile.id == profiles.active?.id else { return true }
        guard profileFlow?.atStartup != true, let index = profiles.profiles.firstIndex(where: { $0.id == profile.id }) else { return false }
        let remaining = profiles.profiles.filter { $0.id != profile.id }
        return !remaining.isEmpty && !remaining[min(index, remaining.count - 1)].isLocked
            && profileRunningGames.isEmpty && !steamBlocksIdlePresence && viewModel.launchingGameId == nil
    }

    private func requestProfile(_ target: LocalProfile, startsGuest: Bool) {
        guard profileFlow?.change == nil else { return }
        let change = ProfileFlow.Change(target: target, startsGuest: startsGuest, step: .unlock)
        if target.isLocked && (profileFlow?.atStartup == true || profiles.active?.id != target.id) {
            profileFlow?.change = change
        } else { verifiedProfile(change) }
    }

    private func verifiedProfile(_ change: ProfileFlow.Change) {
        if change.step == .unlock, let pending = profileFlow?.change, pending != change { return }
        guard profileFlow != nil else { return }
        if change.requiresConfirmation(current: profiles.active?.id, running: profileSwitchBlocked(), endsGuest: profiles.guest != nil) {
            var pending = change
            pending.step = .confirm
            profileFlow?.change = pending
        } else { finishProfileChange(change) }
    }

    private func confirmProfileChange(_ change: ProfileFlow.Change) {
        guard profileFlow?.change == change else { return }
        if !profileSwitchBlocked() { finishProfileChange(change); return }
        for game in profileRunningGames { runningGames.close(game, forceIfUnresponsive: false) }
        var pending = change
        pending.step = .wait
        profileFlow?.change = pending
    }

    private func cancelProfileChange() { profileFlow?.change = nil }

    func requestGuestQuit() {
        guard let guest = profiles.guest else { return }
        if profileFlow == nil { openProfile(.picker, fromMenu: router.isMenuPresented) }
        guard profileFlow?.change == nil, profileFlow != nil else { return }
        profileFlow?.page = .picker
        profileFlow?.change = .init(target: guest, startsGuest: false, step: .confirm, quits: true)
    }

    private func finishProfileChange(_ change: ProfileFlow.Change) {
        guard change.canCommit(current: profiles.active?.id, running: profileSwitchBlocked()) else {
            var pending = change
            pending.step = .confirm
            profileFlow?.change = pending
            return
        }
        if change.quits {
            closeProfile()
            AppDelegate.quitAfterGuestConfirmation()
            return
        }
        let success = if change.startsGuest { profiles.beginGuest(change.target) }
            else if change.target.id == profiles.guest?.id { true }
            else { profiles.choose(change.target.id) }
        guard success else { cancelProfileChange(); return }
        applyActiveProfile()
        if profileFlow?.returnsToMenu == true { router.closeMenu() }
        closeProfile()
    }

    func applyActiveProfile() {
        guard let profile = profiles.active else { return }
        let scopedID = profile.id == profiles.originalID ? nil : profile.id
        if playSessions.profileID != scopedID {
            playSessions.profileID = scopedID
            viewModel.refreshProfileFavorites()
        }
        if profile.look != .init(settings.settings) {
            profile.look.apply(to: &settings.settings)
        }
        if settings.settings.launcherChoices.gamepadLayout != profile.gamepadLayout {
            settings.settings.launcherChoices.gamepadLayout = profile.gamepadLayout
        }
        ThemeStore.shared.apply(id: profile.look.theme)
    }

    func postProfileAction(_ action: GamepadAction) {
        NotificationCenter.default.post(name: .nxProfileInput, object: action)
    }

    func profileKey(_ event: NSEvent) -> NSEvent? {
        if profileFlow?.change?.step == .unlock {
            return ProfilePINDialog.handleKey(event, input: .nxProfileInput)
        }
        let key = event.charactersIgnoringModifiers?.lowercased()
        let typing = event.window?.firstResponder is NSText
        if typing && event.keyCode != 53 { return event }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
        let action: GamepadAction
        switch event.keyCode {
        case 123: action = .navigateLeft
        case 124: action = .navigateRight
        case 125: action = .navigateDown
        case 126: action = .navigateUp
        case 36, 49, 76: action = .confirm
        case 53: action = .cancel
        case 51: action = .secondaryAction
        case 12: action = .tabPrevious
        case 14: action = .tabNext
        case 48:
            let previous = event.modifierFlags.contains(.shift)
            action = profileFlow == nil && router.route == .profile
                ? (previous ? .tabPrevious : .tabNext) : (previous ? .navigateLeft : .navigateRight)
        default:
            switch key {
            case "x": action = .secondaryAction
            case "y": action = .contextAction
            case "+", "=": action = .menu
            default: return event
            }
        }
        if !event.isARepeat || [.navigateLeft, .navigateRight, .navigateUp, .navigateDown].contains(action) {
            postProfileAction(action)
        }
        return nil
    }
}

struct ProfileSwitchDialog: View {
    let startsGuest: Bool
    let endsGuest: Bool
    let hasGame: Bool
    let hasSteam: Bool
    let waiting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var focus = SeleneConfirmButton.cancel

    var body: some View {
        let title = endsGuest ? "End guest session?" : startsGuest ? "Play as guest?" : "Switch profile?"
        let primary = hasGame ? "Close Game" : "Continue"
        let details = [
            hasGame ? "Unsaved progress will be lost." : nil,
            hasSteam ? "Close any Steam games yourself before switching." : nil,
            startsGuest ? "Guests play Switch games offline with separate saves. A future guest cannot resume this session." : nil,
            endsGuest ? "The guest cannot resume this session. Its saves are kept separately on this Mac." : nil
        ].compactMap { $0 }.map { L10n.text($0) }.joined(separator: "\n")
        VStack {
            if waiting {
                SeleneChoiceDialog(title: title, message: L10n.text(hasSteam ? "Close any Steam games yourself before switching." : "Waiting for the game to close…"),
                                   choices: ["Cancel"], focus: .constant(0), onCancel: onCancel) { _ in onCancel() }
            } else {
                SeleneConfirmDialog(title: title, message: details, confirmTitle: primary,
                                    destructive: hasGame || endsGuest, focus: $focus,
                                    onCancel: onCancel, onConfirm: onConfirm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .nxProfileInput)) { note in
            switch note.object as? GamepadAction {
            case .navigateLeft: focus = .left
            case .navigateRight: focus = .right
            case .confirm: accept()
            case .cancel: onCancel()
            default: break
            }
        }
    }

    private func accept() { if !waiting && focus == .confirm { onConfirm() } else { onCancel() } }
}

struct ProfilePINDialog: View {
    let title: String
    var allowsTouchID = false
    var input: Notification.Name = .nxProfileInput
    let onCancel: () -> Void
    var onTouchID: (() -> Void)?
    /// nil closes or advances the caller's flow; an error keeps the keypad open.
    let onPIN: (String) -> String?
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.seleneHintsCovered) private var covered
    @State private var keypad = ProfileKeypad()
    @State private var hover = SeleneHoverFocus()
    @State private var error: String?
    @State private var shakes = 0
    @State private var biometric = LAContext()
    @State private var canUseTouchID = false
    @State private var authenticating = false
    @State private var biometricTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.control)) {
            Label(L10n.text(title, context: localization), systemImage: "lock.fill")
                .seleneFont(.screen, .semibold)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.text(error ?? "Use four digits.", context: localization))
                .seleneFont(.text).foregroundStyle(error == nil ? SeleneTheme.ink75 : SeleneTheme.danger)
            HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                ForEach(0..<LocalProfile.pinLength, id: \.self) { index in
                    Image(systemName: index < keypad.count ? "circle.fill" : "circle")
                        .seleneFont(.text)
                }
            }
            .foregroundStyle(error == nil ? SeleneTheme.ink : SeleneTheme.danger)
            .modifier(SeleneShake(amount: reduceMotion ? 0 : CGFloat(shakes),
                                  distance: canvas.u(SeleneTokens.Space.compact)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("%lld of %lld digits entered", [keypad.count, LocalProfile.pinLength],
                                           context: localization))
            VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                ForEach(ProfileKeypad.rows.indices, id: \.self) { row in
                    HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                        ForEach(ProfileKeypad.rows[row], id: \.self, content: key)
                    }
                }
            }
            if canUseTouchID {
                SelenePillButton(title: "Touch ID", focused: false, enabled: !authenticating, action: authenticate)
            }
        }
        .foregroundStyle(SeleneTheme.ink)
        .modifier(SeleneDialogCard(width: nil))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            SeleneHintsBar(left: [HintItem(.b, "Cancel", action: onCancel), HintItem(.x, "Erase") { press(.erase) }],
                           right: (canUseTouchID ? [HintItem(.y, "Touch ID", action: authenticate)] : [])
                            + [HintItem(.navigate, "Move"), HintItem(.a, "Select") { press(keypad.selected) },
                               HintItem(.menu, "Validate", keyboard: .text("⌘↵")) { press(.validate) }])
        }
        .onAppear {
            if allowsTouchID {
                canUseTouchID = biometric.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
                    && biometric.biometryType == .touchID
            }
        }
        .onDisappear { biometricTask?.cancel(); biometric.invalidate() }
        .onReceive(NotificationCenter.default.publisher(for: input)) { note in
            guard !covered else { return }
            if let digit = note.object as? Int { press(.digit(digit)); return }
            switch note.object as? GamepadAction {
            case .navigateLeft: keypad.move(.left)
            case .navigateRight: keypad.move(.right)
            case .navigateUp: keypad.move(.up)
            case .navigateDown: keypad.move(.down)
            case .confirm: press(keypad.selected)
            case .menu, .menuHold: press(.validate)
            case .secondaryAction: press(.erase)
            case .contextAction: authenticate()
            case .cancel: onCancel()
            default: break
            }
        }
    }

    private func key(_ key: ProfileKeypad.Key) -> some View {
        let title: String?
        let icon: MaterialIcon?
        let label: String
        switch key {
        case .digit(let digit): title = String(digit); icon = nil; label = String(digit)
        case .erase: title = nil; icon = .backspace; label = "Erase"
        case .validate: title = nil; icon = .done; label = "Validate"
        }
        let enabled = !authenticating && (key != .validate || keypad.canValidate)
        let size = SeleneTokens.Space.profileKeypadKey
        return SelenePillButton(title: title, icon: icon, iconSize: SeleneTokens.Text.heading.rawValue, minWidth: size,
                               height: size, titleSize: .heading, horizontalPadding: 0, focused: keypad.selected == key,
                               fillsOnFocus: false, scalesOnFocus: false, enabled: enabled, tint: .white) {
            keypad.focus(key)
            press(key)
        }
        .disabled(!enabled)
        .accessibilityLabel(L10n.text(label, context: localization))
        .accessibilityAddTraits(keypad.selected == key ? .isSelected : [])
        .onHover { if hover.moved($0) { keypad.focus(key) } }
    }

    private func press(_ key: ProfileKeypad.Key) {
        guard !authenticating else { return }
        let previousCount = keypad.count
        if let pin = keypad.press(key) {
            error = onPIN(pin)
            if error != nil {
                keypad.focus(.digit(1))
                if !reduceMotion { withAnimation(SeleneTheme.shake) { shakes += 1 } }
            }
        } else if keypad.count != previousCount {
            error = nil
        }
    }

    /// Both callers give the same keys to the keypad; the rest of each screen is suspended.
    static func handleKey(_ event: NSEvent, input: Notification.Name) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        let action: GamepadAction
        if modifiers == [.command], [36, 76].contains(event.keyCode) {
            action = .menu
        } else {
            guard modifiers.subtracting(.shift).isEmpty else { return event }
            switch (event.keyCode, key) {
            case (123, _): action = .navigateLeft
            case (124, _): action = .navigateRight
            case (125, _): action = .navigateDown
            case (126, _): action = .navigateUp
            case (36, _), (49, _), (76, _): action = .confirm
            case (48, _): action = modifiers.contains(.shift) ? .navigateLeft : .navigateRight
            case (53, _): action = .cancel
            case (51, _), (117, _), (_, "x"): action = .secondaryAction
            case (_, "y"): action = .contextAction
            default:
                if let key, key.utf8.count == 1, let digit = Int(key) {
                    if !event.isARepeat { NotificationCenter.default.post(name: input, object: digit) }
                    return nil
                }
                return event
            }
        }
        if !event.isARepeat || [.navigateLeft, .navigateRight, .navigateUp, .navigateDown].contains(action) {
            NotificationCenter.default.post(name: input, object: action)
        }
        return nil
    }

    private func authenticate() {
        guard canUseTouchID, !authenticating else { return }
        authenticating = true
        biometricTask = Task { @MainActor in
            let accepted = (try? await biometric.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                                 localizedReason: L10n.text(title))) == true
            guard !Task.isCancelled else { return }
            authenticating = false
            if accepted { onTouchID?() }
        }
    }
}

private struct NextendoPresenceTask: View {
    @ObservedObject var account: NextendoSettings
    let clientID: String?
    let eligible: () -> Bool

    private struct Key: Equatable {
        let clientID: String?
        let revision: UUID
    }

    var body: some View {
        Color.clear.accessibilityHidden(true).allowsHitTesting(false)
            .task(id: Key(clientID: account.isSigningOut ? nil : clientID, revision: account.presenceRevision)) {
                guard !Task.isCancelled else { return }
                account.clearPresence()
                if let clientID, !account.isSigningOut {
                    await account.publishPresence(clientID: clientID, eligible: eligible)
                }
            }
    }
}
