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

public enum LibraryFilter: String, CaseIterable, Identifiable, Equatable {
    case all = "All games"
    case installed = "Installed"
    case recentlyPlayed = "Recently played"
    case favorites = "Favorites"
    case notPlayed = "Not played yet"
    case cloud = "Cloud"

    public var id: String { rawValue }
}

public enum LibrarySort: String, Codable, CaseIterable {
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

    public init(filter: LibraryFilter = .all, searchText: String = "", sort: LibrarySort = .recent) {
        self.filter = filter
        self.searchText = searchText
        self.sort = sort
    }

    public func applyCatalog(to games: [CatalogGame], history: PlayHistory, cloudOnly: Set<UUID> = []) -> [CatalogGame] {
        applyRecords(games, history: history, cloudOnly: cloudOnly)
    }

    package func applyRecords<Game: LibraryQueryRecord>(_ games: [Game], history: PlayHistory,
                                                       cloudOnly: Set<UUID> = []) -> [Game] {
        let visible = games.filter { !$0.isHidden }
        let needsHistory = sort == .recent || filter == .recentlyPlayed || filter == .notPlayed
        let dates = needsHistory ? Dictionary(uniqueKeysWithValues: visible.map { ($0.id, history.lastPlayed(for: $0.id)) }) : [:]
        func played(_ game: Game) -> Date? { dates[game.id] ?? nil }

        let filtered: [Game]
        switch filter {
        case .all: filtered = visible
        case .installed: filtered = visible.filter(\.isInstalledForLibrary)
        case .recentlyPlayed: filtered = visible.filter { played($0) != nil }
        case .favorites: filtered = visible.filter(\.isFavorite)
        case .notPlayed: filtered = visible.filter { played($0) == nil }
        case .cloud: filtered = visible.filter { cloudOnly.contains($0.id) }
        }

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
        case .recent: return descending(by: played)
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
