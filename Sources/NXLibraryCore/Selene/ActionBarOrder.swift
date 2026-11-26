/// The order of a panel's or a question's keys: the way back on the left, the way forward last on the right,
/// where the pad's B and A hints already are. With a third answer, what erases stands apart.
public enum ActionBarRole: Int, CaseIterable, Sendable {
    case destructive, back, secondary, primary

}

/// A dialog answer has an identity that survives moving it to a different slot.
public struct DialogAnswer<ID: Hashable> {
    public let id: ID
    public let title: String
    public let role: ActionBarRole

    public init(_ id: ID, _ title: String, _ role: ActionBarRole) {
        self.id = id
        self.title = title
        self.role = role
    }
}

public enum ActionBarOrder {
    /// Left to right, as drawn and as Left and Right move. Keys of one role keep the order they were given in.
    public static func sorted<Item>(_ items: [Item], role: (Item) -> ActionBarRole) -> [Item] {
        if items.count == 2, items.contains(where: { role($0) == .back }),
           items.contains(where: { role($0) == .destructive }) {
            return items.filter { role($0) == .back } + items.filter { role($0) == .destructive }
        }
        return items.enumerated().sorted {
            (role($0.element).rawValue, $0.offset) < (role($1.element).rawValue, $1.offset)
        }.map(\.element)
    }

    public static func isStacked(count: Int) -> Bool { count >= 4 }

    public static func separatesDestructive<Item>(_ items: [Item], role: (Item) -> ActionBarRole) -> Bool {
        items.count >= 3 && items.contains { role($0) == .destructive }
    }

    /// The order shared by a question and its input. In a list, keep alternatives in the order they are offered.
    public static func dialog<Item>(_ items: [Item], role: (Item) -> ActionBarRole) -> [Item] {
        isStacked(count: items.count) ? stacked(items, role: role) : sorted(items, role: role)
    }

    /// Top to bottom when the keys are a list: the way forward first, what erases then the way back at the bottom.
    public static func stacked<Item>(_ items: [Item], role: (Item) -> ActionBarRole) -> [Item] {
        let place: [ActionBarRole: Int] = [.primary: 0, .secondary: 1, .destructive: 2, .back: 3]
        return items.enumerated().sorted {
            (place[role($0.element)]!, $0.offset) < (place[role($1.element)]!, $1.offset)
        }.map(\.element)
    }

    /// The roles of a question's keys from the answers in the order they are offered, the main one first.
    public static func question<Item>(main: Item?, others: [Item], back: Item, erases: (Item) -> Bool) -> [(item: Item, role: ActionBarRole)] {
        var keys = [(item: Item, role: ActionBarRole)]()
        // The first answer that does not erase leads, even when the nominal main answer erases.
        let answers = (main.map { [$0] } ?? []) + others
        let primary = answers.firstIndex { !erases($0) }
        for (index, answer) in answers.enumerated() {
            keys.append((answer, erases(answer) ? .destructive : index == primary ? .primary : .secondary))
        }
        keys.append((back, answers.isEmpty ? .primary : .back))
        return dialog(keys) { $0.role }
    }

    /// What Return and A press when the player has not moved: the way forward, or the way back when going forward erases
    /// or moves things.
    public static func initial<Item>(_ items: [Item], safe: Bool = false, role: (Item) -> ActionBarRole) -> Item? {
        let order: [ActionBarRole] = safe ? [.back, .secondary, .primary] : [.primary, .secondary, .back]
        for wanted in order { if let item = items.first(where: { role($0) == wanted }) { return item } }
        return nil
    }

    /// Only navigation uses positions. If the focused answer disappeared, never silently press its neighbour.
    public static func move<ID: Hashable>(_ current: ID, by delta: Int, in order: [ID]) -> ID {
        guard let position = order.firstIndex(of: current) else { return current }
        return order[min(max(0, position + delta), order.count - 1)]
    }
}
