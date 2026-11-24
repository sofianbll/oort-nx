import Foundation
import NXLibraryCore
import ArcanePorting

extension AppViewModel {
    @MainActor private static let playersScreenSession = PlayersScreenSession()

    @MainActor private var profilesForPlayersScreen: [LocalProfile] {
        guard let localProfiles, !localProfiles.failed else { return [] }
        return localProfiles.profiles
    }

    @MainActor func playersScreen(game: PortedGame? = nil, input: Notification.Name,
                                  canHandleInput: @escaping () -> Bool, onClose: @escaping () -> Void) -> PlayersScreenHost {
        let controller = GameControllerService.shared
        return PlayersScreenHost(model: PlayersScreenModel(session: Self.playersScreenSession,
                                                           read: self.readPlayerPlan, write: self.savePlayerPlan,
                                                           unlock: self.unlockPlayerProfile,
                                                           profiles: { self.profilesForPlayersScreen },
                                                           identify: controller.identify),
                                 controller: controller, input: input,
                                 canHandleInput: canHandleInput, onClose: onClose,
                                 readNotes: game.map { game in { await self.playersScreenNotes(for: game) } })
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
