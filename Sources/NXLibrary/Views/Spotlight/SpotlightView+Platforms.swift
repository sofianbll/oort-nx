import SwiftUI
import NXLibraryCore
import ArcanePorting

extension SpotlightView {
    func platforms(in games: [CatalogGame]) -> SpotlightPlatforms {
        SpotlightPlatforms(listedGames: games, preferredOrder: [.nxnative, .steam, .macShortcut])
    }

    var activePlatform: CatalogIntegration? {
        if viewModel.profileOwnsInput { return nil }
        if let platformPicker { return platformPicker.settled }
        return platformChoice
    }

    func togglePlatformPicker() {
        let owner = viewModel.playProfile
        guard !owner.blocksPlay else { return }
        if let picker = platformPicker {
            let choices = platforms(in: viewModel.visibleCatalogGames)
            let requested = choices.card(for: picker.cursor).integration
            // Closing an untouched preview must not overwrite an unavailable saved choice.
            if picker.wantsCommit {
                platformChoice = requested
                viewModel.localProfiles?.rememberSpotlightPlatform(requested, for: owner)
            }
            platformPicker = nil
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
        case .confirm, .cancel:
            togglePlatformPicker()
        default:
            break
        }
    }

    /// Coalesce rapid presses before mounting the next set of game tiles and artwork.
    func settlePlatformPreview(_ cursor: SpotlightPlatforms.Card?) async {
        guard let cursor, platformPicker?.settled != cursor.integration else { return }
        try? await Task.sleep(for: .milliseconds(240))
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
