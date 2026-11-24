import Foundation
import Combine

public enum AppRoute: Equatable {
    /// Spotlight, the home screen.
    case library
    /// The whole library as one grid (Selene's Collection).
    case collection
    case profile
    case profileCollection(ProfilePageCard)
    case integrations
    case detail(UUID)
    case settings(SettingsSection)
    case addGame
    case gameInbox
    case console

    /// Drawn over the screen it was opened from, which stays behind, blurred.
    public var isOverlay: Bool { self == .addGame || self == .console }
    public var isCollection: Bool {
        if case .profileCollection = self { return true }
        return self == .collection
    }
}

public enum IntegrationID: CaseIterable, Hashable, Sendable {
    case switchGames, steam, macApps, drive, nextendo, saves, images

    public var isGameSource: Bool { self == .switchGames || self == .steam || self == .macApps }
}

/// A full-screen page covers lower UI layers while their shared background stays mounted.
public enum ShellBackdropCover: Equatable {
    case none, themePicker, welcome, setup

    public var priority: Double {
        switch self {
        case .none: return 0
        case .themePicker: return 1
        case .welcome: return 2.4
        case .setup: return 2.5
        }
    }

    public func covers(_ layer: Double) -> Bool { priority > layer }

    public static func resolve(setup: Bool, welcome: Bool, themePicker: Bool) -> Self {
        if setup { return .setup }
        if welcome { return .welcome }
        return themePicker ? .themePicker : .none
    }
}

/// A press on the control center, whatever device it came from.
public enum MenuStep { case left, right, up, down, previous, next, confirm, back }

/// What the shell runs after a `confirm`: the focused icon, card entry or Power pill.
public enum MenuOutcome: Equatable {
    case none
    case action(MenuAction)
    case entry(MenuEntry)
    case power(PowerAction)
}

public final class AppRouter: ObservableObject {
    @Published public private(set) var route: AppRoute = .library
    @Published public private(set) var isReturningFromBack = false
    @Published public var isMenuPresented = false
    @Published public var isSearchPresented = false
    @Published package var sortMenu: LibrarySort?
    /// True while the full-screen screenshot viewer is open; the shell ignores its global shortcuts.
    @Published public var isScreenshotViewerOpen = false
    @Published public var menuSelection = MenuSelectionModel()
    /// The activity card replaces the control-center row while the menu still owns input.
    @Published public var activityCenterFocus: ActivityCenterFocus?
    /// The menu's Theme screen (colors, then background) is open in place of its row.
    @Published public var isThemePickerOpen = false
    /// A Spotlight item key waiting to be lifted for moving (see `requestSpotlightMove`).
    @Published public var pendingSpotlightMove: String?
    /// A game id waiting for Spotlight to select it (Details' More like this).
    @Published public var pendingSpotlightSelect: UUID?
    @Published public var integrationBarFocused = false
    @Published public var integrationFocus: IntegrationID?
    @Published public private(set) var integrationDetail: IntegrationID?
    @Published public private(set) var settingsRowID: String?

    private var history: [AppRoute] = []
    private var profileSpotlightKey: String?
    private var inboxSetting: AnyCancellable?

    public init(settings: AppSettingsStore? = nil) {
        inboxSetting = settings?.$settings.map(\.gameInboxEnabled).removeDuplicates().sink { [weak self] enabled in
            guard let self else { return }
            self.menuSelection.gameInboxEnabled = enabled
            if !enabled {
                self.history.removeAll { $0 == .gameInbox }
                if self.route == .gameInbox {
                    if self.history.isEmpty { self.showLibrary() } else { self.back() }
                }
            }
        }
    }

    /// The route the app opens on for the Start on setting.
    public static func initialRoute(for startOn: StartScreen, last: StartScreen) -> AppRoute {
        switch startOn {
        case .spotlight: return .library
        case .collection: return .collection
        case .last: return last == .collection ? .collection : .library
        }
    }

    /// Opens on `route` with nothing to go back to.
    public func setInitialRoute(_ route: AppRoute) {
        guard route != .gameInbox || menuSelection.gameInboxEnabled else { return }
        isReturningFromBack = false
        history.removeAll()
        integrationBarFocused = false
        settingsRowID = nil
        self.route = route
    }

    /// Left and Right move along the row. They do nothing while a card or the Power pills are open.
    public func moveMenu(by delta: Int) {
        guard !menuSelection.isSubmenuOpen else { return }
        menuSelection.move(by: delta)
    }

    /// Up and Down move the Power pills. They do nothing while the pills are closed.
    public func movePowerMenu(by delta: Int) {
        guard menuSelection.isPowerOpen else { return }
        menuSelection.movePower(by: delta)
    }

    /// Up and Down move the open card's entries. They do nothing while it is closed.
    public func moveEntryMenu(by delta: Int) { menuSelection.moveEntry(by: delta) }

    public func openPowerMenu() { menuSelection.openPower() }

    /// A press on Profile or Library: the card opens above its icon.
    public func openEntryMenu() { menuSelection.openEntries() }

    /// B on a card: closes it and leaves the menu open, the focus on its icon.
    public func closeEntryMenu() { menuSelection.closeEntries() }

    /// B on the Power pills: closes them and leaves the menu open.
    public func closePowerMenu() { menuSelection.closePower() }

    /// One press on the open control center, from the keyboard or a controller: moves the focus or closes
    /// the open panel, and says what the shell must run, as Selene's MenuScreen does.
    @discardableResult
    public func menuStep(_ step: MenuStep) -> MenuOutcome {
        switch step {
        case .left: moveMenu(by: -1)
        case .right: moveMenu(by: 1)
        case .up: movePowerMenu(by: -1); moveEntryMenu(by: -1)
        case .down: movePowerMenu(by: 1); moveEntryMenu(by: 1)
        case .previous, .next:
            let delta = step == .previous ? -1 : 1
            guard menuSelection.isSubmenuOpen || activityCenterFocus != nil else {
                moveMenu(by: delta)
                return .none
            }
            // Settings leaves the control center; only an explicit confirm opens it.
            let panels = MenuAction.allCases.filter { $0 != .settings }
            if let index = panels.firstIndex(of: menuSelection.selected), panels.indices.contains(index + delta) {
                return .action(panels[index + delta])
            }
        case .confirm:
            if menuSelection.isPowerOpen { return .power(menuSelection.power) }
            if menuSelection.isEntryOpen { return .entry(menuSelection.entry) }
            return .action(menuSelection.selected)
        case .back:
            if activityCenterFocus != nil { activityCenterFocus = nil }
            else if menuSelection.isPowerOpen { closePowerMenu() }
            else if menuSelection.isEntryOpen { closeEntryMenu() }
            else { closeMenu() }
        }
        return .none
    }

    /// A press on a row icon, by pointer or by A: the focus lands on it, and its card or Power's pills open, or close
    /// when they were already open on it. The submenu of another icon closes first; the other icons hold none.
    public func pressMenuIcon(_ action: MenuAction) {
        activityCenterFocus = nil
        let wasFocused = menuSelection.selected == action
        menuSelection.selected = action
        switch action {
        case .profile, .library:
            closePowerMenu()
            if wasFocused, menuSelection.isEntryOpen { closeEntryMenu() } else { openEntryMenu() }
        case .power:
            closeEntryMenu()
            if wasFocused, menuSelection.isPowerOpen { closePowerMenu() } else { openPowerMenu() }
        case .activityCenter, .settings:
            closePowerMenu()
            closeEntryMenu()
        }
    }

    public func navigate(to route: AppRoute) {
        guard route != self.route, route != .gameInbox || menuSelection.gameInboxEnabled else { return }
        isReturningFromBack = false
        integrationBarFocused = false
        settingsRowID = nil
        history.append(self.route)
        self.route = route
    }

    /// Asks Spotlight to select the item with this key and lift it for moving.
    /// Callers: a card's Y menu, and Game options' Move row.
    public func requestSpotlightMove(_ key: String) { pendingSpotlightMove = key }

    /// Asks Spotlight to select this game, switching to All games when the
    /// current filter hides it (the same path as Surprise me).
    public func requestSpotlightSelect(_ id: UUID) { pendingSpotlightSelect = id }

    /// The screen under Add game or the console: the one they were opened from (Spotlight when unknown).
    public var underlyingRoute: AppRoute {
        history.last { !$0.isOverlay } ?? .library
    }

    public func showDetail(_ id: UUID) { navigate(to: .detail(id)) }
    public func openSettings(_ section: SettingsSection = .startUp, rowID: String? = nil) {
        navigate(to: .settings(section))
        settingsRowID = rowID
    }
    public func takeSettingsRowFocus() { settingsRowID = nil }
    public func openIntegrations() {
        guard route == .library || route == .collection else { return }
        integrationDetail = nil
        integrationFocus = IntegrationID.allCases.first
        navigate(to: .integrations)
    }
    public func showIntegrationDetail(_ id: IntegrationID) {
        guard route == .integrations else { return }
        integrationFocus = id
        integrationDetail = id
    }
    public func backFromIntegration() {
        if integrationDetail != nil { integrationDetail = nil }
        else { back() }
    }
    /// Only directional input or a return from the page can put focus on the home bar.
    public func stepIntegrationBar(_ step: MenuStep?, profileFocused: inout Bool, hasProfile: Bool) -> Bool {
        guard route == .library || route == .collection else { return false }
        if integrationBarFocused {
            switch step {
            case .confirm: openIntegrations(); return true
            case .right where hasProfile:
                integrationBarFocused = false; profileFocused = true; return true
            case .down, .back:
                integrationBarFocused = false; return true
            case .left, .right, .up: return true
            default: integrationBarFocused = false; return false
            }
        }
        if (profileFocused && step == .left) || (!hasProfile && step == .up) {
            profileFocused = false
            integrationBarFocused = true
            return true
        }
        return false
    }
    public func openAddGame() { navigate(to: .addGame) }
    public func openGameInbox() { navigate(to: .gameInbox) }
    public func openConsole() { navigate(to: .console) }
    public func openCollection() { navigate(to: .collection) }
    public var previousRoute: AppRoute? { history.last }

    public func openSpotlightDetails(_ id: UUID, returningTo selection: String?) {
        profileSpotlightKey = selection
        requestSpotlightSelect(id)
        navigate(to: .library)
    }

    public func takeProfileSpotlightKey() -> String? {
        defer { profileSpotlightKey = nil }
        return profileSpotlightKey
    }

    public func showLibrary() {
        isReturningFromBack = false
        history.removeAll()
        integrationBarFocused = false
        settingsRowID = nil
        route = .library
    }

    public func back() {
        guard let previous = history.popLast() else {
            isReturningFromBack = false
            return
        }
        isReturningFromBack = true
        integrationBarFocused = route == .integrations && (previous == .library || previous == .collection)
        settingsRowID = nil
        route = previous
    }

    /// Closes the menu and any of its panels.
    public func closeMenu() {
        isMenuPresented = false
        isThemePickerOpen = false
        activityCenterFocus = nil
        menuSelection.closePower()
        menuSelection.closeEntries()
    }
}
