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

    /// What Return and A press when the player has not moved: the way forward, or the way back when going forward erases
    /// or moves things.
    public static func initial<Item>(_ items: [Item], safe: Bool = false, role: (Item) -> ActionBarRole) -> Item? {
        let order: [ActionBarRole] = safe ? [.back, .secondary, .primary, .destructive] : [.primary, .secondary, .back, .destructive]
        for wanted in order { if let item = items.first(where: { role($0) == wanted }) { return item } }
        return nil
    }
}
