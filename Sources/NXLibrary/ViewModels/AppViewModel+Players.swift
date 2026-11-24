import Foundation
import NXLibraryCore
import ArcanePorting

extension AppViewModel {
    private static let playerPlanLibrary = PlayerPlanLibrary(
        url: AppData.supportRoot.appendingPathComponent("players.json"))

    @MainActor func readPlayerPlan() async throws -> PlayerPlan? {
        try await Self.playerPlanLibrary.load()
    }

    @MainActor func savePlayerPlan(_ plan: PlayerPlan) async throws {
        try await Self.playerPlanLibrary.save(plan)
    }

    @MainActor func unlockPlayerProfile(_ id: UUID, pin: String, for plan: PlayerPlan) async throws -> Bool {
        guard let profile = playerProfiles.first(where: { $0.id == id }) else { return false }
        return try await Self.playerPlanLibrary.authorize(profile, pin: pin, for: plan)
    }

    @MainActor func playerLaunchStatus(for game: PortedGame) async -> PlayersLaunchStatus? {
        guard let titleID = game.titleId, !titleID.isEmpty else { return nil }
        let explicit = playProfile.isGuest ? NextendoLaunch.guestEnvironment() :
            runtimeSettings.gameSettings(for: game)?.multiplayerLaunch(
                settings: settingsStore?.settings ?? AppSettings(), adapters: .current()).environment ?? [:]
        return await preparePlayers(for: game, titleID: titleID, environment: explicit, preview: true).status
    }

    @MainActor func preparePlayers(for game: PortedGame, titleID: String, environment: [String: String],
                                   mergePlayer: Int = 1, preview: Bool = false) async -> PlayersLaunch {
        let path = setup.nxnativePath
        let ancestry = path.isEmpty ? nil : EngineAncestry(runner: SystemCommandRunner(), engineFolder: URL(fileURLWithPath: path))
        return await PlayersLaunch.prepare(
            library: Self.playerPlanLibrary, app: game.url, titleID: titleID, explicit: environment,
            profiles: playerProfiles, ancestry: ancestry, mergePlayer: mergePlayer, liveControllers: {
                let connected = GameControllerService.shared.connectedControllers.map {
                    ConnectedPlayerController(id: $0.id, stableID: $0.stableID, modelKey: $0.modelKey)
                }
                let fingerprints = PlayerPadFingerprint.liveHID { serial, vendor, product in
                    ControllerHardwareID.make(serial: serial, bluetoothAddress: nil, vendor: vendor, product: product,
                                              salt: ControllerHardwareID.installationSalt)
                }
                return (connected, fingerprints)
            }, avatarSymbols: ProfilePortrait.symbols, portraitDirectory: preview ? nil : FileManager.default.temporaryDirectory)
    }

    @MainActor private var playerProfiles: [LocalProfile] {
        guard let localProfiles, !localProfiles.failed else { return [] }
        return localProfiles.profiles
    }
}
