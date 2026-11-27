import SwiftUI
import NXLibraryCore
import ArcanePorting

/// Library → Games: how every game launches and closes, Surprise me and the hidden games.
struct SettingsLibraryGamesSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: SettingsEditor
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    /// Games hidden from Game options, by name (the library keeps them sorted).
    private var hiddenGames: [PortedGame] {
        viewModel.libraryGames.filter(\.isHidden)
    }

    private func unhide(_ game: PortedGame) {
        SoundEffectService.shared.play(.click)
        viewModel.toggleHidden(game)
    }

    private var surprisePoolTitle: String {
        switch settings.settings.surprisePool {
        case .installed: return "Installed"
        case .notPlayed: return "Not played yet"
        case .all: return "All games"
        }
    }

    var body: some View {
        OortSettingsGroup {
            SettingsSubheading(L10n.text("All games"))

            SeleneCycleRow("Sort games",
                           subtitle: "Order of games in Spotlight and Collection.",
                           value: settings.settings.librarySort.title, cycle: stepSort)

            SeleneCycleRow("Badge position",
                           subtitle: "The corner of game covers that holds the badge.",
                           value: settings.settings.tileBadgePosition.titleKey, cycle: stepBadgePosition)

            SeleneCycleRow("Launch screen style",
                           subtitle: "Artwork layout",
                           value: settings.settings.launchStyle.title) { step in
                settings.settings.launchStyle = settings.settings.launchStyle.stepped(step)
            }

            SeleneToggleRow("Launch screen motion",
                            subtitle: "Artwork drift",
                            isOn: $settings.settings.launchMotion)

            SeleneCycleRow("Launch screen shade",
                           subtitle: "Launch brightness",
                           value: settings.settings.launchShade.title) { step in
                settings.settings.launchShade = settings.settings.launchShade.stepped(step)
            }

            SeleneToggleRow("Session card",
                            subtitle: "Your playtime when a game closes",
                            info: "When you close a game, a card shows how long you played this time and in total. Sessions under 10 seconds show none.",
                            isOn: $settings.settings.showsSessionCard)

            SeleneCycleRow("Surprise me pool",
                           subtitle: "Which games Surprise me picks from.",
                           value: surprisePoolTitle) { step in
                settings.settings.surprisePool = settings.settings.surprisePool.stepped(step)
            }

            SettingsSubheading(L10n.text("Hidden game apps"))

            if hiddenGames.isEmpty {
                Text(L10n.text("No hidden game apps. Hide one from its Game options; it comes back here."))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, canvas.u(SeleneTokens.Space.large))
            } else {
                ForEach(hiddenGames) { game in
                    SeleneButtonRow(game.name, id: "hidden-\(game.id)",
                                    subtitle: "Out of Spotlight, Collection, Surprise me and search.", verbatimTitle: true,
                                    buttonTitle: "Show") { unhide(game) }
                }
            }

        }
        .onAppear(perform: publishActions)
        .onChange(of: hiddenGames.map(\.id)) { publishActions() }
    }

    private func publishActions() {
        let hidden = hiddenGames.map { game in
            SettingsRowAction(id: "hidden-\(game.id)", title: game.name, rowID: "hidden-\(game.id)") { unhide(game) }
        }
        onActions([.value("librarySort", "Sort games", cycle: stepSort)] + launchActions + hidden)
    }

    private func stepSort(_ step: Int) {
        settings.settings.librarySort = settings.settings.librarySort.stepped(step)
    }

    private func stepBadgePosition(_ step: Int) {
        settings.settings.tileBadgePosition = settings.settings.tileBadgePosition.stepped(step)
    }

    private var launchActions: [SettingsRowAction] {
        [
            .value("tileBadgePosition", "Badge position", cycle: stepBadgePosition),
            .value("launchStyle", "Launch screen style") { step in
                settings.settings.launchStyle = settings.settings.launchStyle.stepped(step)
            },
            .init(id: "launchMotion", title: L10n.text("Launch screen motion"), rowID: "Launch screen motion") {
                settings.settings.launchMotion.toggle()
            },
            .value("launchShade", "Launch screen shade") { step in
                settings.settings.launchShade = settings.settings.launchShade.stepped(step)
            },
            .init(id: "showsSessionCard", title: L10n.text("Session card"), rowID: "Session card") {
                settings.settings.showsSessionCard.toggle()
            },
            .value("surprisePool", "Surprise me pool") { step in
                settings.settings.surprisePool = settings.settings.surprisePool.stepped(step)
            }
        ]
    }
}
