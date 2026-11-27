import Foundation
import OortLibrary

/// Projection of confirmed cloud events, independent of the screen displaying them.
public enum CloudTransferPresentation: Equatable {
    case queued, running(Double?), verifying(Double?), waitingForGame, ready, failed

    public init(progress: CloudArchiveProgress?, queued: Bool) {
        if queued { self = .queued; return }
        switch progress?.phase {
        case .verifying, .restoring:
            self = .verifying(progress?.downloadComplete == true ? 1 : Self.fraction(progress))
        case .readyToInstall: self = .waitingForGame
        case .uploading, .downloading: self = .running(Self.fraction(progress))
        default: self = .running(nil)
        }
    }

    public var titleKey: String {
        switch self {
        case .queued: "Queued"
        case .running: "In progress"
        case .verifying: "Verifying"
        case .waitingForGame: "Update ready · applied when you quit the game"
        case .ready: "Ready"
        case .failed: "Cloud operation failed"
        }
    }

    public enum Gauge: Equatable { case cover, download, bar, none }

    public func gauge(hasCover: Bool, hasDownloadPill: Bool) -> Gauge {
        switch self {
        case .queued, .ready, .failed: return .none
        case .waitingForGame, .verifying:
            return .none
        case .running(let fraction):
            if hasCover { return .cover }
            return hasDownloadPill && fraction != nil ? .download : .bar
        }
    }

    public var coverFraction: Double {
        switch self {
        case .running(let fraction): fraction ?? 0
        case .verifying(let fraction): fraction ?? 0
        case .waitingForGame, .ready: 1
        default: 0
        }
    }

    public var canCancel: Bool {
        switch self {
        case .ready, .failed: false
        default: true
        }
    }

    public static func fraction(_ progress: CloudArchiveProgress?) -> Double? {
        guard let transfer = progress?.transfer, transfer.totalBytes > 0 else { return nil }
        return min(1, max(0, Double(transfer.bytesTransferred) / Double(transfer.totalBytes)))
    }
}

public enum CloudGameManagementPlacement: Equatable {
    case primaryActions, detailsLink

    public init?(nextToPlay: Bool, detailsLink: Bool, cloudEnabled: Bool = true) {
        if nextToPlay { self = .primaryActions }
        else if detailsLink || cloudEnabled { self = .detailsLink }
        else { return nil }
    }
}
