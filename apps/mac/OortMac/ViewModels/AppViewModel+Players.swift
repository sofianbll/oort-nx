import Combine
import Foundation
import GameController
import OortLibrary
import ArcanePorting

extension AppViewModel {
    private static let playerPlanLibrary = PlayerPlanLibrary(
        url: AppData.supportRoot.appendingPathComponent("players.json"))
    @MainActor private static var playerEngineProofs: [String: EngineAncestry] = [:]
    @MainActor private static let playerPads = PlayerLaunchPadCache()

    @MainActor private static func playerEngineProof(for path: String) -> EngineAncestry? {
        guard !path.isEmpty else { return nil }
        if let kept = playerEngineProofs[path] { return kept }
        let proof = EngineAncestry(runner: SystemCommandRunner(), engineFolder: URL(fileURLWithPath: path))
        playerEngineProofs[path] = proof
        return proof
    }

    static func warmPlayerEngines(_ apps: [URL], path: String) async {
        guard !Task.isCancelled, let proof = await playerEngineProof(for: path) else { return }
        for app in apps {
            guard !Task.isCancelled else { return }
            await PlayersLaunch.warmEngine(in: app, ancestry: proof)
        }
    }

    @MainActor func watchPlayerPads() {
        Self.playerPads.watch(GameControllerService.shared)
    }

    @MainActor func readPlayerPlan() async throws -> PlayerPlan? {
        try await Self.playerPlanLibrary.load(committed: settingsStore?.settings.launcherChoices.players)
    }

    @MainActor func savePlayerPlan(_ plan: PlayerPlan) async throws {
        if let store = settingsStore, store.settings.launcherChoices.players != nil {
            var change = AppSettingsDraft(store.settings, fields: [
                .init("playerPlan", \.launcherChoices.players) { _ in "" }
            ])
            change.values.launcherChoices.players = plan
            try store.commit(change)
            _ = try await Self.playerPlanLibrary.load(committed: plan)
        } else {
            try await Self.playerPlanLibrary.save(plan)
        }
    }

    @MainActor func unlockPlayerProfile(_ id: UUID, pin: String, for plan: PlayerPlan) async throws -> Bool {
        guard let profile = playerProfiles.first(where: { $0.id == id }) else { return false }
        return try await Self.playerPlanLibrary.authorize(profile, pin: pin, for: plan,
                                                          committed: settingsStore?.settings.launcherChoices.players)
    }

    @MainActor func acceptPlayerDraftGrants(_ grants: [PlayerPlanLibrary.DraftAuthorization], plan: PlayerPlan) async {
        guard settingsStore?.settings.launcherChoices.players == plan else { return }
        await Self.playerPlanLibrary.accept(grants, committed: plan, profiles: playerProfiles)
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
        let ancestry = Self.playerEngineProof(for: path)
        if preview, let ancestry {
            await PlayersLaunch.warmEngine(in: game.url, ancestry: ancestry)
        } else if let ancestry {
            // A new or replaced bundle may not be in the startup warm-up yet. Never wait on Play.
            let app = game.url
            Task.detached(priority: .utility) { await PlayersLaunch.warmEngine(in: app, ancestry: ancestry) }
        }
        return await PlayersLaunch.prepare(
            library: Self.playerPlanLibrary, app: game.url, titleID: titleID, explicit: environment,
            profiles: playerProfiles, ancestry: ancestry, mergePlayer: mergePlayer, liveControllers: {
                Self.playerPads.snapshot(GameControllerService.shared.connectedControllers)
            }, avatarSymbols: ProfilePortrait.symbols, portraitDirectory: preview ? nil : FileManager.default.temporaryDirectory,
            committedPlan: settingsStore?.settings.launcherChoices.players)
    }

    @MainActor private var playerProfiles: [LocalProfile] {
        guard let localProfiles, !localProfiles.failed else { return [] }
        return localProfiles.profiles
    }
}

/// Main reads only the roster and the published hashes. Stale scans cannot be used after a topology change.
@MainActor private final class PlayerLaunchPadCache {
    private var watch: AnyCancellable?
    private var signature: [ConnectedPlayerController] = []
    private var fingerprints: [String: String] = [:]
    private var scan: Task<Void, Never>?
    private var revision = 0

    func watch(_ controller: GameControllerService) {
        guard watch == nil else { return }
        watch = controller.$connectedControllers.sink { [weak self] in self?.update($0) }
    }

    func snapshot(_ controllers: [ConnectedController]) -> ([ConnectedPlayerController], [String: String]) {
        let pads = observations(controllers)
        return (pads, pads == signature ? fingerprints : [:])
    }

    private func observations(_ controllers: [ConnectedController]) -> [ConnectedPlayerController] {
        controllers.map { .init(id: $0.id, stableID: $0.stableID, modelKey: $0.modelKey) }
    }

    private func update(_ controllers: [ConnectedController]) {
        let next = observations(controllers)
        guard next != signature else { return }
        signature = next
        fingerprints = [:]
        scan?.cancel()
        revision += 1
        guard next.contains(where: { $0.stableID != nil }) else { return }
        let ticket = revision
        let names = Set(GCController.controllers().filter { $0.extendedGamepad != nil }.compactMap(\.vendorName))
        let salt = ControllerHardwareID.installationSalt
        scan = Task(priority: .utility) { [weak self] in
            let result = await Task.detached(priority: .utility) {
                PlayerPadFingerprint.liveHID(gameControllerNames: names) { serial, vendor, product in
                    ControllerHardwareID.make(serial: serial, bluetoothAddress: nil, vendor: vendor, product: product, salt: salt)
                }
            }.value
            guard let self, !Task.isCancelled, revision == ticket else { return }
            fingerprints = result
        }
    }
}
