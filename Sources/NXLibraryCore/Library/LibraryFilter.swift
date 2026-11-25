import Foundation

public protocol PlayHistory {
    func lastPlayed(for gameID: UUID) -> Date?
    func totalDuration(for gameID: UUID) -> TimeInterval
}

public extension PlayHistory {
    func totalDuration(for gameID: UUID) -> TimeInterval { 0 }
}

public struct NoPlayHistory: PlayHistory {
    public init() {}
    public func lastPlayed(for gameID: UUID) -> Date? { nil }
}

/// The tabs above the games, in the order they show: where the games are, then the player's own choices.
public enum LibraryFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all = "All games"
    case installed = "Installed"
    case cloud = "Cloud"
    case favorites = "Favorites"
    case recentlyPlayed = "Recently played"
    case notPlayed = "Not played yet"

    public var id: String { rawValue }

    /// Recently played is also a sort, and Not played yet also a filter: both stay one setting away.
    public static let defaultTabs: [LibraryFilter] = [.all, .installed, .cloud, .favorites]

    /// Each tab once, in the chosen order, with All games always there.
    public static func tabs(_ chosen: [LibraryFilter]) -> [LibraryFilter] {
        (chosen.contains(.all) ? chosen : [.all] + chosen).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}

/// Narrows any tab by play history.
public enum LibraryPlayed: String, CaseIterable, Sendable {
    case any = "All games"
    case notPlayed = "Not played yet"
    case played = "Already played"
}

/// A row of the Sort and filter panel.
public enum LibraryMenuItem: Hashable, Sendable {
    case sort(LibrarySort), played(LibraryPlayed)

    public static let all = LibrarySort.allCases.map(Self.sort) + LibraryPlayed.allCases.map(Self.played)

    public var title: String {
        switch self {
        case .sort(let sort): sort.title
        case .played(let played): played.rawValue
        }
    }
}

public enum LibrarySort: String, Codable, CaseIterable, Sendable {
    case recent, name, added, playtime

    public var title: String {
        switch self {
        case .recent: return "Sort: Recent"
        case .name: return "Sort: Name"
        case .added: return "Sort: Recently added"
        case .playtime: return "Sort: Playtime"
        }
    }
}

public struct LibraryQuery: Equatable {
    public var filter: LibraryFilter
    public var searchText: String
    public var sort: LibrarySort
    public var played: LibraryPlayed

    public init(filter: LibraryFilter = .all, searchText: String = "", sort: LibrarySort = .recent,
                played: LibraryPlayed = .any) {
        self.filter = filter
        self.searchText = searchText
        self.sort = sort
        self.played = played
    }

    public func applyCatalog(to games: [CatalogGame], history: PlayHistory, cloudOnly: Set<UUID> = []) -> [CatalogGame] {
        applyRecords(games, history: history, cloudOnly: cloudOnly)
    }

    package func applyRecords<Game: LibraryQueryRecord>(_ games: [Game], history: PlayHistory,
                                                       cloudOnly: Set<UUID> = []) -> [Game] {
        let visible = games.filter { !$0.isHidden }
        let needsHistory = sort == .recent || filter == .recentlyPlayed || filter == .notPlayed || played != .any
        let dates = needsHistory ? Dictionary(uniqueKeysWithValues: visible.map { ($0.id, history.lastPlayed(for: $0.id)) }) : [:]
        func lastPlayed(_ game: Game) -> Date? { dates[game.id] ?? nil }

        var filtered: [Game]
        switch filter {
        case .all: filtered = visible
        case .installed: filtered = visible.filter(\.isInstalledForLibrary)
        case .recentlyPlayed: filtered = visible.filter { lastPlayed($0) != nil }
        case .favorites: filtered = visible.filter(\.isFavorite)
        case .notPlayed: filtered = visible.filter { lastPlayed($0) == nil }
        case .cloud: filtered = visible.filter { cloudOnly.contains($0.id) }
        }
        if played != .any { filtered = filtered.filter { (lastPlayed($0) == nil) == (played == .notPlayed) } }

        let query = normalized(searchText)
        let searched = query.isEmpty ? filtered : filtered.filter { game in
            normalized(game.name).contains(query)
                || game.librarySearchTerms.contains { normalized($0).contains(query) }
        }

        func byName(_ lhs: Game, _ rhs: Game) -> Bool {
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        // Compute each sort value once, especially the aggregates from play history.
        func descending<Value: Comparable>(by value: (Game) -> Value?) -> [Game] {
            searched.map { (game: $0, value: value($0)) }.sorted { lhs, rhs in
                switch (lhs.value, rhs.value) {
                case let (l?, r?) where l != r: return l > r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return byName(lhs.game, rhs.game)
                }
            }.map(\.game)
        }
        switch sort {
        case .recent: return descending(by: lastPlayed)
        case .name: return searched.sorted(by: byName)
        case .added: return descending { $0.libraryModificationDate }
        case .playtime: return descending { history.totalDuration(for: $0.id) }
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive],
                      locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// What the library's filter, search and Surprise read from a game of any source.
package protocol LibraryQueryRecord {
    var id: UUID { get }
    var name: String { get }
    var isFavorite: Bool { get }
    var isHidden: Bool { get }
    var isInstalledForLibrary: Bool { get }
    var librarySearchTerms: [String] { get }
    var libraryModificationDate: Date? { get }
}
extension CatalogGame: LibraryQueryRecord {
    package var isInstalledForLibrary: Bool { record.isInstalledForLibrary }
    package var librarySearchTerms: [String] { record.librarySearchTerms }
    package var libraryModificationDate: Date? { record.libraryModificationDate }
}
