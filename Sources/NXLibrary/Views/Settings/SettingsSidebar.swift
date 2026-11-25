import SwiftUI
import NXLibraryCore

/// Categories, subjects and search results share the detail column, not their storage identities.
enum SettingsPage: Hashable {
    case category(SettingsCategory)
    case subject(SettingsSection)
    case search, changed

    static let stops: [Self] = [.search] + SettingsCategory.allCases.map(Self.category) + [.changed]

    static func opening(_ section: SettingsSection) -> OortSettingsStack<Self> {
        guard let category = SettingsCategory(section: section) else {
            return .init(section == .changed ? .changed : .search)
        }
        var stack = OortSettingsStack<Self>(.category(category))
        if category.subjects.contains(section) { stack.push(.subject(section)) }
        return stack
    }

    var inlineSections: [SettingsSection] {
        switch self {
        case .search: [.search]
        case .changed: [.changed]
        case .subject(let section): [section]
        case .category(let category): category.inlineSections
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
        case .search: return L10n.text("Search", context: context)
        case .changed: return L10n.text("Changed settings", context: context)
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

    typealias Sidebar = OortSettingsSidebar<SettingsPage, AnyView>

    var body: some View {
        Sidebar(sections: SettingsCategory.groups.enumerated().map { index, group in
            .init(title: group.heading.map { L10n.text($0, context: context) },
                  items: group.categories.compactMap { category in
                category.sections.first.map {
                    .init(id: .category(category), title: category.title(in: context), icon: $0.icon)
                }
            } + (index == SettingsCategory.groups.count - 1
                 ? [.init(id: .changed, title: SettingsPage.changed.title(in: context), icon: SettingsSection.changed.icon)] : []))
        }, selected: selection, focused: isFocused, onSelect: onSelect) {
            AnyView(OortSettingsSearchField(query: $query, request: searchFieldRequest, selected: isFocused && selection == .search,
                                            onFocus: onSearchFocus, onSubmit: onSubmit))
        }
    }
}
