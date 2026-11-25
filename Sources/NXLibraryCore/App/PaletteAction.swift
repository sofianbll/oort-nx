import Foundation

/// What the command palette can do besides games and settings: five sections of five at most, in the order they are
/// browsed. Each one is also somewhere else; the palette is only the shorter way.
public enum PaletteAction: String, CaseIterable, Sendable {
    case addGame, addApp, manageSources, refreshLibrary, gameInbox
    case myProfile, switchProfile, editProfile, theme, players
    case changeView, fullscreen, zoomIn, zoomOut, actualSize
    case controls, settings, controlCenter, activityCenter, checkUpdates
    case sleep, hide, relaunch, quit

    public enum Section: CaseIterable, Sendable {
        case library, profile, interface, help, power

        public var key: String {
            switch self {
            case .library: "Library"
            case .profile: "Profile"
            case .interface: "Interface"
            case .help: "Help"
            case .power: "Power"
            }
        }
    }

    public static let paletteShortcut = "⌘K"

    /// Offered on an empty field, in this order; the last game played comes before.
    public static let suggested: [PaletteAction] = [.addGame, .players, .theme, .controls, .switchProfile, .refreshLibrary, .fullscreen]

    /// The catalog key of its title.
    public var key: String {
        switch self {
        case .addGame: "Add Game"
        case .addApp: "Add an app…"
        case .manageSources: "Manage sources"
        case .refreshLibrary: "Library refresh"
        case .gameInbox: "Sort incoming files"
        case .myProfile: "My profile"
        case .switchProfile: "Switch profile"
        case .editProfile: "Edit profile"
        case .theme: "Theme"
        case .players: "Players"
        case .changeView: "Change view"
        case .fullscreen: "Fullscreen"
        case .zoomIn: "Larger interface"
        case .zoomOut: "Smaller interface"
        case .actualSize: "Actual size"
        case .controls: "Controls guide"
        case .settings: "Settings"
        case .controlCenter: "Control center"
        case .activityCenter: "Activity center"
        case .checkUpdates: "Check for Updates…"
        case .sleep: "Sleep"
        case .hide: "Hide"
        case .relaunch: "Restart app"
        case .quit: "Quit"
        }
    }

    public var title: String { L10n.text(key) }

    public var section: Section {
        switch self {
        case .addGame, .addApp, .manageSources, .refreshLibrary, .gameInbox: .library
        case .myProfile, .switchProfile, .editProfile, .theme, .players: .profile
        case .changeView, .fullscreen, .zoomIn, .zoomOut, .actualSize: .interface
        case .controls, .settings, .controlCenter, .activityCenter, .checkUpdates: .help
        case .sleep, .hide, .relaunch, .quit: .power
        }
    }

    public var icon: MaterialIcon {
        switch self {
        case .addGame, .addApp: .add
        case .manageSources: .collections
        case .refreshLibrary: .sync
        case .gameInbox: .folder
        case .myProfile, .switchProfile: .person
        case .editProfile: .edit
        case .theme: .palette
        case .players, .controls: .gamepad
        case .changeView: .swap
        case .fullscreen, .zoomIn, .zoomOut, .actualSize: .monitor
        case .settings: .settings
        case .controlCenter: .menu
        case .activityCenter: .notifications
        case .checkUpdates: .update
        case .sleep: .bedtime
        case .hide: .hidden
        case .relaunch: .restartAlt
        case .quit: .power
        }
    }

    /// The keys that do the same from a screen, as the menu bar and the controls guide write them.
    public var shortcut: String? {
        switch self {
        case .addGame: "⌘N"
        case .switchProfile: "⇧⌘P"
        case .changeView: "V"
        case .fullscreen: "⌃⌘F"
        case .zoomIn: "⌘+"
        case .zoomOut: "⌘−"
        case .actualSize: "⌘0"
        case .settings: "⌘,"
        case .controlCenter: "⇧⌘K"
        case .hide: "⌘H"
        case .quit: "⌘Q"
        default: nil
        }
    }

    public var itemID: String { "action:\(rawValue)" }

    public func item(in context: AppLocale = L10n.context, showsShortcut: Bool = true) -> PaletteItem {
        PaletteItem(id: itemID, kind: .action, title: L10n.text(key, context: context),
                    section: L10n.text(section.key, context: context), shortcut: showsShortcut ? shortcut : nil,
                    aliases: [L10n.text(key, context: AppLocale(language: .english, region: "US"))],
                    isRemembered: section != .power)
    }
}

/// The last palette choices of each player; a guest leaves none.
public struct PaletteRecentsStore {
    public static let key = "Oort.PaletteRecents"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppData.preferences) { self.defaults = defaults }

    public func load(for profile: UUID) -> [String] { all[profile.uuidString] ?? [] }

    /// Profiles outside `known` were removed: what they chose goes with them.
    public func save(_ recents: [String], for profile: UUID, known: Set<UUID>) {
        let kept = Set(known.map(\.uuidString))
        var next = all.filter { kept.contains($0.key) }
        next[profile.uuidString] = recents
        defaults.set(next, forKey: Self.key)
    }

    private var all: [String: [String]] { defaults.dictionary(forKey: Self.key) as? [String: [String]] ?? [:] }
}
