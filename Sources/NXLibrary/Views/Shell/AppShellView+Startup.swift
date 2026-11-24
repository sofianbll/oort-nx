import SwiftUI
import ArcanePorting
import AppKit
import Combine
import NXLibraryCore

/// What the shell starts when it appears, and the first launch's choices and the last home screen.
extension AppShellView {
    func startRuntime() {
        AppDelegate.requestGuestQuit = requestGuestQuit
        if profiles.failed {
            viewModel.showSettingsNotice(title: L10n.text("Profiles could not be loaded."),
                                         message: L10n.text("Defaults are in use. Your previous settings file has been kept."))
        }
        presentLegacyNotice()
        askToMoveIfTranslocated()
        viewModel.playSessionStore = playSessions
        playSessions.profileID = profiles.active?.id == profiles.originalID ? nil : profiles.active?.id
        viewModel.settingsStore = settings
        SoundEffectService.shared.bind(to: settings)
        // The opening's boot cue, with Spotlight's entrance (Settings → Start-up → Entrance animation).
        if settings.settings.introAnimation { SoundEffectService.shared.play(.boot) }
        artwork.trimCache()
        viewModel.refreshBoxArtIndex()
        if settings.settings.checkEngineAtLaunch && !AppData.profile.isDevelopment { SetupCheckModel.checkAtLaunch(viewModel: viewModel) }
        runningGames.start(sessions: playSessions, engineFolder: { [weak setup] in setup?.nxnativePath ?? "" })
        runningGames.setGames(viewModel.libraryGames)
        viewModel.runningGameMonitor = runningGames
        // Steam's playtime first: a Steam game already running starts a session at once, and trimming needs Steam's last values.
        SteamPlaytimeCoordinator.shared.setGames(viewModel.catalogGames, sources: viewModel.catalogSourceConfigurations)
        SteamPlaytimeCoordinator.shared.start(sessions: playSessions)
        SteamAchievementsStore.shared.setSources(viewModel.catalogSourceConfigurations)
        // After the nxnative reconcile, which closes a Steam session left by a restart at its last heartbeat.
        SteamPlayCoordinator.shared.setGames(viewModel.catalogGames, sources: viewModel.catalogSourceConfigurations)
        SteamPlayCoordinator.shared.nativeGames = runningGames
        SteamPlayCoordinator.shared.isLaunchScreenShowing = { [weak viewModel] in viewModel?.launchOverlay != nil }
        SteamPlayCoordinator.shared.profileAllowsPlay = { [weak viewModel] in
            guard let viewModel, !viewModel.profileOwnsInput else { return false }
            guard viewModel.localProfiles?.guest == nil else {
                viewModel.showSettingsNotice(title: L10n.text("Guest"),
                                             message: L10n.text("Steam saves cannot be isolated for a guest."))
                return false
            }
            return true
        }
        SteamPlayCoordinator.shared.start(sessions: playSessions, settings: settings)
        viewModel.installPendingBuilds()
        viewModel.appIcon.syncPendingAppIcons()
        closeGameWatch = runningGames.$runningGameIDs.sink { [weak viewModel] ids in
            guard let viewModel else { return }
            viewModel.runningGameCount = ids.count
            // A game that quit lets the build that waited for it go in (after this change is published).
            DispatchQueue.main.async {
                viewModel.cloudLibrary.appInstallWake?.yield(())
                viewModel.porting.scheduleNextBuild()
                viewModel.installPendingBuilds()
                // An icon chosen while the game ran goes on once it quits.
                viewModel.appIcon.syncPendingAppIcons()
            }
            // The game under Close Game quit by itself: its confirmation has nothing left to close.
            guard let game = viewModel.gameToClose, !ids.contains(game.id) else { return }
            viewModel.dismissCloseGame()
        }
        viewModel.router = router
        updater.blockedReason = { [weak viewModel, weak runningGames] in
            guard let viewModel else { return nil }
            if viewModel.isBuilding || viewModel.isCheckingCloudBuild { return L10n.text("After the porting") }
            if viewModel.cloudLibrary.isWorking { return L10n.text("After the cloud transfer") }
            if viewModel.isCleaningStorage { return L10n.text("After storage cleanup") }
            if viewModel.launchingGameId != nil { return L10n.text("After the game starts") }
            if viewModel.saveGate.hasActiveOperations { return L10n.text("After the save operation") }
            if let ids = runningGames?.runningGameIDs, let id = ids.first {
                let name = viewModel.libraryGames.first { $0.id == id }?.name ?? "the game"
                return L10n.format("After you quit %@", [String(describing: name)])
            }
            return nil
        }
        updater.acquireInstallLease = { [weak viewModel, weak runningGames] in
            guard let viewModel, !viewModel.isBuilding, !viewModel.isCheckingCloudBuild,
                  !viewModel.cloudLibrary.isWorking, !viewModel.cloudLibrary.isChangingConnection,
                  !viewModel.isCleaningStorage, viewModel.launchingGameId == nil,
                  runningGames?.runningGameIDs.isEmpty == true,
                  let token = viewModel.saveGate.beginAppUpdate() else { return nil }
            let gate = viewModel.saveGate
            viewModel.isUpdatingApp = true
            return { [weak viewModel] in
                gate.endAppUpdate(token: token)
                viewModel?.isUpdatingApp = false
            }
        }
        updater.checkAtLaunch(enabled: settings.settings.checkAppUpdatesAtLaunch)
        installGestureKeyMonitor()
        GameControllerService.shared.onAction = { [weak viewModel, weak router] action in
            guard let viewModel, let router else { return }
            guard !nativeMenus.isTracking, !nativeDialogOwnsInput, viewModel.launchOverlay == nil else { return }
            if action == .profiles, !launcherIsFrontmost { return }
            if viewModel.cloudQuitRequested {
                cloudQuitInput(action)
                return
            }
            if viewModel.showSetupCheck {
                // The Setup check owns the controller; Menu does nothing there (as in Selene).
                NotificationCenter.default.post(name: .nxSetupCheckGamepadAction, object: action)
                return
            }
            if showsSettingsNotice {
                settingsNoticeInput(action)
                return
            }
            if showsWelcome, !showsInstallFailure, viewModel.gameToClose == nil, viewModel.gameToRemove == nil,
               !showsUpdateOffer {
                NotificationCenter.default.post(name: .nxArcaneWelcomeGamepadAction, object: action)
                return
            }
            if showsInstallFailure {
                installFailureInput(action)
                return
            }
            if viewModel.gameToClose != nil {
                closeGameInput(action)
                return
            }
            if viewModel.gameToRemove != nil {
                removeGameInput(action)
                return
            }
            if showsUpdateOffer {
                updateOfferInput(action)
                return
            }
            if viewModel.cloudLibraryGameID != nil {
                NotificationCenter.default.post(name: .nxCloudLibraryGamepadAction, object: action)
                return
            }
            if viewModel.profileOwnsInput {
                if action == .profiles { toggleProfilePicker() }
                else { postProfileAction(action) }
                return
            }
            if action == .profiles {
                guard !router.isScreenshotViewerOpen else { return }
                if router.route == .library, !router.isMenuPresented, !router.isSearchPresented, !viewModel.isGameOptionsOpen {
                    // Spotlight still owns its entrance: ask it before covering the screen.
                    NotificationCenter.default.post(name: .nxSpotlightGamepadAction, object: action)
                } else {
                    toggleProfilePicker()
                }
                return
            }
            if router.isMenuPresented {
                menuInput(action)
                return
            }
            if viewModel.isGameOptionsOpen {
                guard action != .menu, action != .menuHold else { return }
                NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: action)
                return
            }
            if router.isSearchPresented, isHomeRoute {
                NotificationCenter.default.post(name: .nxFindGameGamepadAction, object: action)
                return
            }
            if router.isScreenshotViewerOpen, action == .menu || action == .menuHold { return }
            switch router.route {
            case .library:
                NotificationCenter.default.post(name: .nxSpotlightGamepadAction, object: action)
            case .collection, .profileCollection:
                NotificationCenter.default.post(name: .nxCollectionGamepadAction, object: action)
            case .profile:
                postProfileAction(action)
            case .detail:
                NotificationCenter.default.post(name: .nxDetailGamepadAction, object: action)
            case .settings:
                NotificationCenter.default.post(name: .nxSettingsGamepadAction, object: action)
            case .integrations:
                if action == .menu { router.isMenuPresented = true }
                else if action == .menuHold { router.openSettings(.startUp) }
                else { NotificationCenter.default.post(name: .nxIntegrationsAction, object: action) }
            case .addGame:
                NotificationCenter.default.post(name: .nxAddGameGamepadAction, object: action)
            case .gameInbox:
                if action == .menu { router.isMenuPresented = true }
                else if action == .menuHold { router.openSettings(.startUp) }
                else { NotificationCenter.default.post(name: .nxGameInboxAction, object: action) }
            case .console:
                if action == .menu {
                    router.isMenuPresented = true
                } else if action == .menuHold {
                    router.openSettings(.startUp)
                } else {
                    NotificationCenter.default.post(name: .nxConsoleGamepadAction, object: action)
                }
            }
        }
    }

    /// Remembers which home screen was used last, for Start on → Last used.
    func recordLastHome(_ route: AppRoute) {
        let home: StartScreen
        switch route {
        case .library: home = .spotlight
        case .collection: home = .collection
        default: return
        }
        if settings.settings.lastHome != home { settings.settings.lastHome = home }
    }

    /// Open library on the first launch's `found` page; the Steam switch applies with the finish.
    func finishFromFound(importPorted: Bool) {
        guard viewModel.showSetupCheck, viewModel.firstRunSetup.page == .found else { return }
        viewModel.finishFromFound(importPorted: importPorted)
        router.navigate(to: .library)
    }

    func chooseFirstGame(usingFolder: Bool) {
        guard viewModel.showSetupCheck,
              viewModel.firstRunSetup.page == .games else { return }
        let defaults = settings.settings.gameDefaults
        let picked = usingFolder ? viewModel.porting.selectGameFolder(startingNewGameWith: defaults)
            : viewModel.porting.selectGameFiles(startingNewGameWith: defaults)
        guard picked else { return }
        setupSourceEntryID = UUID()
        viewModel.completeSetup()
        router.openAddGame()
    }

    func openFreshAddGame() {
        if router.route == .addGame, !viewModel.isBuilding {
            viewModel.porting.startNewAddGame(defaults: settings.settings.gameDefaults)
        } else {
            router.openAddGame()
        }
    }
}
