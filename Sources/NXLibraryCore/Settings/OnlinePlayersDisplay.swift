import Foundation

/// Where Nextendo's count of online players shows: the one setting every such count follows.
public enum OnlinePlayersDisplay: String, Codable, CaseIterable, Sendable {
    case dot, selectedGame, gamePage, never

    public enum Place: CaseIterable, Sendable {
        /// A game's cover, which shows a dot without the number.
        case tile
        /// The information line under or above the selected game, in Spotlight and Collection.
        case selectedGame
        /// The Players row of a game's details.
        case gamePage
    }

    public var label: String {
        switch self {
        case .dot: "Dot"
        case .selectedGame: "On selected game"
        case .gamePage: "Game page only"
        case .never: "Never"
        }
    }

    /// Never shows nothing and also sends no request for these numbers.
    public var asksService: Bool { self != .never }

    /// The count to show for a title in a place; nil when this choice shows none there or nobody is online.
    public func count(for titleID: String?, in counts: [String: Int], at place: Place) -> Int? {
        let shows = switch self {
        case .dot: place != .selectedGame
        case .selectedGame: place == .selectedGame
        case .gamePage: place == .gamePage
        case .never: false
        }
        guard shows, let titleID, let count = counts[titleID.lowercased()], count > 0 else { return nil }
        return count
    }
}

extension [DetailsFact] {
    /// The count joins the Players fact, or makes it in its place when the store gives no number of players.
    public func addingOnlinePlayers(_ count: Int?, context: AppLocale = L10n.context) -> [DetailsFact] {
        guard let count else { return self }
        var values: [DetailsFact.Kind: String?] = Dictionary(uniqueKeysWithValues: map { ($0.kind, $0.value) })
        let online = L10n.count("%lld online", count, context: context)
        values[.players] = [values[.players] ?? nil, online].compactMap { $0 }.joined(separator: " · ")
        return DetailsFacts.rows(values)
    }
}
