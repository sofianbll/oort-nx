import AppKit
import NXLibraryCore
import ArcanePorting

extension AppViewModel {
    @MainActor private static let playersScreenSession = PlayersScreenSession()

    @MainActor private var profilesForPlayersScreen: [LocalProfile] {
        guard let localProfiles, !localProfiles.failed else { return [] }
        return localProfiles.profiles
    }

    @MainActor func playersScreen(game: PortedGame? = nil, input: Notification.Name,
                                  settingsEditor: SettingsEditor? = nil,
                                  hasSettingsDraft: Bool = false, saveSettingsDraft: (() -> Void)? = nil,
                                  canHandleInput: @escaping () -> Bool, onClose: @escaping () -> Void) -> PlayersScreenHost {
        let controller = GameControllerService.shared
        return PlayersScreenHost(model: PlayersScreenModel(session: settingsEditor?.playersSession ?? Self.playersScreenSession,
                                                           read: {
                                                               guard let editor = settingsEditor else { return try await self.readPlayerPlan() }
                                                               if !editor.hasReadPlayers {
                                                                   editor.originalPlayers = try await self.readPlayerPlan()
                                                                   editor.hasReadPlayers = true
                                                               }
                                                               return editor.settings.launcherChoices.players ?? editor.originalPlayers
                                                           }, write: { plan in
                                                               guard let editor = settingsEditor else { try await self.savePlayerPlan(plan); return }
                                                               guard editor.store.draft != nil else { throw CancellationError() }
                                                               editor.playerGrants = []
                                                               editor.settings.launcherChoices.players = plan == (editor.originalPlayers ?? PlayerPlan())
                                                                   ? editor.store.settings.launcherChoices.players : plan
                                                           }, unlock: { id, pin, plan in
                                                               guard let editor = settingsEditor else {
                                                                   return try await self.unlockPlayerProfile(id, pin: pin, for: plan)
                                                               }
                                                               guard let profile = self.profilesForPlayersScreen.first(where: { $0.id == id }),
                                                                     let grant = PlayerPlanLibrary.DraftAuthorization(profile: profile, pin: pin, plan: plan)
                                                               else { return false }
                                                               editor.playerGrants.append(grant)
                                                               return true
                                                           },
                                                           profiles: { self.profilesForPlayersScreen },
                                                           identify: controller.identify, leaseCapture: { receive in
                                                               guard canHandleInput() else { return nil }
                                                               return controller.waitForAssignment { event in
                                                                   receive(canHandleInput() && !NativeMenuCommands.shared.isTracking
                                                                       && NSApp.modalWindow == nil && NSApp.keyWindow?.attachedSheet == nil
                                                                       ? event : .cancelled)
                                                               }
                                                           }),
                                 controller: controller, input: input,
                                 canHandleInput: canHandleInput, onClose: onClose,
                                 readNotes: game.map { game in { await self.playersScreenNotes(for: game) } },
                                 hasSettingsDraft: hasSettingsDraft, saveSettingsDraft: saveSettingsDraft)
    }

    @MainActor private func playersScreenNotes(for game: PortedGame) async -> PlayersScreenHost.Notes {
        guard game.isPlayableLocally else { return .init() }
        let status = await playerLaunchStatus(for: game)
        guard let status else { return .init() }
        var names = status.profileNames
        names[1] = status.nickname
        let order = status.controllerOrder.compactMapValues {
            $0 == .unsupportedEngine ? "This game's app is too old: rebuild it to keep the order." : Self.playerOmission($0)
        }
        return .init(order: order, mode: Self.playerOmission(status.controllerMode),
                     profiles: names.compactMapValues { Self.playerOmission($0) },
                     supportsExtendedMerge: status.supportsExtendedMerge)
    }

    private static func playerOmission(_ reason: PlayersLaunchStatus.Omission?) -> String? {
        switch reason {
        case .unsupportedEngine: "This game's app is too old for this setting."
        case .environmentFile: "The game's env.txt sets this instead."
        case .environmentFileUnreadable: "The game's env.txt could not be read."
        case .gameOption: "The game's own setting takes priority."
        case .networkMode(.automatic): "Choose offline or local play to use this name."
        case .invalidNickname: "This profile name cannot be used in the game."
        case .controllerIdentityUnavailable: "The game cannot keep the order for this controller."
        case .incompatibleKeyboardSlot: "The game's keyboard setting takes this player slot."
        case .controllerInputDisabled: "The game does not read this controller."
        case .networkMode, .lockedProfile, .missingProfile, .mergeMode, .disconnectedController,
             .unconfirmedController, .invalidMergePlayer, .invalidPortrait, .portraitExportFailed, nil: nil
        }
    }
}
