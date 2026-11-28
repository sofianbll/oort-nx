public struct CloudSetupAssistantFocus {
    /// The two folders a player gives to Oort.
    public enum Folder: Hashable, Sendable { case library, sources }

    public enum Target: Hashable {
        case step(Int)
        case haveClient, helpCreate, link(Int), guide, client, secret, retry
        case change(Folder), accept(Folder), swap, keep
        case breadcrumb(String), folder(String), recent(String), newFolder, folderName, refresh
        case enterPath, typedPath
        case moveGames, confirmMove, cancel, primary, create
    }

    public enum Direction { case left, right, up, down }

    private var selection: Target?

    public init() {}
    public mutating func reset() { selection = nil }
    public mutating func select(_ target: Target) { selection = target }
    public mutating func retainSelection(in rows: [[Target]], rail: [Target] = []) {
        if let selection, !rail.contains(selection), !rows.contains(where: { $0.contains(selection) }) { reset() }
    }

    /// `rail` is the column of steps on the left: Left enters it, Right leaves it. With nothing chosen yet, `initial` is
    /// lit, then the first useful target: never the way back while there is something to do.
    public func current(in rows: [[Target]], rail: [Target] = [], initial: Target? = .primary) -> Target {
        let targets = rows.flatMap { $0 }
        if let selection, targets.contains(selection) || rail.contains(selection) { return selection }
        if let initial, targets.contains(initial) { return initial }
        return targets.first { $0 != .cancel } ?? .cancel
    }

    public mutating func move(_ direction: Direction, in rows: [[Target]], rail: [Target] = [], initial: Target? = .primary) {
        let rows = rows.filter { !$0.isEmpty }
        let target = current(in: rows, rail: rail, initial: initial)
        if let step = rail.firstIndex(of: target) {
            switch direction {
            case .up: selection = rail[max(0, step - 1)]
            case .down: selection = rail[min(rail.count - 1, step + 1)]
            case .right: selection = rows.first?.first
            case .left: break
            }
            return
        }
        guard let row = rows.firstIndex(where: { $0.contains(target) }),
              let column = rows[row].firstIndex(of: target) else { return }
        switch direction {
        case .left:
            if column > 0 { selection = rows[row][column - 1] }
            else if let step = rail.last { selection = step }
        case .right:
            if column + 1 < rows[row].count { selection = rows[row][column + 1] }
        case .up:
            if row > 0 { selection = rows[row - 1][min(column, rows[row - 1].count - 1)] }
        case .down:
            // Down into the last row lands on its way forward, not on the way back under the first column.
            if row + 1 < rows.count {
                let next = rows[row + 1]
                selection = row + 2 == rows.count && next.contains(.cancel) ? next.last : next[min(column, next.count - 1)]
            }
        }
    }

    /// Tab and Shift-Tab: every target once, the steps last, and around.
    public mutating func tab(_ step: Int, in rows: [[Target]], rail: [Target] = [], initial: Target? = .primary) {
        let targets = rows.flatMap { $0 } + rail
        guard let index = targets.firstIndex(of: current(in: rows, rail: rail, initial: initial)) else { return }
        selection = targets[(index + step + targets.count) % targets.count]
    }
}
