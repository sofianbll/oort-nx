import Foundation

/// A row of games under the wheel or two fingers: how many tiles one event moves the selection.
/// Fingers move the row with them, one tile per tile of travel; a wheel moves one tile per notch.
public struct RailScroll: Equatable, Sendable {
    private var travel = 0.0
    private var last: TimeInterval?

    /// Travel left by an older gesture is dropped.
    /// Travel that turns one screenshot, in canvas units.
    public static let page = 400.0
    static let gesturePause: TimeInterval = 0.3

    public init() {}

    /// The delta a row follows: sideways, or also up and down on a screen that has nothing else to scroll.
    /// Nil when the event belongs to something else.
    public static func delta(x: Double, y: Double, verticalToo: Bool) -> Double? {
        if abs(x) > abs(y) { return x }
        return verticalToo && y != 0 ? y : nil
    }

    /// Positive steps move right. `delta` is the scrolling delta, so content dragged left asks for the next tile.
    public mutating func steps(_ delta: Double, precise: Bool, began: Bool, pitch: Double, at now: TimeInterval) -> Int {
        guard delta != 0 else { return 0 }
        if let last, now - last > Self.gesturePause { travel = 0 }
        last = now
        guard precise else {
            travel = 0
            return delta < 0 ? 1 : -1
        }
        // A new touch, or fingers turning back, starts from here.
        if began || (travel != 0 && (travel < 0) != (delta < 0)) { travel = 0 }
        travel += delta
        let moved = (travel / max(pitch, 1)).rounded(.towardZero)
        travel -= moved * max(pitch, 1)
        return -Int(moved)
    }
}
