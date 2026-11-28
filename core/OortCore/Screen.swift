import Foundation

/// A screen as the core decides it, for every renderer: its nodes, their order, which takes the focus first, and what
/// A, B and X do on each, with their words. It names no host type, no size or position, no key and no design token:
/// a renderer draws each node with its own native piece and moves the focus in the published order.
/// `Screen.json` (Codable) is the only encoding: what a companion sends, what the reference trees are made of.
public struct Screen: Equatable, Sendable, Codable {
    public let id: String
    public let title: Text
    public let lead: Text?
    public let blocks: [Node]
    /// Every focusable node, in the order Up and Down go through them. Also where VoiceOver and TalkBack start.
    public let focusOrder: [String]
    public let initialFocus: String?
    /// B, on every node of the screen.
    public let back: Gesture

    public init(id: String, title: Text, lead: Text? = nil, blocks: [Node], initialFocus: String? = nil, back: Gesture) {
        let order = blocks.flatMap(\.focusable)
        precondition(Self.problem(id, order, initialFocus) == nil, Self.problem(id, order, initialFocus) ?? "")
        (self.id, self.title, self.lead, self.blocks, self.back) = (id, title, lead, blocks, back)
        focusOrder = order
        self.initialFocus = initialFocus ?? order.first
    }

    private static func problem(_ id: String, _ order: [String], _ initialFocus: String?) -> String? {
        if Set(order).count != order.count { return "\(id): two focusable nodes share an identity" }
        if let initialFocus, !order.contains(initialFocus) { return "\(id): the initial focus is not a focusable node" }
        return nil
    }

    enum CodingKeys: String, CodingKey { case id, title, lead, blocks, focusOrder, initialFocus, back }

    /// A decoded screen keeps the rules of one made here: its focus order is the one its nodes give.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let blocks = try c.decode([Node].self, forKey: .blocks)
        let initialFocus = try c.decodeIfPresent(String.self, forKey: .initialFocus)
        let order = blocks.flatMap(\.focusable)
        if let problem = Self.problem(id, order, initialFocus) {
            throw DecodingError.dataCorruptedError(forKey: .blocks, in: c, debugDescription: problem)
        }
        if let published = try c.decodeIfPresent([String].self, forKey: .focusOrder), published != order {
            throw DecodingError.dataCorruptedError(forKey: .focusOrder, in: c, debugDescription: "\(id): not the order of its nodes")
        }
        self.init(id: id, title: try c.decode(Text.self, forKey: .title), lead: try c.decodeIfPresent(Text.self, forKey: .lead),
                  blocks: blocks, initialFocus: initialFocus, back: try c.decode(Gesture.self, forKey: .back))
    }

    /// Words of the core's catalogue: `key` and what fills it. A renderer puts them into words once, with its own lookup.
    public struct Text: Hashable, Sendable, Codable {
        public let key: String
        /// Words of the catalogue that fill the first `%@` of `key`, said by the renderer before `args`.
        public var words: [Text]
        /// Fill the `%@` of `key` as they are (a path, a number).
        public var args: [String]
        /// Picks the plural and fills `%lld`.
        public var count: Int?
        /// Fills the `%@` of `key`, said in the reader's locale by the renderer.
        public var date: Date?
        /// Consent depends on it (what is sent, a question's message): a renderer never truncates it.
        public var whole: Bool

        public init(_ key: String, words: [Text] = [], args: [String] = [], count: Int? = nil, date: Date? = nil, whole: Bool = false) {
            (self.key, self.words, self.args, self.count, self.date, self.whole) = (key, words, args, count, date, whole)
        }

        enum CodingKeys: String, CodingKey { case key, words, args, count, date, whole }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(try c.decode(String.self, forKey: .key), words: try c.decodeIfPresent([Text].self, forKey: .words) ?? [],
                      args: try c.decodeIfPresent([String].self, forKey: .args) ?? [],
                      count: try c.decodeIfPresent(Int.self, forKey: .count), date: try c.decodeIfPresent(Date.self, forKey: .date),
                      whole: try c.decodeIfPresent(Bool.self, forKey: .whole) ?? false)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(key, forKey: .key)
            if !words.isEmpty { try c.encode(words, forKey: .words) }
            if !args.isEmpty { try c.encode(args, forKey: .args) }
            try c.encodeIfPresent(count, forKey: .count)
            try c.encodeIfPresent(date, forKey: .date)
            if whole { try c.encode(whole, forKey: .whole) }
        }
    }

    /// How much a status needs the player. Every status is drawn with its dot.
    public enum Tone: String, Sendable, Codable, CaseIterable { case neutral, working, attention }

    public struct Status: Hashable, Sendable, Codable {
        public let text: Text
        public let tone: Tone
        public init(_ text: Text, tone: Tone = .neutral) { (self.text, self.tone) = (text, tone) }
    }

    /// What a gesture asks. The targets of `owner` form a closed list each host declares (an unknown one is refused).
    public enum Intent: Hashable, Sendable, Codable {
        case open(String), back, toggle(String), owner(String)

        enum CodingKeys: String, CodingKey { case intent, id }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id = try c.decodeIfPresent(String.self, forKey: .id)
            switch (try c.decode(String.self, forKey: .intent), id) {
            case ("open", let id?): self = .open(id)
            case ("back", nil): self = .back
            case ("toggle", let id?): self = .toggle(id)
            case ("owner", let id?): self = .owner(id)
            default: throw DecodingError.dataCorruptedError(forKey: .intent, in: c, debugDescription: "unknown intent")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .open(let id): try c.encode("open", forKey: .intent); try c.encode(id, forKey: .id)
            case .back: try c.encode("back", forKey: .intent)
            case .toggle(let id): try c.encode("toggle", forKey: .intent); try c.encode(id, forKey: .id)
            case .owner(let id): try c.encode("owner", forKey: .intent); try c.encode(id, forKey: .id)
            }
        }
    }

    /// A gesture's words and what it asks: the hint, the accessibility hint or named action.
    public struct Gesture: Hashable, Sendable, Codable {
        public let title: Text
        public let intent: Intent
        public init(_ title: Text, _ intent: Intent) { (self.title, self.intent) = (title, intent) }
    }

    /// Asked before an intent that cannot be taken back: Cancel first (left), with the focus; the action after it
    /// (right), in the destructive role.
    public struct Question: Hashable, Sendable, Codable {
        public enum Role: String, Sendable, Codable { case cancel, destructive }
        public struct Choice: Hashable, Sendable, Codable {
            public let role: Role
            public let title: Text
        }

        public let title: Text
        /// Never truncated.
        public let message: Text
        /// In the order they are drawn.
        public let choices: [Choice]
        /// The choice that has the focus when the question opens.
        public let focus: Int

        public init(title: Text, message: Text, confirm: Text, cancel: Text) {
            var message = message
            message.whole = true
            (self.title, self.message) = (title, message)
            choices = [Choice(role: .cancel, title: cancel), Choice(role: .destructive, title: confirm)]
            focus = 0
        }
    }

    /// One node. Its kind says which fields it has; the static constructors are the only way to make one.
    public struct Node: Hashable, Sendable, Codable {
        public enum Kind: String, Sendable, Codable {
            /// `id`, `title`, `items`, `note` (a quiet line under it, « Coming later »).
            case section
            /// `id`, `title`, `items`.
            case box
            /// `id`, `icon`, `title`, `about`, `status`, `on`, `a`, `x`: A opens, X (or a click on the switch) toggles.
            case row
            /// `id`, `title`, `about`, `on`, `a`: a switch drawn flat; A asks for the other state.
            case toggle
            /// `id`, `title`, `a`, `question`.
            case button
            /// `text`: a sentence; `quiet`: a discreet one.
            case text, quiet
            /// `status`.
            case status
            /// `texts`: what an entry reads, writes and sends, kept together.
            case facts
        }

        public let kind: Kind
        public private(set) var id: String?
        public private(set) var title: Text?
        public private(set) var icon: String?
        public private(set) var about: Text?
        public private(set) var status: Status?
        /// The owner's state: nothing turns at the screen before the owner answers.
        public private(set) var on: Bool?
        public private(set) var a: Gesture?
        public private(set) var x: Gesture?
        public private(set) var question: Question?
        public private(set) var text: Text?
        public private(set) var texts: [Text]?
        public private(set) var note: Text?
        public private(set) var items: [Node]?

        private init(_ kind: Kind) { self.kind = kind }

        public static func section(_ id: String, _ title: Text, _ items: [Node], note: Text? = nil) -> Node {
            var node = Node(.section)
            (node.id, node.title, node.items, node.note) = (id, title, items, note)
            return node
        }

        public static func box(_ id: String, _ title: Text, _ items: [Node]) -> Node {
            var node = Node(.box)
            (node.id, node.title, node.items) = (id, title, items)
            return node
        }

        public static func row(_ id: String, icon: String?, title: Text, about: Text? = nil, status: Status? = nil,
                               on: Bool? = nil, a: Gesture?, x: Gesture? = nil) -> Node {
            precondition(x == nil || on != nil, "\(id): X is only a visible switch")
            var node = Node(.row)
            (node.id, node.icon, node.title, node.about, node.status, node.on, node.a, node.x) = (id, icon, title, about, status, on, a, x)
            return node
        }

        public static func toggle(_ id: String, title: Text, about: Text? = nil, on: Bool, a: Gesture) -> Node {
            var node = Node(.toggle)
            (node.id, node.title, node.about, node.on, node.a) = (id, title, about, on, a)
            return node
        }

        public static func button(_ id: String, _ title: Text, a: Gesture, question: Question? = nil) -> Node {
            var node = Node(.button)
            (node.id, node.title, node.a, node.question) = (id, title, a, question)
            return node
        }

        public static func text(_ text: Text) -> Node { var node = Node(.text); node.text = text; return node }
        public static func quiet(_ text: Text) -> Node { var node = Node(.quiet); node.text = text; return node }
        public static func status(_ status: Status) -> Node { var node = Node(.status); node.status = status; return node }
        public static func facts(_ texts: [Text]) -> Node { var node = Node(.facts); node.texts = texts; return node }

        /// Takes the focus: rows, switches and buttons, also without A (A is then refused).
        public var isFocusable: Bool { [.row, .toggle, .button].contains(kind) }

        /// The identities of the focusable nodes in it and under it, in order.
        public var focusable: [String] {
            (isFocusable ? [id].compactMap { $0 } : []) + (items ?? []).flatMap(\.focusable)
        }

        /// This node and every node under it, depth first.
        public var all: [Node] { [self] + (items ?? []).flatMap(\.all) }
    }

    /// Every node of the screen, depth first.
    public var nodes: [Node] { blocks.flatMap(\.all) }

    public func node(_ id: String?) -> Node? {
        guard let id else { return nil }
        return nodes.first { $0.id == id && $0.isFocusable }
    }

    /// Where the focus is: the given identity while it is on the screen, else the initial focus (after it disappeared).
    public func focus(_ id: String?) -> String? {
        id.flatMap { focusOrder.contains($0) ? $0 : nil } ?? initialFocus
    }

    /// Up (-1) and Down (+1) through the published order, stopping at both ends.
    public func moved(from id: String?, by delta: Int) -> String? {
        guard let current = focus(id), let index = focusOrder.firstIndex(of: current) else { return nil }
        return focusOrder[min(max(index + delta, 0), focusOrder.count - 1)]
    }

    /// The roles of the gestures: A chooses, B goes back, X is a secondary action (only a visible switch).
    public enum Key: String, Sendable, Codable, CaseIterable { case a, b, x }

    /// The gesture a key makes on the focused node; nil when it is refused there (a node without A, a row without switch).
    public func gesture(_ key: Key, at id: String?) -> Gesture? {
        switch key {
        case .b: back
        case .a: node(focus(id))?.a
        case .x: node(focus(id))?.x
        }
    }

    /// The hints bar for the focused node: B on the left; X then A on the right.
    public struct Hints: Hashable, Sendable, Codable {
        public let left: [Hint]
        public let right: [Hint]
    }

    public struct Hint: Hashable, Sendable, Codable {
        public let key: Key
        public let gesture: Gesture
    }

    public func hints(at id: String?) -> Hints {
        Hints(left: [Hint(key: .b, gesture: back)],
              right: [Key.x, .a].compactMap { key in gesture(key, at: id).map { Hint(key: key, gesture: $0) } })
    }
}

/// What came of an intent, as the host's effect says it: done (the next screen is drawn from the owners' new facts),
/// refused with its words (or none: the renderer's refusal sound alone), or stale (redrawn, without a message).
public enum ScreenOutcome: Equatable, Sendable {
    case done, refused(Screen.Text?), stale
}
