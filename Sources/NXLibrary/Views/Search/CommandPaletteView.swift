import AppKit
import NXLibraryCore
import SwiftUI

/// The command palette (⌘K, or Y in Find a game): one field over games, actions and settings.
/// The field keeps the keyboard; the row in focus is what Return or A runs.
struct CommandPaletteView: View {
    @ObservedObject var palette: CommandPalette
    var postAnnouncement: (String) -> Void = { AccessibilityNotification.Announcement($0).post() }

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var hover = SeleneHoverFocus()
    @State private var returnResponder = ReturnResponder()
    @FocusState private var fieldFocused: Bool

    private func text(_ key: String) -> String { L10n.text(key, context: locale) }

    var body: some View {
        SeleneOverlay(style: .search, alignment: .top, onOutside: palette.onClose) {
            VStack(spacing: canvas.u(SeleneTokens.Space.large)) {
                field
                results
            }
            .frame(width: canvas.u(SeleneTokens.Space.transferMeasure))
            .padding(.top, canvas.u(SeleneTokens.Space.pageTop))
            .padding(.bottom, canvas.u(SeleneBottomScrim.contentClearance))
            VStack {
                Spacer()
                SeleneHintsBar(left: [HintItem(.b, palette.state.scope == nil ? "Close" : "Back") { palette.back() }],
                               right: hints)
            }
        }
        .onAppear {
            returnResponder.keep()
            fieldFocused = true
        }
        .onDisappear { returnResponder.giveBack() }
        .onChange(of: palette.total) { announce() }
    }

    private var hints: [HintItem] {
        let item = palette.focusedItem
        var hints: [HintItem] = []
        if let secondary = item?.secondary {
            hints.append(HintItem(.y, secondary, keyboard: .text("⌘↩")) { palette.chooseSecondary() })
        }
        if palette.focusedRow != nil {
            hints.append(HintItem(.a, item?.primary ?? (item == nil ? "See all" : "Open")) { palette.choose() })
        }
        return hints
    }

    private var field: some View {
        OortSearchField(query: query, lit: palette.focusedRow == nil) {
            TextField(text("Search games, settings and actions"), text: query)
                .focused($fieldFocused)
        }
    }

    private var query: Binding<String> {
        Binding(get: { palette.state.query }, set: palette.type)
    }

    @ViewBuilder private var results: some View {
        if palette.groups.isEmpty {
            OortEmptyState(title: text("Nothing matches. Try another word."))
            Spacer(minLength: 0)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.large)) {
                        ForEach(starts, id: \.group.id) { start in section(start.group, from: start.index) }
                    }
                    .padding(.bottom, canvas.u(SeleneTokens.Space.control))
                }
                .scrollIndicators(.hidden)
                .onChange(of: palette.state.focus) { _, index in
                    withAnimation(Motion.focus(reduceMotion)) { proxy.scrollTo(index) }
                }
                .onChange(of: palette.state.scope) { proxy.scrollTo(palette.state.focus) }
            }
        }
    }

    /// Each group with the place of its first row among all the rows.
    private var starts: [(group: PaletteGroup, index: Int)] {
        var index = 0
        return palette.groups.map { group in
            defer { index += group.rows.count }
            return (group, index)
        }
    }

    private func section(_ group: PaletteGroup, from start: Int) -> some View {
        OortSection(title: title(group.id)) {
            OortSettingsGroup {
                ForEach(Array(group.rows.enumerated()), id: \.offset) { offset, row in
                    button(row, in: group, index: start + offset)
                }
            }
        }
    }

    private func title(_ id: PaletteGroupID) -> String {
        switch id {
        case .recents: text("Recents")
        case .suggestions: text("Suggestions")
        case .browse: text("Browse")
        case .kind(let kind): title(kind)
        case .section(let name): name
        }
    }

    private func title(_ kind: PaletteKind) -> String {
        switch kind {
        case .game: text("Games")
        case .action: text("Actions")
        case .setting: text("Settings")
        }
    }

    private func button(_ row: PaletteRow, in group: PaletteGroup, index: Int) -> some View {
        let focused = palette.state.focus == index
        return Button { palette.press(index) } label: { label(row, in: group, focused: focused) }
            .buttonStyle(OortPressStyle())
            .containerValue(\.oortSettingsRow, true)
            .id(index)
            .onHover { if hover.moved($0) { palette.focus(index) } }
            .oortItemMenu(secondaryHint(row, at: index))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name(row, in: group))
            .accessibilityValue(value(row))
            .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
            .accessibilityActions {
                if case .item(let item) = row, let secondary = item.secondary {
                    Button(text(secondary)) {
                        palette.focus(index)
                        palette.chooseSecondary()
                    }
                }
            }
    }

    private func secondaryHint(_ row: PaletteRow, at index: Int) -> [HintItem] {
        guard case .item(let item) = row, let secondary = item.secondary else { return [] }
        return [HintItem(.y, secondary) { palette.focus(index); palette.chooseSecondary() }]
    }

    @ViewBuilder private func label(_ row: PaletteRow, in group: PaletteGroup, focused: Bool) -> some View {
        switch row {
        case .item(let item):
            SeleneOptionRow(icon: nil, title: item.title, about: nil, focused: focused, leading: picture(palette.symbol(item))) {
                trailing(item)
            }
        case .seeAll(_, let count):
            SeleneOptionRow(icon: nil, title: name(row, in: group), about: nil, focused: focused, leading: picture(.icon(.menu))) {
                OortReadout(text: number(count), preset: .quiet)
            }
        }
    }

    private func trailing(_ item: PaletteItem) -> some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            if let detail = item.detail {
                OortReadout(text: detail, preset: .quiet).lineLimit(1).truncationMode(.middle)
            }
            if let shortcut = item.shortcut { OortTag(text: shortcut) }
        }
    }

    /// Every row gives its picture the same width, whatever the mark, so the titles line up.
    private func picture(_ symbol: CommandPalette.Symbol) -> AnyView {
        let side = canvas.u(SeleneTokens.Space.large)
        return AnyView(Group {
            switch symbol {
            case .icon(let icon): MaterialIconView(icon, size: SeleneTokens.Space.large)
            case .platform(let kind): PlatformMark(kind: kind)
            case .art(let image):
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.cover), style: .continuous))
            }
        }
        .foregroundStyle(SeleneTheme.rowIcon)
        .frame(width: canvas.u(SeleneTokens.Space.dialogInset))
        .accessibilityHidden(true))
    }

    private func name(_ row: PaletteRow, in group: PaletteGroup) -> String {
        switch row {
        case .item(let item): item.title
        case .seeAll(let kind, _): group.id == .browse ? title(kind) : text("See all")
        }
    }

    private func value(_ row: PaletteRow) -> String {
        switch row {
        case .item(let item): [item.detail, item.shortcut].compactMap { $0 }.joined(separator: ", ")
        case .seeAll(_, let count): number(count)
        }
    }

    private func number(_ count: Int) -> String { count.formatted(.number.locale(locale.formatLocale)) }

    /// The focus stays in the field: VoiceOver hears what the words found.
    private func announce() {
        guard !palette.state.query.isEmpty else { return }
        let found = palette.total == 0 ? text("Nothing matches. Try another word.")
            : L10n.count("%lld results", palette.total, context: locale)
        postAnnouncement([found, palette.focusedItem?.title].compactMap { $0 }.joined(separator: ". "))
    }
}

/// What had the keyboard before the palette, such as a text field, has it again after.
@MainActor
private final class ReturnResponder {
    private weak var window: NSWindow?
    private weak var responder: NSResponder?

    func keep() {
        window = NSApp.keyWindow
        // A field edits through its window's shared editor: the field itself is what comes back.
        let first = window?.firstResponder
        responder = (first as? NSTextView)?.isFieldEditor == true ? (first as? NSTextView)?.delegate as? NSResponder : first
    }

    func giveBack() {
        guard let window, let view = responder as? NSView, view.window === window else { return }
        window.makeFirstResponder(view)
    }
}
