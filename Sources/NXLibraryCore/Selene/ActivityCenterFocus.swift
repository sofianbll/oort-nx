import Foundation

public struct ActivityCenterFocus: Equatable {
    public enum Row: Hashable {
        case build(UUID?), queuedBuild(UUID), cloud(UUID), queuedCloud(UUID), move(UUID), refresh(UUID), undo, result(UUID), clearAll, close

        public var opensPorting: Bool {
            switch self {
            case .build, .queuedBuild: return true
            default: return false
            }
        }

        public func canCancel(isCancellingBuild: Bool) -> Bool {
            switch self {
            case .build(let id): return id != nil && !isCancellingBuild
            case .queuedBuild, .cloud, .queuedCloud, .move: return true
            case .refresh, .undo, .result, .clearAll, .close: return false
            }
        }
    }

    public var selected: Row?

    public init() {}

    public static func rows(isBuilding: Bool, activeBuild: UUID? = nil, queuedBuilds: [UUID] = [],
                            activeCloud: UUID? = nil, queuedCloud: [UUID] = [], move: UUID? = nil,
                            refresh: UUID? = nil, results: [UUID] = [], undo: Bool = false) -> [Row] {
        var rows: [Row] = isBuilding ? [.build(activeBuild)] : []
        rows += queuedBuilds.map(Row.queuedBuild)
        if let activeCloud { rows.append(.cloud(activeCloud)) }
        rows += queuedCloud.map(Row.queuedCloud)
        if let move { rows.append(.move(move)) }
        if let refresh { rows.append(.refresh(refresh)) }
        if undo { rows.append(.undo) }
        if !results.isEmpty { rows += results.map(Row.result) + [.clearAll] }
        return rows
    }

    public func current(in rows: [Row]) -> Row {
        guard let selected else { return rows.first ?? .close }
        // A vanished request must not silently hand its cancel shortcut to another row.
        return rows.contains(selected) ? selected : .close
    }

    public mutating func move(by delta: Int, in rows: [Row]) {
        guard let current = rows.firstIndex(of: current(in: rows)) else {
            selected = delta < 0 ? rows.last : rows.first
            return
        }
        var index = FocusIndex(index: current)
        index.move(by: delta, count: rows.count)
        selected = rows.indices.contains(index.index) ? rows[index.index] : .close
    }
}
