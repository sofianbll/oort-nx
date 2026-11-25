import SwiftUI
import NXLibraryCore

/// A sidebar selection is independent of the page currently shown in its detail column.
struct OortSettingsStack<Page: Equatable> {
    private var pages: [Page]
    init(_ root: Page) { pages = [root] }

    var root: Page { pages[0] }
    var current: Page { pages[pages.count - 1] }
    var canGoBack: Bool { pages.count > 1 }

    mutating func select(_ root: Page) { pages = [root] }
    mutating func push(_ page: Page) {
        if page != current { pages.append(page) }
    }
    mutating func goBack() {
        if canGoBack { pages.removeLast() }
    }
}

struct OortSettingsShell<Sidebar: View, Detail: View>: View {
    let title: String
    let onBack: (() -> Void)?
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail
    @State private var rowHelp: String?
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.large)) {
            sidebar()
                .frame(width: min(max(canvas.size.width * 0.27, 175), canvas.u(420)))
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.control)) {
                HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                    if let onBack {
                        OortButton(title: "Back", preset: .compact, action: onBack)
                    }
                    Text(title)
                        .seleneFont(.heading, .semibold)
                        .foregroundStyle(SeleneTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                detail()
                    .onPreferenceChange(OortRowHelpKey.self) { rowHelp = $0 }
                    .safeAreaInset(edge: .bottom, spacing: 0) { OortSettingsHelp(text: rowHelp) }
            }
            .frame(maxWidth: canvas.u(SeleneTokens.Space.settingsMeasure), alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.chromeGutter))
        .padding(.top, canvas.u(SeleneTokens.Space.stageHeader))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct OortSettingsSidebar<ID: Hashable, Header: View>: View {
    struct Item: Identifiable {
        let id: ID
        let title: String
        let icon: MaterialIcon
    }

    struct Section: Identifiable {
        var id: ID { items[0].id }
        let title: String?
        let items: [Item]
    }

    let sections: [Section]
    let selected: ID
    let focused: Bool
    let onSelect: (ID) -> Void
    @ViewBuilder var header: () -> Header
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
            header()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
                        ForEach(sections.filter { !$0.items.isEmpty }) { section in
                            if let title = section.title {
                                Text(title)
                                    .seleneFont(.badge, .semibold)
                                    .foregroundStyle(SeleneTheme.ink)
                                    .padding(.leading, canvas.u(SeleneTokens.Space.panel))
                                    .padding(.top, canvas.u(SeleneTokens.Space.line))
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(section.items) { item in row(item).id(item.id) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(selected) }
                .onChange(of: selected) { _, id in proxy.scrollTo(id) }
            }
        }
        .padding(canvas.u(SeleneTokens.Space.small))
        .oortPanel(radius: canvas.u(SeleneTokens.Radius.field))
        .animation(Motion.focus(reduceMotion), value: selected)
    }

    private func row(_ item: Item) -> some View {
        let isSelected = selected == item.id
        let lit = isSelected && focused
        return Button { onSelect(item.id) } label: {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                MaterialIconView(item.icon, size: SeleneTokens.Space.large)
                    .accessibilityHidden(true)
                Text(item.title)
                    .seleneFont(.row, .medium)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(lit ? SeleneTheme.onFocus : SeleneTheme.ink)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.panel))
            .padding(.vertical, canvas.u(SeleneTokens.Space.tight))
            .background {
                // One pill glides from row to row.
                if isSelected {
                    OortKeyFace(kind: lit ? .solid : .quiet, radius: canvas.u(SeleneTokens.Radius.field - SeleneTokens.Space.small), lit: lit, outlined: false)
                        .matchedGeometryEffect(id: "selection", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(OortPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct OortSettingsLink: View {
    let id: String
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SeleneRow(title, id: id, subtitle: subtitle, verbatimTitle: true) {
                if let value { SeleneValueChip(text: value) }
                MaterialIconView(.chevron, size: SeleneTokens.Space.large)
                    .foregroundStyle(SeleneTheme.ink60)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(OortPressStyle())
        .containerValue(\.oortSettingsRow, true)
        .id("selene-row-\(id)")
    }
}

/// The search field heads the list and follows its grid: same icon column, same text column, same corners.
struct OortSettingsSearchField: View {
    @Binding var query: String
    let request: Int
    var selected = false
    let onFocus: () -> Void
    let onSubmit: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.nxAppLocale) private var locale

    var body: some View {
        OortSearchField(query: $query, lit: focused || selected, preset: .list) {
            TextField(L10n.text("Search settings", context: locale), text: $query).focused($focused)
        }
        .onTapGesture { focused = true }
        .onChange(of: focused) { _, focused in if focused { onFocus() } }
        .onChange(of: request) { focused = true }
        .onSubmit {
            focused = false
            onSubmit()
        }
    }
}

struct OortSettingsRows<ID: Hashable, Content: View>: View {
    var focus: ID?
    @ViewBuilder var content: () -> Content
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                OortSettingsGroup(content: content)
                    .padding(.vertical, canvas.u(SeleneTokens.Space.tight))
            }
            .scrollIndicators(.hidden)
            .onChange(of: focus) { _, id in
                guard let id else { return }
                withAnimation(Motion.focus(reduceMotion)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

struct OortGameSettingRow: View {
    let title: String
    let about: String?
    let value: String?
    let fixed: Bool
    let focused: Bool
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action, !fixed {
                Button(action: action) { row }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityValue(value ?? "")
                    .accessibilityHint(about ?? "")
            } else {
                row.accessibilityElement(children: .combine)
            }
        }
        .containerValue(\.oortSettingsRow, true)
    }

    private var row: some View {
        SeleneOptionRow(icon: nil, title: title, about: about, focused: focused, enabled: !fixed,
                        aboutIsHelp: !fixed) {
            if let value { SeleneValueChip(text: value) }
        }
        .contentShape(Rectangle())
    }
}

/// Previously standalone panels can share the settings detail pane without taking sidebar input.
struct OortSettingsPane {
    let active: Binding<Bool>
    let locked: Binding<Bool>
    let onBack: () -> Void
}

extension EnvironmentValues {
    @Entry var oortSettingsPane: OortSettingsPane? = nil
}

struct OortSettingsPaneLayout<Header: View, Content: View>: View {
    let back: () -> Void
    let hints: [HintItem]
    let locked: Bool
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.oortSettingsPane) private var pane

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if pane == nil { header() }
                content()
            }
            .frame(maxWidth: pane == nil ? canvas.u(1040) : .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, pane == nil ? canvas.u(90) : 0)
            .padding(.bottom, canvas.u(SeleneTokens.Space.panel))
            .contentShape(Rectangle())

            if pane?.active.wrappedValue ?? true {
                SeleneHintsBar(left: [HintItem(.b, "Back", action: back)], right: hints,
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: SeleneTokens.Space.control)
            }
        }
        .onChange(of: locked, initial: true) { _, locked in
            if locked { pane?.active.wrappedValue = true }
            pane?.locked.wrappedValue = locked
        }
        .onDisappear { pane?.locked.wrappedValue = false }
    }
}
