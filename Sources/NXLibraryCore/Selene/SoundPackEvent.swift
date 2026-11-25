import Foundation

public enum SoundPackEvent: String, CaseIterable, Sendable {
    case move, select, confirm, back, deny, open, close, play, resume, success, notification, boot, ambience

    public var legacyCue: SoundCue? {
        switch self {
        case .move: return .move
        case .select: return .select
        case .confirm: return .key
        case .back, .close: return .back
        case .deny, .notification: return .alert
        case .open: return .openPanel
        case .play: return .gameStarting
        case .success: return .success
        case .boot: return .boot
        case .resume, .ambience: return nil
        }
    }
}
