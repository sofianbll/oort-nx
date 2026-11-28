import Foundation
import OortLibrary

public struct BuildRecord: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date?
    public var exitCode: Int32?
    public var logPath: String?
    public var outputPath: String?
    public var engineCommit: String?
    public var metalVersion: String?
    public var xcodeVersion: String?
    public var toolchainVerified: Bool
    public var nextendoRequested: Bool?
    /// Engine switch names for this build, never the current mod selection.
    public var builtCodeMods: [String]?
    public var cancelled: Bool

    public init(startedAt: Date = Date(), endedAt: Date? = nil,
                exitCode: Int32? = nil, logPath: String? = nil,
                outputPath: String? = nil, engineCommit: String? = nil,
                metalVersion: String? = nil, xcodeVersion: String? = nil,
                toolchainVerified: Bool = false, nextendoRequested: Bool? = nil,
                builtCodeMods: [String]? = nil, cancelled: Bool = false) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exitCode = exitCode
        self.logPath = logPath
        self.outputPath = outputPath
        self.engineCommit = engineCommit
        self.metalVersion = metalVersion
        self.xcodeVersion = xcodeVersion
        self.toolchainVerified = toolchainVerified
        self.nextendoRequested = nextendoRequested
        self.builtCodeMods = builtCodeMods
        self.cancelled = cancelled
    }

    package static func recentGames(in games: [PortedGame]) -> [(game: PortedGame, date: Date)] {
        games.compactMap { game -> (game: PortedGame, date: Date)? in
            guard !game.isHidden else { return nil }
            let date = [game.lastBuild, game.pendingInstall?.record].compactMap { record -> Date? in
                guard let record, record.exitCode == 0, !record.cancelled,
                      let end = record.endedAt, end >= record.startedAt else { return nil }
                return end
            }.max()
            return date.map { (game, $0) }
        }.sorted { $0.date > $1.date }
    }
}
