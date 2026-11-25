import Foundation

public enum MacExecutableArchitecture: String, Hashable, Codable, Sendable { case arm64, x86_64 }

public enum NativeMacApplicationError: Error, Equatable {
    case invalidBundle, unsafePath, invalidExecutable, metadataTooLarge
}

/// Evidence about an installed app, independent of Steam and of any launch operation.
public struct NativeMacApplication: Equatable, Sendable {
    public let url: URL
    public let executableURL: URL
    public let bundleIdentifier: String?
    public let name: String
    public let architectures: Set<MacExecutableArchitecture>
    public let isDeclaredGame: Bool
    let fileObservations: [InstallationFileObservation]

    static func isWithin(_ url: URL, root: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
    }

    static let gameCategories: Set<String> = Set([
        "games", "action-games", "adventure-games", "arcade-games", "board-games", "card-games",
        "casino-games", "dice-games", "educational-games", "family-games", "kids-games", "music-games",
        "puzzle-games", "racing-games", "role-playing-games", "simulation-games", "sports-games",
        "strategy-games", "trivia-games", "word-games"
    ].map { "public.app-category." + $0 })
}
