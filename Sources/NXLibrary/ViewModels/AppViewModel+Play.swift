import Foundation
import NXLibraryCore
import ArcanePorting

extension AppViewModel {
    @MainActor var playProfile: PlayProfile {
        .init(id: localProfiles?.active?.id, isGuest: localProfiles?.guest != nil, blocksPlay: profileOwnsInput)
    }

    @MainActor func playTarget(for game: CatalogGame) -> PlayTarget {
        let enabled = catalogSourceConfigurations.first { $0.integration == game.integration }?.isEnabled
        return PlayTarget(game: game, sourceEnabled: enabled ?? (game.integration == .nxnative))
    }

    @MainActor @discardableResult
    func play(_ game: CatalogGame, observe: PlayObserver? = nil) -> PlayResult {
        playRouter.play(playTarget(for: game), profile: playProfile, observe: observe)
    }

    @MainActor func pressPlay(_ game: CatalogGame) {
        if game.integration == .steam, SteamPlayCoordinator.shared.handleNonPlayPress(game) { return }
        play(game)
    }

    @MainActor func launchGame(_ game: PortedGame) {
        play(CatalogGame(nxnative: game))
    }
}

@MainActor struct NXNativePlayConnector: PlayConnector {
    unowned let app: AppViewModel
    let source = CatalogIntegration.nxnative

    func availability(of target: PlayTarget) -> PlayAvailability {
        guard case .available = target.installationAvailability, let installation = target.installation else {
            return target.installationAvailability
        }
        return FileManager.default.fileExists(atPath: installation.contentURL.path) ? .available : .unavailable(.installationMissing)
    }

    func play(_ target: PlayTarget, profile: PlayProfile, observe: PlayObserver?) -> PlayResult {
        app.playNXNative(target, profile: profile, observe: observe)
    }
}
