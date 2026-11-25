import Foundation

/// Where the focus is on a screen: rows of controls, each row remembering its own place.
public struct FocusGrid<ID: Hashable>: Equatable {
    public private(set) var current: ID?
    private var remembered: [ID] = []

    public init(_ current: ID? = nil) { set(current) }

    public mutating func set(_ id: ID?) {
        current = id
        guard let id else { return }
        remembered.removeAll { $0 == id }
        remembered.append(id)
        if remembered.count > 32 { remembered.removeFirst() }
    }

    /// True when the focus moved. A direction with nothing there stays put.
    public mutating func move(_ direction: MoveDirection, in rows: [[ID]]) -> Bool {
        let rows = rows.filter { !$0.isEmpty }
        guard !rows.isEmpty else { return false }
        guard let current, let row = rows.firstIndex(where: { $0.contains(current) }),
              let column = rows[row].firstIndex(of: current) else {
            set(rows[0][0])
            return true
        }
        switch direction {
        case .left where column > 0: set(rows[row][column - 1])
        case .right where column + 1 < rows[row].count: set(rows[row][column + 1])
        case .up where row > 0: set(place(in: rows[row - 1], near: column))
        case .down where row + 1 < rows.count: set(place(in: rows[row + 1], near: column))
        default: return false
        }
        return true
    }

    private func place(in row: [ID], near column: Int) -> ID {
        remembered.last { row.contains($0) } ?? row[min(column, row.count - 1)]
    }

    /// A grid's cards as rows, so the focus goes up and down by whole lines.
    public static func rows(_ ids: [ID], columns: Int) -> [[ID]] {
        let columns = max(1, columns)
        return stride(from: 0, to: ids.count, by: columns).map { Array(ids[$0..<min($0 + columns, ids.count)]) }
    }
}
