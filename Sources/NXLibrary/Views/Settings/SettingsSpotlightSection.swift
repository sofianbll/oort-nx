import SwiftUI
import NXLibraryCore

struct SettingsSpotlightSection: View {
    @ObservedObject var settings: SettingsEditor
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var tabs: [String] { settings.settings.libraryTabs.map(\.rawValue) }

    private func toggle(_ tab: LibraryFilter) {
        let shown = settings.settings.libraryTabs
        settings.settings.libraryTabs = LibraryFilter.tabs(shown.contains(tab) ? shown.filter { $0 != tab } : shown + [tab])
        if !tabs.contains(settings.settings.startingTab) { settings.settings.startingTab = LibraryFilter.all.rawValue }
    }

    private func cardBinding(_ card: SpotlightCard) -> Binding<Bool> {
        Binding(
            get: { settings.settings.visibleSpotlightCards.contains(card) },
            set: { _ in toggle(card) }
        )
    }

    private func toggle(_ card: SpotlightCard) {
        var cards = settings.settings.visibleSpotlightCards
        if let index = cards.firstIndex(of: card) {
            cards.remove(at: index)
        } else {
            // Keep the canonical order so the row reads the same every time.
            cards = SpotlightCard.allCases.filter { cards.contains($0) || $0 == card }
        }
        settings.settings.visibleSpotlightCards = cards
    }

    private func stepTab(_ step: Int) {
        if let next = tabs.stepped(from: settings.settings.startingTab, step) {
            settings.settings.startingTab = next
        }
    }

    private func stepPlatformInfo(_ step: Int) {
        settings.settings.platformCardInfo = settings.settings.platformCardInfo.stepped(step)
    }

    var body: some View {
        OortSettingsGroup {
            SettingsSubheading(L10n.text("Cards"))
            ForEach(SpotlightCard.allCases.filter { $0 != .inbox }, id: \.self) { card in
                SeleneToggleRow(card.title, isOn: cardBinding(card))
            }

            SettingsSubheading(L10n.text("Top tabs"))
            ForEach(LibraryFilter.allCases.filter { $0 != .all }) { tab in
                SeleneToggleRow(tab.rawValue, isOn: Binding(get: { settings.settings.libraryTabs.contains(tab) },
                                                           set: { _ in toggle(tab) }))
            }
            SeleneCycleRow("Starting tab",
                           subtitle: "The filter Spotlight and Collection open on.",
                           value: settings.settings.startingTab) { stepTab($0) }

            SettingsSubheading(L10n.text("Row"))
            SeleneCycleRow("Platform card", subtitle: "What shows beside the platform card.",
                           value: settings.settings.platformCardInfo.titleKey, cycle: stepPlatformInfo)

            SeleneButtonRow("Tile order",
                            subtitle: settings.settings.spotlightOrder.isEmpty
                                ? "Spotlight uses its own order."
                                : "Your own order of games and cards.",
                            buttonTitle: "Reset") {
                settings.settings.spotlightOrder = []
            }
        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        var actions: [SettingsRowAction] = SpotlightCard.allCases.filter { $0 != .inbox }.map { card in
            .init(id: "card-\(card.rawValue)", title: card.title) { toggle(card) }
        }
        actions += LibraryFilter.allCases.filter { $0 != .all }.map { tab in
            .init(id: "tab-\(tab.rawValue)", title: tab.rawValue) { toggle(tab) }
        }
        actions.append(.value("startingTab", "Starting tab") { stepTab($0) })
        actions.append(.value("platformCardInfo", "Platform card", cycle: stepPlatformInfo))
        actions.append(.init(id: "order", title: "Tile order") {
            settings.settings.spotlightOrder = []
        })
        onActions(actions)
    }
}
