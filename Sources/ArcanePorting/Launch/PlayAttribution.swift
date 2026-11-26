import Foundation

/// The host supplies snapshots of the exact native target, not a bundle ID match.
struct PlayAttribution {
    let startedAt: Date
    let before: Set<Int32>

    func accepts(pid: Int32, born: Date?, after: Set<Int32>, belongsToGesture: Bool) -> Bool {
        guard belongsToGesture, let born, born > startedAt else { return false }
        return after.subtracting(before) == [pid]
    }
}
