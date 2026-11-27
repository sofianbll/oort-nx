import AppKit
import OortLibrary
import SwiftUI

/// The open command palette: what it lists, what was typed and the row in focus. It runs nothing itself;
/// the shell hears the choice.
@MainActor
final class CommandPalette: ObservableObject {
    /// The picture of a row: the game's art in memory, its platform, or a glyph.
    enum Symbol {
        case art(NSImage), platform(PlatformKind), icon(MaterialIcon)
    }

    @Published private(set) var groups: [PaletteGroup] = []
    @Published private(set) var state = PaletteState()
    private var items: [PaletteItem] = []
    private var recents: [String] = []
    private var suggestions: [String] = []
    private var symbols: [String: Symbol] = [:]
    private var returnFocus: PaletteRow?
    var onChoose: (_ item: PaletteItem, _ secondary: Bool) -> Void = { _, _ in }
    var onClose: () -> Void = {}

    var rows: [PaletteRow] { groups.flatMap(\.rows) }
    var focusedRow: PaletteRow? { rows.indices.contains(state.focus) ? rows[state.focus] : nil }
    var focusedItem: PaletteItem? { if case .item(let item) = focusedRow { item } else { nil } }
    /// How many things match, beyond the rows shown.
    var total: Int { groups.reduce(0) { $0 + $1.total } }

    func symbol(_ item: PaletteItem) -> Symbol { symbols[item.id] ?? .icon(.settings) }

    func open(query: String = "", items: [PaletteItem], recents: [String], suggestions: [String],
              symbols: [String: Symbol]) {
        self.items = items
        self.symbols = symbols
        self.recents = recents
        self.suggestions = suggestions
        returnFocus = nil
        state = PaletteState(query: query)
        refresh()
    }

    /// The library changed under an open palette: the same words, the new games.
    func update(items: [PaletteItem], symbols: [String: Symbol]) {
        let previous = focusedRow
        self.items = items
        self.symbols = symbols
        refresh()
        restoreFocus(previous)
    }

    func type(_ query: String) {
        guard query != state.query else { return }
        returnFocus = nil
        state.setQuery(query)
        refresh()
    }

    func focus(_ index: Int) {
        guard index != state.focus else { return }
        state.focus = index
    }

    func press(_ index: Int) {
        focus(index)
        choose()
    }

    /// The field keeps letters, ← and →; these keys move the list or run its row.
    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> GamepadAction? {
        switch (keyCode, modifiers.intersection([.command, .control, .option, .shift])) {
        case (125, []): .navigateDown
        case (126, []): .navigateUp
        case (48, []): .tabNext                  // Tab
        case (48, [.shift]): .tabPrevious
        case (115, []): .jumpToStart             // Home
        case (119, []): .jumpToEnd               // End
        case (36, []), (76, []): .confirm        // Return, keypad Enter
        case (36, [.command]), (76, [.command]): .contextAction
        case (53, []): .cancel                   // Esc
        default: nil
        }
    }

    func handle(_ action: GamepadAction) {
        var moved = false
        switch action {
        case .navigateUp: moved = state.move(by: -1, count: rows.count)
        case .navigateDown: moved = state.move(by: 1, count: rows.count)
        case .tabPrevious: moved = state.moveGroup(by: -1, in: groups)
        case .tabNext: moved = state.moveGroup(by: 1, in: groups)
        case .jumpToStart: moved = state.jump(toEnd: false, count: rows.count)
        case .jumpToEnd: moved = state.jump(toEnd: true, count: rows.count)
        case .confirm: choose()
        case .contextAction, .menu: chooseSecondary()
        case .cancel: back()
        default: break
        }
        if moved { SoundEffectService.shared.play(.focus) }
    }

    func choose() {
        switch focusedRow {
        case .item(let item):
            SoundEffectService.shared.play(.click)
            onChoose(item, false)
        case .seeAll(let kind, _):
            SoundEffectService.shared.play(.click)
            returnFocus = focusedRow
            state.open(kind)
            refresh()
        case nil: break
        }
    }

    func chooseSecondary() {
        guard let item = focusedItem, item.secondary != nil else { return }
        SoundEffectService.shared.play(.click)
        onChoose(item, true)
    }

    /// Esc and B: out of See all, then out of the palette.
    func back() {
        SoundEffectService.shared.play(.back)
        if state.back() {
            refresh()
            if let returnFocus { restoreFocus(returnFocus) }
            returnFocus = nil
        } else { onClose() }
    }

    private func restoreFocus(_ previous: PaletteRow?) {
        state.focus = rows.firstIndex { row in
            switch (previous, row) {
            case (.item(let old)?, .item(let new)): old.id == new.id
            case (.seeAll(let old, _)?, .seeAll(let new, _)): old == new
            default: false
            }
        } ?? -1
    }

    private func refresh() {
        groups = Palette.groups(query: state.query, scope: state.scope, in: items, recents: recents, suggestions: suggestions)
        state.settle(count: rows.count)
    }
}
