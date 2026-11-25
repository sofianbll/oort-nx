import Foundation

/// Independent places for the public Nextendo player count.
public struct OnlinePlayersDisplay: Codable, Equatable, Sendable {
    public enum Place: String, CaseIterable, Sendable {
        case tile, selectedGame, details, gamePage

        public var id: String { "nextendoPlayers.\(rawValue)" }

        public var label: String {
            switch self {
            case .tile: "On covers"
            case .selectedGame: "On the selected game"
            case .details: "In Details"
            case .gamePage: "On the game page"
            }
        }

        fileprivate var key: WritableKeyPath<OnlinePlayersDisplay, Bool> {
            switch self {
            case .tile: \.tile
            case .selectedGame: \.selectedGame
            case .details: \.details
            case .gamePage: \.gamePage
            }
        }
    }

    private var tile: Bool
    private var selectedGame: Bool
    private var details: Bool
    private var gamePage: Bool

    public init(_ places: Set<Place> = [.tile, .selectedGame]) {
        tile = places.contains(.tile)
        selectedGame = places.contains(.selectedGame)
        details = places.contains(.details)
        gamePage = places.contains(.gamePage)
    }

    init(legacy: String?) {
        switch legacy {
        case "dot": self.init([.tile, .details])
        case "selectedGame": self.init([.selectedGame])
        case "gamePage": self.init([.details])
        case "never": self.init([])
        default: self.init()
        }
    }

    public subscript(_ place: Place) -> Bool {
        get { self[keyPath: place.key] }
        set { self[keyPath: place.key] = newValue }
    }

    public var asksService: Bool { Place.allCases.contains { self[$0] } }

    public func count(for titleID: String?, in counts: [String: Int], at place: Place) -> Int? {
        guard self[place], let titleID, let count = counts[titleID.lowercased()], count > 0 else { return nil }
        return count
    }

    public static func label(for count: Int, context: AppLocale) -> String {
        L10n.count("%lld Nextendo players", count, context: context)
    }
}
