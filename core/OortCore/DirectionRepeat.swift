import Foundation

public enum ControllerDirection: CaseIterable, Hashable { case up, down, left, right }

/// A held direction moves once, waits, then repeats, a little faster after a while. The D-pad and both sticks share
/// it; the last one pressed leads. Time is supplied by the caller.
public struct DirectionRepeat {
    public enum Source: Hashable { case pad, leftStick, rightStick }

    public static let firstDelay: TimeInterval = 0.36
    public static let interval: TimeInterval = 0.12
    public static let fastInterval: TimeInterval = 0.07
    static let fastAfter = 8

    private var held: [(source: Source, direction: ControllerDirection)] = []
    private var count = 0

    public init() {}

    public var current: ControllerDirection? { held.last?.direction }

    /// The delay before the next repeat of what is held now.
    public var nextDelay: TimeInterval {
        if held.last?.source == .rightStick { return count == 0 ? Self.interval * 1.5 : Self.fastInterval }
        return count == 0 ? Self.firstDelay : count < Self.fastAfter ? Self.interval : Self.fastInterval
    }

    /// True when this is a new direction: move now.
    public mutating func press(_ direction: ControllerDirection, from source: Source) -> Bool {
        guard !held.contains(where: { $0.source == source && $0.direction == direction }) else { return false }
        held.append((source, direction))
        count = 0
        return true
    }

    public mutating func release(_ direction: ControllerDirection, from source: Source) {
        held.removeAll { $0.source == source && $0.direction == direction }
        count = 0
    }

    /// A stick is in one direction or none. A little slack keeps a stick resting on its threshold from chattering.
    public mutating func stick(_ value: SIMD2<Float>, deadzone: Float, from source: Source) -> ControllerDirection? {
        let was = held.last { $0.source == source }?.direction
        func pull(_ direction: ControllerDirection) -> Float {
            switch direction {
            case .up: value.y
            case .down: -value.y
            case .left: -value.x
            case .right: value.x
            }
        }
        if let was, pull(was) > deadzone * 0.8, pull(was) >= ControllerDirection.allCases.map(pull).max()! * 0.8 { return nil }
        if let was { release(was, from: source) }
        guard let next = ControllerDirection.allCases.max(by: { pull($0) < pull($1) }), pull(next) > deadzone,
              source != .rightStick || next == .up || next == .down else { return nil }
        return press(next, from: source) ? next : nil
    }

    public mutating func tick() -> ControllerDirection? {
        guard let current else { return nil }
        count += 1
        return current
    }

    public mutating func reset() {
        held.removeAll()
        count = 0
    }
}
