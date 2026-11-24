import Foundation

/// A catalog game (including its source) and the one usable installation, if unambiguous.
/// A missing installation is still a target: the existing Play path may explain or repair it.
public struct PlayTarget {
    public let game: CatalogGame
    public let installation: CatalogInstallationPresentation?
    public let installationAvailability: PlayAvailability

    public init(game: CatalogGame, sourceEnabled: Bool) {
        self.game = game
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

public struct PlayProfile: Equatable, Sendable {
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

public enum PlayRefusal: Equatable, Sendable {
    case missingTarget, unsupportedSource, sourceDisabled, installationMissing, installationNeedsReview
    case profileLocked, guestUnsupported, launchInProgress
    case confirmationRequired, savesUnavailable, invalidGame
    case launcherMissing, handoffRejected, notStarted, preparationFailed, openFailed
}

public enum PlayAvailability: Equatable, Sendable {
    case available
    case unavailable(PlayRefusal)
}

public enum PlayAcceptance: Equatable, Sendable {
    /// Preparing a request is not evidence of handing it off or opening a game.
    case pending
    case handedOff
    case gameOpened
}

public enum PlayResult: Equatable, Sendable {
    case accepted(PlayAcceptance)
    case refused(PlayRefusal)
}

/// Further outcomes only when observed by the connector. A cover fading out is not readiness.
public enum PlayEvent: Equatable, Sendable {
    case result(PlayResult)
    case ready
    case exited
}

public typealias PlayObserver = @MainActor (PlayEvent) -> Void

@MainActor public protocol PlayConnector {
    var source: CatalogIntegration { get }
    /// Availability of a fresh launch; not a replacement for the connector's final checks.
    func availability(of target: PlayTarget) -> PlayAvailability
    func play(_ target: PlayTarget, profile: PlayProfile, observe: PlayObserver?) -> PlayResult
}

@MainActor public struct GamePlay {
    private let connectors: [any PlayConnector]

    public init(_ connectors: [any PlayConnector]) { self.connectors = connectors }

    public func supports(_ source: CatalogIntegration) -> Bool { connector(for: source) != nil }

    public func availability(of target: PlayTarget?) -> PlayAvailability {
        guard let target else { return .unavailable(.missingTarget) }
        guard let connector = connector(for: target.game.integration) else { return .unavailable(.unsupportedSource) }
        return connector.availability(of: target)
    }

    public func play(_ target: PlayTarget?, profile: PlayProfile, observe: PlayObserver? = nil) -> PlayResult {
        guard let target else { return .refused(.missingTarget) }
        guard let connector = connector(for: target.game.integration) else { return .refused(.unsupportedSource) }
        // The connector owns legacy refusal feedback and may have a resume or deferred launch to handle.
        return connector.play(target, profile: profile, observe: observe)
    }

    private func connector(for source: CatalogIntegration) -> (any PlayConnector)? {
        connectors.first { $0.source == source }
    }
}
