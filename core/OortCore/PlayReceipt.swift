import Foundation

public enum PlayRefusal: Equatable, Codable, Sendable {
    case missingTarget, unsupportedSource, sourceDisabled, installationMissing, installationNeedsReview
    case profileLocked, guestUnsupported, launchInProgress
    case confirmationRequired, savesUnavailable, invalidGame
    case launcherMissing, handoffRejected, notStarted, preparationFailed, openFailed
    case stale, outcomeUnknown
}

public enum PlayAcceptance: Equatable, Codable, Sendable {
    case pending
    case handedOff
    case gameOpened
}

public enum PlayResult: Equatable, Codable, Sendable {
    case accepted(PlayAcceptance)
    case refused(PlayRefusal)
}

/// An admission belongs to one gesture. Joining an existing app does not attest a play session.
public struct PlayReceipt: Equatable, Sendable {
    public let request: RequestID
    public let admission: PlayResult
    public let run: RunRef?

    package init(_ request: RequestID, _ admission: PlayResult, run: RunRef? = nil) {
        self.request = request
        self.admission = admission
        self.run = run
    }
}

public enum PlayEvent: Equatable, Codable, Sendable {
    case result(PlayResult)
    case ready
    case readinessTimedOut
    case receiptUnavailable
    case exited
}

public enum RunRole {}
public typealias RunRef = Ref<RunRole>

public struct PlayFact: Equatable, Codable, Sendable {
    public let sequence: Int
    public let observedAt: Date
    public let event: PlayEvent
    private let runID: UUID?
    public var run: RunRef? { runID.map(RunRef.init) }

    package init(sequence: Int, event: PlayEvent, run: RunRef?) {
        self.sequence = sequence
        self.observedAt = .now
        self.event = event
        self.runID = run?.id
    }
}

public typealias PlayObserver = @MainActor (PlayEvent) -> Void
package typealias PlayFactObserver = @MainActor (PlayFact) -> Void
