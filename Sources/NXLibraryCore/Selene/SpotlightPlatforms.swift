import Foundation

/// The platform choices come from the visible catalog, not from the current top filter.
public struct SpotlightPlatforms: Equatable {
    public struct Card: Equatable {
        /// nil is All.
        public let integration: CatalogIntegration?
        public let count: Int
    }

    public let cards: [Card]

    /// `listedGames` is the projection of the active sources, before applying the library query.
    /// Records unknown to this reader are preserved by CatalogDocument, outside that projection.
    public init(listedGames: [CatalogGame], preferredOrder: [CatalogIntegration]) {
        var counts: [CatalogIntegration: Int] = [:]
        for game in listedGames where !game.isHidden { counts[game.integration, default: 0] += 1 }
        let total = counts.values.reduce(0, +)
        var ordered = preferredOrder.compactMap { integration in
            counts.removeValue(forKey: integration).map { Card(integration: integration, count: $0) }
        }
        ordered += counts.keys.sorted { $0.rawValue < $1.rawValue }.map { Card(integration: $0, count: counts[$0]!) }
        cards = [Card(integration: nil, count: total)] + ordered
    }

    public func card(for requested: CatalogIntegration?) -> Card {
        cards.first { $0.integration == requested } ?? cards[0]
    }

    /// Scope an already-filtered and sorted result without disturbing its order.
    public func games(_ queried: [CatalogGame], on requested: CatalogIntegration?) -> [CatalogGame] {
        guard let integration = card(for: requested).integration else { return queried }
        return queried.filter { $0.integration == integration }
    }

    public func adjacent(to requested: CatalogIntegration?, by direction: Int) -> Card {
        let index = cards.firstIndex { $0.integration == requested } ?? 0
        return cards[min(max(index + direction.signum(), 0), cards.count - 1)]
    }
}

/// The cursor moves immediately; the row's artwork still belongs to the last settled choice.
public struct SpotlightPlatformPicker: Equatable {
    public private(set) var cursor: CatalogIntegration?
    public private(set) var settled: CatalogIntegration?

    public init(_ saved: CatalogIntegration?, in platforms: SpotlightPlatforms) {
        cursor = platforms.card(for: saved).integration
        settled = cursor
    }

    @discardableResult
    public mutating func move(by direction: Int, in platforms: SpotlightPlatforms) -> Bool {
        let next = platforms.adjacent(to: cursor, by: direction).integration
        guard next != cursor else { return false }
        cursor = next
        return true
    }

    public mutating func reconcile(in platforms: SpotlightPlatforms) {
        cursor = platforms.card(for: cursor).integration
        settled = platforms.card(for: settled).integration
    }

    public mutating func settle() { settled = cursor }
}
