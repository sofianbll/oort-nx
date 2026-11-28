import Foundation

/// What the command palette lists.
public enum PaletteKind: String, CaseIterable, Sendable {
    case game, action, setting
}

/// One thing the palette can run. The app keeps what it does; this is what it says and what finds it.
public struct PaletteItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: PaletteKind
    public let title: String
    /// A short fact beside the title: the platform of a game, the place of a setting.
    public let detail: String?
    /// The heading it stands under while browsing.
    public let section: String?
    public let shortcut: String?
    /// The label of its main action ("Play").
    public let primary: String?
    /// The label of its second action ("Options").
    public let secondary: String?
    /// False for what ends the session: the first row of an empty field must never quit the app.
    public let isRemembered: Bool

    let titleKey: String
    let aliasKeys: [String]
    let noteKeys: [String]

    /// `aliases` are other names (the English one); `notes` are sentences about it.
    public init(id: String, kind: PaletteKind, title: String, detail: String? = nil, section: String? = nil,
                shortcut: String? = nil, primary: String? = nil, secondary: String? = nil,
                aliases: [String] = [], notes: [String] = [], isRemembered: Bool = true) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.section = section
        self.shortcut = shortcut
        self.primary = primary
        self.secondary = secondary
        self.isRemembered = isRemembered
        titleKey = PaletteText.normalize(title)
        aliasKeys = aliases.map(PaletteText.normalize).filter { !$0.isEmpty }
        noteKeys = (notes + [detail, section].compactMap { $0 }).map(PaletteText.normalize).filter { !$0.isEmpty }
    }
}

/// Text as the palette compares it: no case, accents, marks or punctuation.
public enum PaletteText {
    private static let ligatures = ["œ": "oe", "æ": "ae", "ß": "ss", "ø": "o", "ł": "l"]

    public static func normalize(_ text: String) -> String {
        var folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        for (letter, letters) in ligatures { folded = folded.replacingOccurrences(of: letter, with: letters) }
        return folded.split { !($0.isLetter || $0.isNumber) }.joined(separator: " ")
    }

    static let lastNameScore = 7

    /// Names up to `lastNameScore`, the title before an alias that says as much; then sentences. Nil when the text
    /// does not hold the query.
    static func score(_ query: String, _ item: PaletteItem) -> Int? {
        let tokens = query.split(separator: " ")
        // One Latin letter inside a word says nothing; one Chinese character does.
        let searchesInside = query.count > 1 || query.unicodeScalars.contains { $0.value >= 0x2E80 }
        func starts(_ text: String) -> Bool {
            let words = text.split(separator: " ")
            return tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
        }
        let compact = query.replacingOccurrences(of: " ", with: "")
        func band(_ name: String) -> Int? {
            if name == query { return 0 }
            if name.hasPrefix(query) { return 1 }
            if starts(name) { return 2 }
            let inside = searchesInside && (name.contains(query) || name.replacingOccurrences(of: " ", with: "").contains(compact))
            return inside ? 3 : nil
        }
        let title = band(item.titleKey).map { $0 * 2 }
        let alias = item.aliasKeys.compactMap(band).min().map { $0 * 2 + 1 }
        if let best = [title, alias].compactMap({ $0 }).min() { return best }
        let everything = ([item.titleKey] + item.aliasKeys + item.noteKeys).joined(separator: " ")
        if starts(everything) { return lastNameScore + 1 }
        return searchesInside && tokens.allSatisfy { everything.contains($0) } ? lastNameScore + 2 : nil
    }

    /// As `score`, with one wrong letter allowed in a word of four, two from eight.
    static func guess(_ query: String, _ item: PaletteItem) -> Int? {
        let words = ([item.titleKey] + item.aliasKeys).flatMap { $0.split(separator: " ").map(Array.init) }
        var total = 0
        for token in query.split(separator: " ").map(Array.init) {
            let allowed = token.count < 4 ? 0 : token.count < 8 ? 1 : 2
            guard let best = words.compactMap({ distance(token, toStartOf: $0, within: allowed) }).min() else { return nil }
            total += best
        }
        return lastNameScore + 3 + total
    }

    /// Wrong, missing, extra or swapped letters between `token` and the closest start of `word`.
    static func distance(_ token: [Character], toStartOf word: [Character], within allowed: Int) -> Int? {
        let word = Array(word.prefix(token.count + allowed))
        guard word.count + allowed >= token.count else { return nil }
        var before: [Int] = []
        var previous = Array(0...word.count)
        for (i, letter) in token.enumerated() {
            var row = [i + 1]
            for (j, other) in word.enumerated() {
                var cost = min(previous[j + 1] + 1, row[j] + 1, previous[j] + (letter == other ? 0 : 1))
                if i > 0, j > 0, letter == word[j - 1], token[i - 1] == other { cost = min(cost, before[j - 1] + 1) }
                row.append(cost)
            }
            guard row.min()! <= allowed || previous.min()! <= allowed else { return nil }
            before = previous
            previous = row
        }
        return previous.min().flatMap { $0 <= allowed ? $0 : nil }
    }
}

public enum PaletteGroupID: Hashable, Sendable {
    case recents, suggestions, browse
    case kind(PaletteKind)
    case section(String)
}

public enum PaletteRow: Equatable, Sendable {
    case item(PaletteItem)
    /// Opens every row of this kind; the number is how many there are.
    case seeAll(PaletteKind, Int)
}

public struct PaletteGroup: Identifiable, Equatable, Sendable {
    public let id: PaletteGroupID
    public let rows: [PaletteRow]
    public let total: Int

    init(_ id: PaletteGroupID, _ rows: [PaletteRow], total: Int? = nil) {
        self.id = id
        self.rows = rows
        self.total = total ?? rows.count
    }

    public var items: [PaletteItem] { rows.compactMap { if case .item(let item) = $0 { item } else { nil } } }
    public var seeAll: PaletteKind? { rows.lazy.compactMap { if case .seeAll(let kind, _) = $0 { kind } else { nil } }.first }
}

public enum Palette {
    /// The most rows a group shows before See all.
    public static let limit = 5

    /// An empty field shows what was used last, what helps and what to browse; `scope` shows everything of one kind.
    public static func groups(query: String, scope: PaletteKind? = nil, in items: [PaletteItem],
                              recents: [String] = [], suggestions: [String] = []) -> [PaletteGroup] {
        let key = PaletteText.normalize(query)
        let scoped = scope.map { kind in items.filter { $0.kind == kind } } ?? items
        guard !key.isEmpty else {
            return scope == nil ? home(items, recents: recents, suggestions: suggestions) : sections(scoped)
        }
        let found = search(key, in: scoped)
        let groups = PaletteKind.allCases.compactMap { kind -> (score: Int, group: PaletteGroup)? in
            let matches = found.filter { $0.item.kind == kind }
            guard let best = matches.first else { return nil }
            var rows = matches.prefix(scope == nil ? limit : matches.count).map { PaletteRow.item($0.item) }
            if rows.count < matches.count { rows.append(.seeAll(kind, matches.count)) }
            return (best.score, PaletteGroup(.kind(kind), rows, total: matches.count))
        }
        return groups.enumerated().sorted { ($0.element.score, $0.offset) < ($1.element.score, $1.offset) }.map(\.element.group)
    }

    private static func search(_ key: String, in items: [PaletteItem]) -> [(score: Int, item: PaletteItem)] {
        var found = items.compactMap { item in PaletteText.score(key, item).map { (score: $0, item: item) } }
        // A name that holds the words needs no guess.
        if !found.contains(where: { $0.score <= PaletteText.lastNameScore }) {
            let known = Set(found.map(\.item.id))
            found += items.compactMap { item in
                known.contains(item.id) ? nil : PaletteText.guess(key, item).map { (score: $0, item: item) }
            }
        }
        return found.enumerated().sorted { ($0.element.score, $0.offset) < ($1.element.score, $1.offset) }.map(\.element)
    }

    private static func home(_ items: [PaletteItem], recents: [String], suggestions: [String]) -> [PaletteGroup] {
        let known = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let last = recents.compactMap { known[$0] }.prefix(limit)
        let shown = Set(last.map(\.id))
        let helpful = suggestions.filter { !shown.contains($0) }.compactMap { known[$0] }.prefix(limit)
        let browse = PaletteKind.allCases.compactMap { kind -> PaletteRow? in
            let count = items.count { $0.kind == kind }
            return count == 0 ? nil : .seeAll(kind, count)
        }
        return [PaletteGroup(.recents, last.map(PaletteRow.item)), PaletteGroup(.suggestions, helpful.map(PaletteRow.item)),
                PaletteGroup(.browse, browse)].filter { !$0.rows.isEmpty }
    }

    private static func sections(_ items: [PaletteItem]) -> [PaletteGroup] {
        var order: [String] = []
        var rows: [String: [PaletteRow]] = [:]
        for item in items {
            let name = item.section ?? ""
            if rows[name] == nil { order.append(name) }
            rows[name, default: []].append(.item(item))
        }
        return order.map { PaletteGroup($0.isEmpty ? .kind(items[0].kind) : .section($0), rows[$0] ?? []) }
    }
}

/// Where the palette is: what was typed, the list it opened, and the row in focus among the rows shown.
public struct PaletteState: Equatable, Sendable {
    public private(set) var query: String
    public private(set) var scope: PaletteKind?
    public var focus = 0
    private var focusBeforeScope = 0

    public init(query: String = "") { self.query = query }

    public mutating func setQuery(_ query: String) {
        guard query != self.query else { return }
        self.query = query
        focus = 0
        focusBeforeScope = 0
    }

    public mutating func open(_ kind: PaletteKind) {
        focusBeforeScope = focus
        scope = kind
        focus = 0
    }

    /// Leaves the list See all opened; false when there is none to leave.
    public mutating func back() -> Bool {
        guard scope != nil else { return false }
        scope = nil
        focus = focusBeforeScope
        return true
    }

    public mutating func settle(count: Int) { focus = min(max(focus, 0), max(count - 1, 0)) }

    public mutating func move(by delta: Int, count: Int) -> Bool { go(to: focus + delta, count: count) }

    public mutating func jump(toEnd: Bool, count: Int) -> Bool { go(to: toEnd ? count - 1 : 0, count: count) }

    /// The first row of the next group, or of this one, then the one before.
    public mutating func moveGroup(by delta: Int, in groups: [PaletteGroup]) -> Bool {
        var starts: [Int] = []
        var count = 0
        for group in groups {
            starts.append(count)
            count += group.rows.count
        }
        let target = delta > 0 ? starts.first { $0 > focus } : starts.last { $0 < focus }
        guard let target else { return false }
        return go(to: target, count: count)
    }

    private mutating func go(to index: Int, count: Int) -> Bool {
        let old = focus
        focus = index
        settle(count: count)
        return focus != old
    }
}

public enum PaletteRecents {
    public static func adding(_ id: String, to recents: [String]) -> [String] {
        Array(([id] + recents.filter { $0 != id }).prefix(Palette.limit))
    }

    public static func adding(_ item: PaletteItem, to recents: [String]) -> [String] {
        item.isRemembered ? adding(item.id, to: recents) : recents
    }
}
