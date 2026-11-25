import Foundation

/// Visible navigation only. `SettingsSection` still owns routes, search rows and reset scope.
public enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general, appearance, sound, controllers
    case account, profilePage, multiplayer
    case home, library, `switch`, saves, cloudLibrary
    case integrations, storage, logs, about

    public var id: Self { self }

    public static let groups: [(heading: String?, categories: [Self])] = [
        (nil, [.general, .appearance, .sound, .controllers]),
        ("Settings navigation: Profile", [.account, .profilePage, .multiplayer]),
        ("Settings navigation: Games", [.home, .library, .switch, .saves, .cloudLibrary]),
        ("Oort", [.integrations, .storage, .logs, .about])
    ]

    public var sections: [SettingsSection] {
        switch self {
        case .general: [.startUp]
        case .appearance: [.look, .profileLook]
        case .sound: [.soundMusic]
        case .controllers: [.controllers, .navigation]
        case .account: [.profileIdentity, .profileSecurity, .profileNextendo]
        case .profilePage: [.profileCards]
        case .multiplayer: [.multiplayer]
        case .home: [.spotlight]
        case .library: [.libraryGames]
        case .switch: [.engine, .keys, .library, .games]
        case .saves: [.cloudSaves]
        case .cloudLibrary: [.cloudLibrary]
        case .integrations: [.sources, .apiServices]
        case .storage: [.storage, .portingStorage]
        case .logs: [.console]
        case .about: [.about]
        }
    }

    public init?(section: SettingsSection) {
        guard let category = Self.allCases.first(where: { $0.sections.contains(section) }) else { return nil }
        self = category
    }

    public var inlineSections: [SettingsSection] {
        switch self {
        case .appearance: [.profileLook]
        case .account: [.profileIdentity, .profileSecurity]
        case .switch: []
        case .storage: [.storage]
        default: sections
        }
    }

    public var subjects: [SettingsSection] { sections.filter { !inlineSections.contains($0) } }

    public func title(in context: AppLocale = L10n.context) -> String {
        L10n.text("Settings navigation: \(rawValue)", context: context)
    }

    public func title(for section: SettingsSection, in context: AppLocale = L10n.context) -> String {
        switch section {
        case .look: L10n.text("Advanced", context: context)
        case .engine, .games, .profileSecurity, .sources, .apiServices, .storage:
            L10n.text("Settings subject: \(section.rawValue)", context: context)
        default:
            section.title(in: context)
        }
    }
}
