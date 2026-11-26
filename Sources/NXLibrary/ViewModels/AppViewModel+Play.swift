import Foundation
import NXLibraryCore
import ArcanePorting

extension AppViewModel {
    @MainActor var playProfile: PlayProfile {
        .init(id: localProfiles?.active?.id, isGuest: localProfiles?.guest != nil, blocksPlay: profileOwnsInput)
    }

    @MainActor func playTarget(for game: CatalogGame, resumeOnly: Bool = false) -> PlayTarget {
        let enabled = catalogSourceConfigurations.first { $0.integration == game.integration }?.isEnabled
        return PlayTarget(game: game, sourceEnabled: enabled ?? (game.integration == .nxnative), resumeOnly: resumeOnly)
    }

    @MainActor @discardableResult
    func play(_ game: CatalogGame, request: RequestID = RequestID(UUID()), resumeOnly: Bool = false,
              observe: PlayObserver? = nil) -> PlayResult {
        let result = engine.play(playTarget(for: game, resumeOnly: resumeOnly), profile: playProfile, request: request) {
            [weak self] fact in
            if fact.event == .result(.refused(.outcomeUnknown)) || fact.event == .receiptUnavailable {
                self?.reportUncertainPlay()
            }
            observe?(fact.event)
        }.admission
        if result == .refused(.outcomeUnknown) { reportUncertainPlay() }
        return result
    }

    private func reportUncertainPlay() {
        logs.append(LogEntry(level: .warning,
                             message: "Play receipt unavailable. Oort will not repeat an uncertain handoff. Use the Mac to check the app before opening it again."))
    }

    @MainActor func pressPlay(_ game: CatalogGame) {
        if game.integration == .steam, SteamPlayCoordinator.shared.handleNonPlayPress(game) { return }
        play(game)
    }

    @MainActor func launchGame(_ game: PortedGame, resumeOnly: Bool = false) {
        play(CatalogGame(nxnative: game), resumeOnly: resumeOnly)
    }
}

@MainActor struct NXNativePlayAdapter: PlayAdapter {
    unowned let app: AppViewModel
    let source = CatalogIntegration.nxnative

    func availability(of target: PlayTarget) -> PlayAvailability {
        guard case .available = target.installationAvailability, let installation = target.installation else {
            return target.installationAvailability
        }
        return FileManager.default.fileExists(atPath: installation.contentURL.path) ? .available : .unavailable(.installationMissing)
    }

    func artifact(of target: PlayTarget) -> String? {
        target.game.nxnativeGame.flatMap { NativePlayTarget($0.url)?.artifact }
    }

    func admit(_ target: PlayTarget, profile: PlayProfile, gesture: PlayGesture) -> PlayResult {
        app.preparePortedPlay(target, profile: profile, gesture: gesture)
    }
}
