import SwiftUI
import NXLibraryCore

/// Categories, subjects and search results share the detail column, not their storage identities.
enum SettingsPage: Hashable {
    case category(SettingsCategory)
    case subject(SettingsSection)
    case search, changed

    static let stops: [Self] = [.search, .changed] + SettingsCategory.allCases.map(Self.category)

    static func opening(_ section: SettingsSection) -> OortSettingsStack<Self> {
        guard let category = SettingsCategory(section: section) else {
            return .init(section == .changed ? .changed : .search)
        }
        var stack = OortSettingsStack<Self>(.category(category))
        if category.sections.count > 1 { stack.push(.subject(section)) }
        return stack
    }

    var section: SettingsSection? {
        switch self {
        case .search: .search
        case .changed: .changed
        case .subject(let section): section
        case .category(let category): category.sections.count == 1 ? category.sections.first : nil
        }
    }

    func title(in context: AppLocale) -> String {
        switch self {
        case .category(let category): return category.title(in: context)
        case .subject(let section):
            if let category = SettingsCategory(section: section) {
                return category.sections.count == 1 ? category.title(in: context) : category.title(for: section, in: context)
            }
            return section.title(in: context)
        case .search, .changed: return L10n.text("Search", context: context)
        }
    }
}

struct SettingsSidebar: View {
    let selection: SettingsPage
    let isFocused: Bool
    @Binding var query: String
    let searchFieldRequest: Int
    let onSelect: (SettingsPage) -> Void
    let onSearchFocus: () -> Void
    let onSubmit: () -> Void
    @Environment(\.nxAppLocale) private var context
    @Environment(\.seleneCanvas) private var canvas

    typealias Sidebar = OortSettingsSidebar<SettingsPage, AnyView>

    var body: some View {
        Sidebar(sections: SettingsCategory.groups.map { group in
            .init(title: group.heading.map { L10n.text($0, context: context) },
                  items: group.categories.compactMap { category in
                category.sections.first.map {
                    .init(id: .category(category), title: category.title(in: context), icon: $0.icon)
                }
            })
        }, selected: selection, focused: isFocused, onSelect: onSelect) {
            AnyView(header)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            OortSettingsSearchField(query: $query, request: searchFieldRequest, onFocus: onSearchFocus, onSubmit: onSubmit)
            HStack(spacing: canvas.u(SeleneTokens.Space.hairline)) {
                SelenePillButton(title: "All", focused: selection == .search) { onSelect(.search) }
                SelenePillButton(title: "Changed", focused: selection == .changed) { onSelect(.changed) }
            }
            .accessibilityElement(children: .contain)
        }
    }
}
