import SwiftUI
import NXLibraryCore

struct SettingsStartUpSection: View {
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    let onChooseLanguage: () -> Void
    let onChooseRegion: () -> Void
    let onOpenOnboarding: () -> Void
    @ObservedObject var profiles: LocalProfileStore
    @Environment(\.seleneCanvas) private var canvas

    private var startOnTitle: String {
        switch settings.settings.startOn {
        case .spotlight: return "Spotlight"
        case .collection: return "Collection"
        case .last: return L10n.text("Where I left")
        }
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SettingsSubheading(L10n.text("Language & region"))
            SeleneButtonRow("App language",
                            subtitle: "Menus, genres and available game descriptions. The games’ own language stays separate.",
                            buttonTitle: settings.settings.appLanguage.nativeName, action: onChooseLanguage)
            SeleneButtonRow("Regional formats", id: "Region",
                            subtitle: "Dates, numbers and sizes only. Game descriptions follow the app language.",
                            buttonTitle: settings.settings.appRegion.flatMap {
                                L10n.context.formatLocale.localizedString(forRegionCode: $0)
                            } ?? L10n.text("Automatic (Mac)"), action: onChooseRegion)

            SeleneCycleRow("Start on",
                           subtitle: "The screen Arcane opens on.",
                           value: startOnTitle) { step in
                settings.settings.startOn = settings.settings.startOn.stepped(step)
            }
            SeleneCycleRow("At startup", subtitle: "Choose who plays when Arcane opens.", value: profileValue,
                           verbatimValue: true, cycle: cycleProfile)

            SeleneToggleRow("Restore last selected game",
                            subtitle: "Reopen the game that was selected when you quit.",
                            isOn: $settings.settings.restoreLastGame)

            SeleneToggleRow("Start in fullscreen",
                            subtitle: "Applies at the next launch.",
                            isOn: $settings.settings.startInFullscreen)

            SeleneToggleRow("Check for app updates",
                            subtitle: "Look for a newer Arcane release at launch, at most once a day.",
                            isOn: $settings.settings.checkAppUpdatesAtLaunch)

            SeleneToggleRow("Entrance animation",
                            subtitle: "The library's tiles fly in with the boot sound when the app opens.",
                            isOn: $settings.settings.introAnimation)
            SeleneButtonRow("Welcome setup", buttonTitle: "Open", action: onOpenOnboarding)
        }
        .onAppear(perform: publishActions)
        .onChange(of: settings.settings.appLanguage) { publishActions() }
        .onChange(of: settings.settings.appRegion) { publishActions() }
    }

    private func publishActions() {
        onActions([
            .init(id: "appLanguage", title: "App language", activate: onChooseLanguage),
            .init(id: "appRegion", title: L10n.text("Regional formats"), rowID: "Region", activate: onChooseRegion),
            .value("startOn", "Start on") { step in
                settings.settings.startOn = settings.settings.startOn.stepped(step)
            },
            .value("showProfilePicker", "At startup", cycle: cycleProfile),
            .init(id: "restore", title: "Restore last selected game") {
                settings.settings.restoreLastGame.toggle()
            },
            .init(id: "startupFullscreen", title: "Start in fullscreen") {
                settings.settings.startInFullscreen.toggle()
            },
            .init(id: "appUpdates", title: "Check for app updates") {
                settings.settings.checkAppUpdatesAtLaunch.toggle()
            },
            .init(id: "intro", title: "Entrance animation") {
                settings.settings.introAnimation.toggle()
            },
            .init(id: "onboarding", title: "Welcome setup", activate: onOpenOnboarding)
        ])
    }

    private var profileValue: String {
        switch settings.settings.profileStartup.available(in: profiles.profiles) {
        case .ask: return L10n.text("Who's playing?")
        case .last: return L10n.text("Last profile")
        case .profile(let id): return profiles.profiles.first { $0.id == id }?.name ?? ""
        }
    }

    func cycleProfile(_ step: Int) {
        let choices: [ProfileStartup] = [.ask, .last] + profiles.profiles.map { .profile($0.id) }
        let current = settings.settings.profileStartup.available(in: profiles.profiles)
        settings.settings.profileStartup = choices.stepped(from: current, step) ?? .ask
    }
}

struct SettingsProfileCardsSection: View {
    @ObservedObject var profiles: LocalProfileStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneCanvas) private var canvas

    private var cards: ProfilePageCards { profiles.active?.pageCards ?? .init() }

    var body: some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            if profiles.active != nil {
                SettingsSubheading(L10n.text("Profile page cards"))
                ForEach(cards.ordered) { card in
                    SeleneRow(card.title) {
                        HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                            SeleneCycleValue(title: orderTitle(card), value: position(card)) { move(card, by: $0) }
                            Toggle(L10n.text(card.title), isOn: Binding(get: { cards.isEnabled(card) }, set: { _ in toggle(card) }))
                                .labelsHidden()
                                .toggleStyle(SeleneToggleStyle())
                        }
                    }
                }
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: cards) { publishActions() }
        .onChange(of: profiles.active?.id) { publishActions() }
    }

    private func orderTitle(_ card: ProfilePageCard) -> String {
        L10n.format("Position: %@", [L10n.text(card.title, context: localization)], context: localization)
    }

    private func position(_ card: ProfilePageCard) -> String {
        ((cards.ordered.firstIndex(of: card) ?? 0) + 1).formatted(.number.locale(localization.formatLocale))
    }

    private func changeCards(_ change: (inout ProfilePageCards) -> Void) {
        guard var profile = profiles.active else { return }
        var updated = cards
        change(&updated)
        guard updated != cards else { return }
        profile.pageCards = updated
        if !profiles.update(profile) {
            NotificationCenter.default.post(name: .nxProfileCardsSaveFailed, object: nil)
        }
    }

    private func move(_ card: ProfilePageCard, by step: Int) { changeCards { $0.move(card, by: step) } }
    private func toggle(_ card: ProfilePageCard) { changeCards { $0.toggle(card) } }

    private func publishActions() {
        let actions: [SettingsRowAction] = profiles.active == nil ? [] : cards.ordered.map { card in
            .init(id: "profile-card-\(card.rawValue)", title: card.title, cycle: { move(card, by: $0) }) { toggle(card) }
        }
        onActions(actions)
    }
}
