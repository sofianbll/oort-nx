import Foundation

/// The keys of the notice on screen, reached on request only: the screen keeps its own focus underneath and takes it
/// back as it was.
public struct NoticeFocus: Equatable, Sendable {
    public private(set) var index: Int?
    private var count = 0

    public init() {}

    public var isActive: Bool { index != nil }

    public mutating func enter(keys: Int) {
        guard keys > 0 else { return leave() }
        count = keys
        index = 0
    }

    public mutating func move(by step: Int) {
        guard let index else { return }
        self.index = min(max(index + step, 0), count - 1)
    }

    public mutating func leave() { self = Self() }
}
