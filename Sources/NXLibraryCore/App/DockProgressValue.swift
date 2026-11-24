import Foundation

/// The one fraction the Dock icon shows for all the work running at once.
public enum DockProgressValue {
    /// The mean of the running works whose size is known, in whole percents (the Dock tile is redrawn only when it
    /// changes); nil hides the bar: nothing runs, or nothing running can say how far it is.
    public static func percent(_ fractions: [Double?]) -> Int? {
        let known = fractions.compactMap { $0 }.filter(\.isFinite).map { min(1, max(0, $0)) }
        guard !known.isEmpty else { return nil }
        return Int((known.reduce(0, +) / Double(known.count) * 100).rounded(.down))
    }
}
