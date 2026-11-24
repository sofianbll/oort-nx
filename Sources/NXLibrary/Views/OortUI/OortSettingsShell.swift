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
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
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
                                    .padding(.top, canvas.u(SeleneTokens.Space.compact))
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
            .background((lit ? SeleneTheme.focus : (isSelected ? SeleneTheme.glass : .clear)),
                        in: RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            SeleneRow(title, id: id, subtitle: subtitle, verbatimTitle: true, verbatimSubtitle: true) {
                if let value { SeleneValueChip(text: value) }
                MaterialIconView(.chevron, size: SeleneTokens.Space.large)
                    .foregroundStyle(SeleneTheme.ink60)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id("selene-row-\(id)")
    }
}

struct OortSettingsSearchField: View {
    @Binding var query: String
    let request: Int
    let onFocus: () -> Void
    let onSubmit: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale

    var body: some View {
        TextField(L10n.text("Search settings", context: locale), text: $query)
            .modifier(OortField(focused: focused))
            .focused($focused)
            .onChange(of: focused) { _, focused in if focused { onFocus() } }
            .onChange(of: request) { focused = true }
            .onSubmit {
                focused = false
                onSubmit()
            }
    }
}
