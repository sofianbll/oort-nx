import Foundation

/// What the player last used: it decides whether the prompts name controller buttons or keys.
/// Only a deliberate act counts, so prompts never flicker: a stick inside its dead zone, a nudged table or the
/// small hover macOS reports under a still pointer changes nothing.
public struct InputInHand: Equatable, Sendable {
    public enum Device: Equatable, Sendable { case controller, keyboard, pointer }

    /// Nil until the first act: a connected controller then leads, as at a launch from the sofa.
    public private(set) var device: Device?
    private var travel = 0.0
    private var lastMove: TimeInterval?
    private var lastPress: TimeInterval?

    /// How far the pointer travels in one gesture before it counts, in points.
    static let deliberateTravel = 24.0
    /// Moves further apart than this start a new gesture.
    static let gesturePause: TimeInterval = 0.25
    /// A controller press ignores the pointer this long: the hand that just set it down still brushes the mouse.
    static let pressGuard: TimeInterval = 0.4

    public init() {}

    public func usesController(connected: Bool) -> Bool { connected && (device ?? .controller) == .controller }

    public mutating func controllerUsed(at now: TimeInterval) {
        use(.controller)
        lastPress = now
    }

    public mutating func keyPressed() { use(.keyboard) }

    /// A click or a scroll is always deliberate.
    public mutating func pointerUsed() { use(.pointer) }

    public mutating func pointerMoved(by distance: Double, at now: TimeInterval) {
        if let lastMove, now - lastMove > Self.gesturePause { travel = 0 }
        lastMove = now
        guard device != .pointer else { return }
        if let lastPress, now - lastPress < Self.pressGuard { return travel = 0 }
        travel += distance
        if travel >= Self.deliberateTravel { use(.pointer) }
    }

    private mutating func use(_ next: Device) {
        device = next
        travel = 0
    }
}
