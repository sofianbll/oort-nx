import Foundation

/// What one refresh of the library read, part by part. A part that is off is not in it, so it is never asked.
public struct LibraryRefresh: Equatable, Sendable {
    public enum Part: Int, CaseIterable, Sendable {
        case apps, steam, cloud

        public var titleKey: String {
            switch self {
            case .apps: return "Game apps"
            case .steam: return "Steam"
            case .cloud: return "Cloud library"
            }
        }
    }

    public enum State: Equatable, Sendable {
        case reading, read, cancelled
        /// Why it is not up to date; what it showed before is kept.
        case stale(String)
    }

    public enum Outcome: Equatable, Sendable { case running, upToDate, changed(Int), incomplete, cancelled }

    public let id: UUID
    public private(set) var states: [Part: State]
    public private(set) var added = 0

    public init(id: UUID = UUID(), parts: Set<Part>) {
        self.id = id
        states = Dictionary(uniqueKeysWithValues: parts.map { ($0, .reading) })
    }

    public var isRunning: Bool { states.values.contains(.reading) }
    public var reading: [Part] { Part.allCases.filter { states[$0] == .reading } }

    /// The parts that are not up to date, in their order, with the reason.
    public var stale: [(part: Part, reason: String)] {
        Part.allCases.compactMap { part in
            if case .stale(let reason) = states[part] { return (part, reason) }
            return nil
        }
    }

    public var outcome: Outcome {
        if isRunning { return .running }
        if !stale.isEmpty { return .incomplete }
        if states.values.contains(.cancelled) { return .cancelled }
        return added > 0 ? .changed(added) : .upToDate
    }

    /// A part ends once; a late answer changes nothing.
    public mutating func end(_ part: Part, _ state: State) {
        guard states[part] == .reading, state != .reading else { return }
        states[part] = state
    }

    public mutating func noteAdded(_ count: Int) { added = max(added, count) }

    public mutating func cancel() {
        for part in reading { states[part] = .cancelled }
    }
}
