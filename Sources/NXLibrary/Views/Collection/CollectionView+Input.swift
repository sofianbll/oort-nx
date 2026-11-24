import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// Collection's controller, keyboard and pointer input.
extension CollectionView {
    func handle(_ action: GamepadAction) {
        if router.sortMenu != nil {
            var next = router.sortMenu
            LibrarySortMenu.handle(action, focused: &next, choose: setSort)
            router.sortMenu = next
            return
        }
        if integrationBar != nil, profileCard == nil,
           router.handleIntegrationBar(action, profileFocused: &profileFocused, hasProfile: profile != nil) { return }
        if profileFocused {
            switch action {
            case .confirm: SpotlightTopBar.openProfile(); return
            case .navigateDown, .cancel: profileFocused = false; return
            default: profileFocused = false
            }
        }
        var moved = false
        switch action {
        case .navigateLeft, .navigateRight, .tabPrevious, .tabNext:
            if showsEmptyActions, action == .navigateLeft || action == .navigateRight {
                let next = action == .navigateRight
                moved = importFocused != next
                importFocused = next
                break
            }
            let step = action == .navigateLeft || action == .tabPrevious ? -1 : 1
            if profileCard == nil, action == .tabPrevious || action == .tabNext {
                setFilter(filter.shifted(by: step))
                return
            }
            let before = viewModel.librarySelection.selectedGameID
            let ids = games.map(\.id)
            moved = viewModel.librarySelection.moveIDs(ids, by: step) != before
        case .navigateUp:
            if profile != nil, profileCard == nil {
                profileFocused = true
                SoundEffectService.shared.play(.focus)
            }
        case .navigateDown: break
        case .jumpToStart, .jumpToEnd:
            let before = viewModel.librarySelection.selectedGameID
            let ids = games.map(\.id)
            moved = viewModel.librarySelection.jumpIDs(ids, toEnd: action == .jumpToEnd) != before
        case .rightStickPress:
            if profileCard == nil { openSort() }
        case .confirm:
            if let record = selectedCatalogGame {
                activateCatalog(record)
            } else if showsEmptyActions {
                SoundEffectService.shared.play(.click)
                if importFocused { viewModel.importExistingBuilds() }
                else { router.openAddGame() }
            }
        case .secondaryAction:
            // A Steam game's details are its Spotlight page; Collection has no Details screen for it.
            if let game = selectedGame, game.isPlayableLocally || cloud.downloadItem(for: game) != nil
                || game.isCloudSourcePlaceholder && viewModel.gamesWithFilesHere.contains(game.id) {
                router.showDetail(game.id)
            }
        case .contextAction:
            if let record = selectedCatalogGame, record.macShortcut != nil {
                viewModel.macShortcuts.showTileOptions(record)
                return
            }
            if let steam = selectedCatalogGame, steam.integration == .steam {
                SoundEffectService.shared.play(.click)
                viewModel.openSteamOptions(steam, from: .collection)
                return
            }
            if let game = selectedGame { viewModel.openGameOptions(game, from: .collection) }
        case .cancel:
            router.back()
        case .view:
            if profileCard == nil, settings.settings.viewButtonSwitches { router.setInitialRoute(.library) }
        case .search, .browseSearch:
            if profileCard == nil { router.isSearchPresented = true }
        case .menu:
            router.isMenuPresented = true
        case .menuHold:
            router.openSettings(.startUp)
        case .profiles, .controlCenter, .fullMenu:
            break // The shell owns the picker.
        }
        if moved { SoundEffectService.shared.play(.focus) }
    }

    func activateCatalog(_ record: CatalogGame) {
        router.integrationBarFocused = false
        if let native = record.nxnativeGame { play(native) }
        else if viewModel.playRouter.supports(record.integration) { SoundEffectService.shared.play(.click); viewModel.pressPlay(record) }
        else { SoundEffectService.shared.play(.click); router.showDetail(record.id) }
    }

    /// A on a cover: plays, or opens Details when the game is not built (Spotlight's rule).
    func play(_ game: PortedGame) {
        SoundEffectService.shared.play(.click)
        if cloud.downloadItem(for: game) != nil {
            viewModel.downloadCloudGame(game)
        } else if game.isPlayableLocally {
            viewModel.launchGame(game)
        } else if game.isCloudSourcePlaceholder, viewModel.gamesWithFilesHere.contains(game.id) {
            viewModel.porting.startBuild(for: game) { router.openAddGame() }
        } else {
            router.showDetail(game.id)
        }
    }

    // MARK: - Keyboard

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // An alert or sheet owns Return and Esc; consuming them here would
            // replay the action that raised the alert.
            guard !router.isMenuPresented,
                  !NativeMenuCommands.shared.isTracking,
                  !router.isSearchPresented,
                  router.route.isCollection,
                  viewModel.cloudLibraryGameID == nil,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  !viewModel.isGameOptionsOpen,
                  viewModel.gameToClose == nil,
                  viewModel.gameToRemove == nil,
                  !viewModel.shellDialogOwnsInput,
                  !viewModel.isWelcomeOpen,
                  !viewModel.showSetupCheck,
                  !router.isScreenshotViewerOpen,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText) else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            let action: GamepadAction
            switch event.keyCode {
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 125 where router.sortMenu != nil || profileFocused || router.integrationBarFocused: action = .navigateDown
            case 126: action = .navigateUp
            case 36, 49, 76: action = .confirm
            case 53: action = .cancel
            case 7: action = .secondaryAction   // X
            case 16: action = .contextAction    // Y
            case 12: action = .tabPrevious      // Q
            case 14: action = .tabNext          // E
            case 99: action = .rightStickPress  // F3: keyboard equivalent of the existing sort action
            default: return event
            }
            handle(action)
            return nil
        }
    }

    func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
