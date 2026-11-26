import Foundation

/// A catalog game (including its source) and the one usable installation, if unambiguous.
/// A missing installation is still a target: the existing Play path may explain or repair it.
public struct PlayTarget {
    public let game: CatalogGame
    public let installation: CatalogInstallationPresentation?
    public let installationAvailability: PlayAvailability
    package let resumeOnly: Bool

    public init(game: CatalogGame, sourceEnabled: Bool, resumeOnly: Bool = false) {
        self.game = game
        self.resumeOnly = resumeOnly
        let presence = game.record.presence(sourceEnabled: sourceEnabled)
        let available = presence.installations.filter { $0.availability == .available }
        if !sourceEnabled {
            installationAvailability = .unavailable(.sourceDisabled)
        } else if available.count > 1 || (presence.requiresReview && !available.isEmpty)
                    || presence.installations.contains(where: { $0.availability == .requiresReview }) {
            installationAvailability = .unavailable(.installationNeedsReview)
        } else if available.isEmpty {
            installationAvailability = .unavailable(.installationMissing)
        } else {
            installationAvailability = .available
        }
        installation = installationAvailability == .available ? available.first : nil
    }
}

public struct PlayProfile: Equatable, Codable, Sendable {
    public let id: UUID?
    public let isGuest: Bool
    /// The profile picker or unlock flow still owns input.
    public let blocksPlay: Bool

    public init(id: UUID?, isGuest: Bool, blocksPlay: Bool) {
        self.id = id
        self.isGuest = isGuest
        self.blocksPlay = blocksPlay
    }
}

public enum PlayAvailability: Equatable, Codable, Sendable {
    case available
    case unavailable(PlayRefusal)
}
