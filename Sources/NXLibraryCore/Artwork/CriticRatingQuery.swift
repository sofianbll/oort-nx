import Foundation

/// Public lookup identity only. Never sends catalog paths, account IDs or play history.
public struct CriticRatingQuery: Hashable, Codable, Sendable {
    public enum Platform: String, Codable, Sendable {
        case mac, `switch`, switch2
        var wikidataID: String {
            switch self {
            case .mac: return "Q14116"
            case .switch: return "Q19610114"
            case .switch2: return "Q122761124"
            }
        }
        var igdbID: Int {
            switch self {
            case .mac: return 14
            case .switch: return 130
            case .switch2: return 508
            }
        }
    }
    public let name: String
    public let platform: Platform
    public let steamAppID: UInt32?

    public init(name: String, platform: Platform, steamAppID: UInt32? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.platform = platform
        self.steamAppID = steamAppID
    }
}
