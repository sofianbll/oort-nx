import Foundation

/// The keyboard a controller types on: its pages, what each key means and where the focus goes.
public struct OnScreenKeyboard: Equatable, Sendable {
    public enum Key: Hashable, Sendable { case text(String), shift, page, space, erase, done }
    public enum Page: Int, CaseIterable, Sendable { case letters, symbols, accents }
    public enum Move: Sendable { case up, down, left, right }

    public private(set) var page: Page = .letters
    public private(set) var shift = false
    public private(set) var row = 1
    public private(set) var column = 0

    public init() {}

    static let letters = ["1234567890", "QWERTYUIOP", "ASDFGHJKL'", "ZXCVBNM-."]
    static let symbols = ["!?.,;:'\"()", "@#&+=_-/\\*", "[]{}<>|~^%", "$€£°…«»·§"]
    static let accents = ["ÀÂÄÁÃÅÆÇÉÈ", "ÊËÍÎÏÌÑÓÔÖ", "ÒÕŒØÚÙÛÜŸẞ", "¿¡ÝŠŽČĞŁĄ"]

    public var rows: [[Key]] {
        let page = switch page {
        case .letters: Self.letters
        case .symbols: Self.symbols
        case .accents: Self.accents
        }
        return page.map { $0.map { .text(String($0)) } } + [[.shift, .page, .space, .erase, .done]]
    }

    public var focused: Key { rows[row][column] }

    /// What a key types, or nil when it acts instead.
    public func text(_ key: Key) -> String? {
        switch key {
        case .text(let letter): shift ? letter : letter.lowercased()
        case .space: " "
        case .shift, .page, .erase, .done: nil
        }
    }

    /// The page the page key leads to.
    public var nextPage: Page { page.neighbour(1) }

    public mutating func toggleShift() { shift.toggle() }
    public mutating func turnPage(_ delta: Int = 1) {
        page = page.neighbour(delta)
        column = min(column, rows[row].count - 1)
    }

    /// The pointer pressed this key: the focus follows it.
    public mutating func focus(_ key: Key) {
        for (index, keys) in rows.enumerated() {
            if let found = keys.firstIndex(of: key) { (row, column) = (index, found); return }
        }
    }

    /// True when the focus moved. Up and down keep to the key above or below, whatever its width.
    @discardableResult public mutating func move(_ direction: Move) -> Bool {
        let before = (row, column)
        switch direction {
        case .left: column = max(0, column - 1)
        case .right: column = min(rows[row].count - 1, column + 1)
        case .up, .down:
            let target = row + (direction == .up ? -1 : 1)
            guard rows.indices.contains(target) else { return false }
            let x = Self.center(column, in: rows[row])
            row = target
            column = rows[target].indices.min {
                abs(Self.center($0, in: rows[target]) - x) < abs(Self.center($1, in: rows[target]) - x)
            } ?? 0
        }
        return before != (row, column)
    }

    /// Widths in canvas units: every row but the letters' last is as wide as the first.
    public static let gap = 8.0
    public static let width = 10 * 70 + 9 * gap
    public static func width(_ key: Key) -> Double {
        switch key {
        case .text: 70
        case .space: 300
        case .shift, .page, .erase: 100
        case .done: 140
        }
    }

    private static func center(_ index: Int, in keys: [Key]) -> Double {
        let total = keys.reduce(0) { $0 + width($1) + gap } - gap
        return keys[..<index].reduce(-total / 2) { $0 + width($1) + gap } + width(keys[index]) / 2
    }
}

extension OnScreenKeyboard.Page {
    func neighbour(_ delta: Int) -> Self {
        let all = Self.allCases
        return all[(rawValue + delta % all.count + all.count) % all.count]
    }
}
