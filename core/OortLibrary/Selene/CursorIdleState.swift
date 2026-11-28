import Foundation

/// Idle policy only; the shell owns AppKit cursor effects and window eligibility.
public struct CursorIdleState {
    public private(set) var isHidden = false
    private var idleSince: TimeInterval?
    /// A controller was picked up: the pointer stays away until it moves, in a window too.
    private var heldByController = false
    private var lastPointerPosition: CGPoint?
    public init() {}
    /// `fullscreen` is where an idle pointer hides by itself.
    public mutating func update(now: TimeInterval, eligible: Bool, fullscreen: Bool = true) -> Bool {
        guard eligible else {
            idleSince = nil
            heldByController = false
            isHidden = false
            return false
        }
        if idleSince == nil || !fullscreen { idleSince = now }
        isHidden = heldByController || now - (idleSince ?? now) >= 3
        return isHidden
    }
    public mutating func controllerUsed() { heldByController = true }
    public mutating func mouseActivity(now: TimeInterval) {
        idleSince = now
        heldByController = false
        isHidden = false
    }

    /// Native menu/control tracking can consume mouse events before a local monitor sees them.
    public mutating func observePointer(at position: CGPoint, now: TimeInterval) -> Bool {
        let previous = lastPointerPosition
        lastPointerPosition = position
        // By coordinates: CGPoint is Equatable only through CoreGraphics on a Mac, which the core does not import.
        guard let previous, previous.x != position.x || previous.y != position.y else { return false }
        mouseActivity(now: now)
        return true
    }
}
