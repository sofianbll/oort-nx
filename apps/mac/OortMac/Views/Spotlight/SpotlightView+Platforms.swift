import SwiftUI
import OortLibrary
import NxnativeAdapter

extension SpotlightView {
    /// What the platform preview waits on. A probe counts only the time its screen runs, not the time it spends capturing.
    @MainActor static var platformSettleClock: any Clock<Duration> = ContinuousClock()

    func platforms(in games: [CatalogGame]) -> SpotlightPlatforms {
        SpotlightPlatforms(listedGames: games, preferredOrder: [.nxnative, .steam, .macShortcut])
    }

    var activePlatform: CatalogIntegration? {
        if viewModel.profileOwnsInput { return nil }
        if let platformPicker { return platformPicker.settled }
        return platformChoice
    }

    /// `keeping` false leaves the choice as it was when the ribbon opened (B).
    func togglePlatformPicker(keeping: Bool = true) {
        let owner = viewModel.playProfile
        guard !owner.blocksPlay else { return }
        if let picker = platformPicker {
            let choices = platforms(in: viewModel.visibleCatalogGames)
            let requested = choices.card(for: picker.cursor).integration
            // Closing an untouched preview must not overwrite an unavailable saved choice.
            if keeping, picker.wantsCommit {
                platformChoice = requested
                viewModel.localProfiles?.rememberSpotlightPlatform(requested, for: owner)
            }
            platformPicker = nil
            if keeping { platformPress += 1 }
        } else {
            platformPicker = SpotlightPlatformPicker(platformChoice, in: platforms(in: viewModel.visibleCatalogGames))
        }
        router.integrationBarFocused = false
        profileFocused = false
        mutate { $0.select(.platform) }
        SoundEffectService.shared.play(.click)
    }

    func handlePlatformPicker(_ action: GamepadAction) {
        guard !viewModel.profileOwnsInput else { return }
        switch action {
        case .navigateUp, .navigateDown:
            let choices = platforms(in: viewModel.visibleCatalogGames)
            if platformPicker?.move(by: action == .navigateUp ? -1 : 1, in: choices) == true {
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            togglePlatformPicker()
        case .cancel:
            togglePlatformPicker(keeping: false)
        default:
            break
        }
    }

    /// A click on a card below the frame chooses it at once.
    func pickPlatform(_ card: SpotlightPlatforms.Card) {
        guard platformPicker != nil else { return }
        platformPicker?.move(to: card.integration, in: platforms(in: viewModel.visibleCatalogGames))
        togglePlatformPicker()
    }

    /// Coalesce rapid presses before mounting the next set of game tiles and artwork.
    func settlePlatformPreview(_ cursor: SpotlightPlatforms.Card?) async {
        guard let cursor, platformPicker?.settled != cursor.integration else { return }
        try? await Self.platformSettleClock.sleep(for: .milliseconds(240))
        guard !Task.isCancelled, !viewModel.profileOwnsInput,
              let picker = platformPicker, picker.cursor == cursor.integration else { return }
        platformPicker?.settle()
    }

    /// A search result or notification must still reach a game outside this rail's scope.
    func showPlatformContaining(_ id: UUID) {
        platformPicker = nil
        let games = viewModel.visibleCatalogGames
        let selected = platforms(in: games).card(for: activePlatform).integration
        if let selected, games.contains(where: { $0.id == id && !$0.isHidden && $0.integration != selected }) {
            platformChoice = nil
        }
    }
}
