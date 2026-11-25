import Foundation

/// A game's total as another launcher keeps it, and when Arcane first saw that value.
public struct ExternalPlaytime: Equatable, Sendable {
    public let duration: TimeInterval
    public let lastPlayed: Date?
    public let since: Date

    public init(duration: TimeInterval, lastPlayed: Date?, since: Date) {
        self.duration = duration
        self.lastPlayed = lastPlayed
        self.since = since
    }
}

/// Play time folded out of the recent-session list for one game. `afterExternal` is the part of it after
/// the external value seen at `externalSince` (Steam's), which that value does not count yet.
public struct CarriedPlaytime: Codable, Equatable {
    public var duration: TimeInterval
    public var lastPlayed: Date
    public var externalSince: Date?
    public var afterExternal: TimeInterval

    public init(duration: TimeInterval, lastPlayed: Date, externalSince: Date? = nil, afterExternal: TimeInterval = 0) {
        self.duration = duration
        self.lastPlayed = lastPlayed
        self.externalSince = externalSince
        self.afterExternal = afterExternal
    }

    private enum CodingKeys: String, CodingKey { case duration, lastPlayed, externalSince, afterExternal }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        lastPlayed = try c.decode(Date.self, forKey: .lastPlayed)
        externalSince = try c.decodeIfPresent(Date.self, forKey: .externalSince)
        afterExternal = try c.decodeIfPresent(TimeInterval.self, forKey: .afterExternal) ?? 0
    }
}
