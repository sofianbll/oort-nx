/// The order of a panel's or a question's keys: the way back on the left, the way forward last on the right,
/// where the pad's B and A hints already are. What erases stands apart, left of the way back.
public enum ActionBarRole: Int, CaseIterable, Sendable {
    case destructive, back, secondary, primary

    /// On the left or the right of the bar.
    public var isLeading: Bool { self == .destructive || self == .back }
}

public enum ActionBarOrder {
    /// Left to right, as drawn and as Left and Right move. Keys of one role keep the order they were given in.
    public static func sorted<Item>(_ items: [Item], role: (Item) -> ActionBarRole) -> [Item] {
        items.enumerated().sorted {
            (role($0.element).rawValue, $0.offset) < (role($1.element).rawValue, $1.offset)
        }.map(\.element)
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
        // Without a main answer, the first other one leads; alone, an answer that erases is still the question's own.
        let answers = (main.map { [$0] } ?? []) + others
        for (index, answer) in answers.enumerated().reversed() {
            keys.append((answer, index == 0 ? .primary : erases(answer) ? .destructive : .secondary))
        }
        keys.append((back, answers.isEmpty ? .primary : .back))
        return sorted(keys) { $0.role }
    }

    /// What Return and A press when the player has not moved: the way forward, or the way back when going forward erases
    /// or moves things.
    public static func initial<Item>(_ items: [Item], safe: Bool = false, role: (Item) -> ActionBarRole) -> Item? {
        let order: [ActionBarRole] = safe ? [.back, .secondary, .primary, .destructive] : [.primary, .secondary, .back, .destructive]
        for wanted in order { if let item = items.first(where: { role($0) == wanted }) { return item } }
        return nil
    }
}
