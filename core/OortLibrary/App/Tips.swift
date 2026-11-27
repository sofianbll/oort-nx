import Foundation

/// A shortcut told once, when it would have helped.
public enum Tip: String, CaseIterable {
    /// A library too long to browse.
    case search
    /// The same choices made again for a second game.
    case copySettings

    public var message: String {
        switch self {
        case .search: return "Find a game by its name"
        case .copySettings: return "Copy these settings to another game"
        }
    }

    public var detail: String {
        switch self {
        case .search: return "Search opens from anywhere in your library."
        case .copySettings: return "In Options, All settings, General."
        }
    }
}

/// Each tip is shown once on this Mac, one at a time and one per session, and never when tips are off.
public final class Tips: ObservableObject {
    static let storageKey = "NXLibrary_TipsSeen"
    public static let longLibrary = 12

    @Published public private(set) var shown: Tip?
    private let defaults: UserDefaults
    private var shownThisSession = false
    private var changedGames: Set<UUID> = []

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func libraryAppeared(games: Int, enabled: Bool) {
        if games >= Self.longLibrary { offer(.search, enabled: enabled) }
    }

    /// A choice was saved for a game; the second game in a session is when copying would have helped.
    public func settingChanged(for game: UUID, enabled: Bool) {
        changedGames.insert(game)
        if changedGames.count > 1 { offer(.copySettings, enabled: enabled) }
    }

    public func dismiss() { shown = nil }

    private func offer(_ tip: Tip, enabled: Bool) {
        var seen = defaults.stringArray(forKey: Self.storageKey) ?? []
        guard enabled, !shownThisSession, !seen.contains(tip.rawValue) else { return }
        seen.append(tip.rawValue)
        defaults.set(seen, forKey: Self.storageKey)
        shownThisSession = true
        shown = tip
    }
}
