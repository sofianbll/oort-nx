import Foundation

/// A screen as a reader meets it, in one language: what every renderer must draw and do, compared as a tree.
/// Part one is for every renderer: the pieces in drawing order, every text with its typographic role, and each
/// focusable piece in focus order with what A and X ask. Part two is for renderers driven by a controller or a
/// keyboard: the hints bar at each focus. A renderer's own trace is read into the same shape and must be equal.
public struct ScreenTree: Equatable, Sendable, Codable {
    /// A piece a renderer draws with one native control.
    public struct Piece: Hashable, Sendable, Codable {
        public enum Kind: String, Sendable, Codable { case row, dot, `switch`, pill }
        public let piece: Kind
        /// Row title, dot text, pill title; nil for a switch.
        public var text: String?
        /// A row's second line.
        public var about: String?
        /// A dot's tone.
        public var tone: Screen.Tone?
        /// A switch's state.
        public var on: Bool?
        /// A pill that asks a question first is drawn in the destructive role.
        public var destructive: Bool?

        public init(_ piece: Kind, text: String? = nil, about: String? = nil, tone: Screen.Tone? = nil, on: Bool? = nil,
                    destructive: Bool? = nil) {
            (self.piece, self.text, self.about, self.tone, self.on, self.destructive) = (piece, text, about, tone, on, destructive)
        }
    }

    public struct Words: Hashable, Sendable, Codable {
        public enum Role: String, Sendable, Codable, CaseIterable { case screen, lead, heading, card, row, about, body, quiet, status, button }
        public let role: Role
        public let text: String
        /// Never truncated.
        public var whole: Bool?
        public init(_ role: Role, _ text: String, whole: Bool = false) { (self.role, self.text, self.whole) = (role, text, whole ? true : nil) }
    }

    public struct Said: Hashable, Sendable, Codable {
        public let title: String
        /// `open steam`, `back`, `toggle steam`, `owner settings`.
        public let intent: String
        public init(_ title: String, _ intent: String) { (self.title, self.intent) = (title, intent) }
    }

    public struct Focus: Hashable, Sendable, Codable {
        /// The index of the focusable piece in `pieces`.
        public let piece: Int
        public var a: Said?
        public var x: Said?
        /// A asks this question first: its title, its message, then each choice as `role title`, in drawing order.
        public var question: [String]?
        /// The index of the question's choice that has the focus when it opens.
        public var questionFocus: Int?
        public init(piece: Int, a: Said? = nil, x: Said? = nil, question: [String]? = nil, questionFocus: Int? = nil) {
            (self.piece, self.a, self.x, self.question, self.questionFocus) = (piece, a, x, question, questionFocus)
        }
    }

    public struct Structure: Equatable, Sendable, Codable {
        public var pieces: [Piece]
        /// Every text of the screen with its role, in reading order. Renderers that cannot read the order compare a set.
        public var texts: [Words]
        public var focus: [Focus]
        /// The index in `focus` of the initial focus.
        public var initialFocus: Int?
        public var back: Said

        public init(pieces: [Piece], texts: [Words], focus: [Focus], initialFocus: Int?, back: Said) {
            (self.pieces, self.texts, self.focus, self.initialFocus, self.back) = (pieces, texts, focus, initialFocus, back)
        }
    }

    /// The hints bar: B on the left; X then A on the right, as `key title`.
    public struct Bar: Hashable, Sendable, Codable {
        public let left: [String]
        public let right: [String]
        public init(left: [String], right: [String]) { (self.left, self.right) = (left, right) }
    }

    public let screen: String
    public var structure: Structure
    /// The bar at each entry of `structure.focus`, in the same order.
    public var hints: [Bar]

    public init(screen: String, structure: Structure, hints: [Bar]) {
        (self.screen, self.structure, self.hints) = (screen, structure, hints)
    }

    public static func intent(_ intent: Screen.Intent) -> String {
        switch intent {
        case .open(let id): "open \(id)"
        case .back: "back"
        case .toggle(let id): "toggle \(id)"
        case .owner(let target): "owner \(target)"
        }
    }

    /// The tree the screen asks for, its texts said by `say`.
    public init(_ screen: Screen, say: (Screen.Text) -> String) {
        var pieces: [Piece] = [], texts: [Words] = [], focus: [String: Int] = [:]
        func words(_ role: Words.Role, _ text: Screen.Text?) {
            if let text { texts.append(Words(role, say(text), whole: text.whole)) }
        }
        func said(_ gesture: Screen.Gesture?) -> Said? { gesture.map { Said(say($0.title), Self.intent($0.intent)) } }
        func walk(_ node: Screen.Node) {
            switch node.kind {
            case .section:
                words(.heading, node.title)
                node.items?.forEach(walk)
                words(.quiet, node.note)
            case .box:
                words(.card, node.title)
                node.items?.forEach(walk)
            case .row, .toggle:
                if let id = node.id { focus[id] = pieces.count }
                pieces.append(Piece(.row, text: node.title.map(say), about: node.about.map(say)))
                words(.row, node.title)
                words(.about, node.about)
                if let status = node.status {
                    pieces.append(Piece(.dot, text: say(status.text), tone: status.tone))
                    words(.status, status.text)
                }
                if let on = node.on { pieces.append(Piece(.switch, on: on)) }
            case .button:
                if let id = node.id { focus[id] = pieces.count }
                pieces.append(Piece(.pill, text: node.title.map(say), destructive: node.question == nil ? nil : true))
                words(.button, node.title)
            case .text: words(.body, node.text)
            case .quiet: words(.quiet, node.text)
            case .status:
                if let status = node.status {
                    pieces.append(Piece(.dot, text: say(status.text), tone: status.tone))
                    words(.status, status.text)
                }
            case .facts: node.texts?.forEach { words(.body, $0) }
            }
        }
        words(.screen, screen.title)
        words(.lead, screen.lead)
        screen.blocks.forEach(walk)
        let order: [Focus] = screen.focusOrder.compactMap { id in
            guard let node = screen.node(id), let piece = focus[id] else { return nil }
            let question = node.question.map { q in [say(q.title), say(q.message)] + q.choices.map { "\($0.role.rawValue) \(say($0.title))" } }
            return Focus(piece: piece, a: said(node.a), x: said(node.x), question: question, questionFocus: node.question?.focus)
        }
        let structure = Structure(pieces: pieces, texts: texts, focus: order,
                                  initialFocus: screen.initialFocus.flatMap(screen.focusOrder.firstIndex), back: said(screen.back)!)
        func bar(_ id: String?) -> Bar {
            let hints = screen.hints(at: id)
            func line(_ hint: Screen.Hint) -> String { "\(hint.key.rawValue) \(say(hint.gesture.title))" }
            return Bar(left: hints.left.map(line), right: hints.right.map(line))
        }
        self.init(screen: screen.id, structure: structure, hints: screen.focusOrder.map(bar))
    }
}
