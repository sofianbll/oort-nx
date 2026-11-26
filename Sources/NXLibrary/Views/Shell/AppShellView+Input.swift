import SwiftUI
import AppKit
import Combine
import NXLibraryCore

/// Keyboard equivalents of the controller gestures, the menu's input and its actions.
extension AppShellView {
    func activityCenterInput(_ action: GamepadAction, router: AppRouter, viewModel: AppViewModel) {
        guard var focus = router.activityCenterFocus else { return }
        let rows = ActivityCenterView.rows(viewModel)
        let current = ActivityCenterView.selectedRow(focus, in: rows)
        switch action {
        case .navigateUp, .navigateDown:
            if focus.selected != nil { focus.selected = current }
            focus.move(by: action == .navigateUp ? -1 : 1, in: rows)
            router.activityCenterFocus = focus
            if focus.selected != current { SoundEffectService.shared.play(.focus) }
        case .confirm: openActivityCenterRow(current, router: router, viewModel: viewModel)
        case .secondaryAction: cancelActivityCenterRow(current, viewModel: viewModel)
        case .cancel: router.menuStep(.back)
        default: break
        }
    }

    func activityCenterKey(_ keyCode: UInt16) -> GamepadAction? {
        switch keyCode {
        case 12: return .tabPrevious
        case 14: return .tabNext
        case 125: return .navigateDown
        case 126: return .navigateUp
        case 36, 76, 49: return .confirm
        case 7, 51: return .secondaryAction // X / Delete
        case 53: return .cancel
        default: return nil
        }
    }

    func openActivityCenterRow(_ row: ActivityCenterFocus.Row, router: AppRouter, viewModel: AppViewModel) {
        guard ActivityCenterView.rows(viewModel).contains(row) else { return }
        switch row {
        case .result(let id): viewModel.retryActivity(id)
        case .cloud, .queuedCloud: viewModel.activateCloudActivityRow(row)
        case .undo: if viewModel.undoOffers.perform() { SoundEffectService.shared.play(.click) }
        case .clearAll: viewModel.clearActivity()
        case .refresh: retryRefresh(router: router, viewModel: viewModel)
        default:
            guard row.opensPorting else { return }
            router.closeMenu()
            router.openAddGame()
        }
    }

    func cancelActivityCenterRow(_ row: ActivityCenterFocus.Row, viewModel: AppViewModel) {
        guard ActivityCenterView.rows(viewModel).contains(row) else { return }
        switch row {
        case .build where viewModel.isBuilding && !viewModel.porting.isCancellingBuild && !viewModel.porting.isInstallingBuild:
            viewModel.porting.cancelBuild()
        case .queuedBuild(let id): viewModel.porting.cancelQueuedBuild(id)
        case .cloud(let token): viewModel.cancelActiveCloudLibrary(token)
        case .queuedCloud(let token): viewModel.cancelQueuedCloudLibrary(token)
        case .move(let id): viewModel.cancelLibraryMove(id)
        case .result(let id): viewModel.clearActivity(id)
        case .refresh:
            if viewModel.libraryRefresh.current?.isRunning == true { viewModel.libraryRefresh.cancel() }
            else { viewModel.libraryRefresh.clear() }
        default: break
        }
    }

    private func retryRefresh(router: AppRouter, viewModel: AppViewModel) {
        let refresh = viewModel.libraryRefresh
        guard refresh.current?.isRunning == false, let failure = refresh.cloudFailure, failure.action != .retry else {
            return viewModel.refreshLibrary()
        }
        router.closeMenu()
        viewModel.recoverCloud(failure.action) { viewModel.refreshLibrary() }
    }

    func cloudQuitInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft ? .left : .right
            if cloudQuitFocus != next {
                cloudQuitFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm: finishCloudQuit(cloudQuitFocus == .confirm)
        case .cancel: finishCloudQuit(false)
        default: break
        }
    }

    private func cloudQuitKey(_ keyCode: UInt16) {
        switch keyCode {
        case 123: cloudQuitInput(.navigateLeft)
        case 124: cloudQuitInput(.navigateRight)
        case 36, 76, 49: cloudQuitInput(.confirm)
        case 53: cloudQuitInput(.cancel)
        default: break
        }
    }

    /// App-level monitor for the keyboard equivalents of the controller gestures.
    /// Handles V, Cmd+F, Cmd+, Home and End outside the shell's dialogs.
    func installGestureKeyMonitor() {
        guard gestureKeyMonitor == nil else { return }
        gestureKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [router, viewModel] event in
            if nativeMenus.isTracking { return event }
            // An alert or another window's sheet owns Return and Esc.
            if nativeDialogOwnsInput
                || event.window?.attachedSheet != nil || event.window?.isSheet == true {
                return event
            }
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            // The launch screen is drawn over everything: only Esc reaches it, and nothing acts under it.
            if viewModel.launchOverlay != nil {
                guard mods.isEmpty else { return event }
                if event.keyCode == 53 { GameControllerService.shared.onAction?(.cancel) }
                return nil
            }
            if viewModel.cloudQuitRequested {
                guard mods.isEmpty else { return event }
                cloudQuitKey(event.keyCode)
                return nil
            }
            if viewModel.noticeFocus.isActive, !leavesNoticesRoom { viewModel.noticeFocus.leave() }
            if viewModel.noticeFocus.isActive, mods.isEmpty {
                if let action = noticeKeyAction(event.keyCode), !event.isARepeat || action != .confirm {
                    GameControllerService.shared.onAction?(action)
                }
                return nil
            }
            // Tab reaches the notice on screen. Full Keyboard Access already does, and a text field keeps its own Tab.
            if event.keyCode == 48, mods.isEmpty, !NSApp.isFullKeyboardAccessEnabled, !noticeKeys.isEmpty,
               !(event.window?.firstResponder is NSText) {
                if !event.isARepeat { chooseNotice() }
                return nil
            }
            // The screenshot viewer owns the keyboard (its own monitor handles it); no navigating underneath.
            if router.isScreenshotViewerOpen { return event }
            // The Setup check and the welcome take the keyboard: arrows, Return, Space and Esc go to them.
            if viewModel.showSetupCheck || (showsWelcome && !showsSettingsNotice && !showsInstallFailure
                                            && !showsUpdateOffer && viewModel.gameToClose == nil
                                            && viewModel.gameToRemove == nil) {
                if viewModel.isGuidedSetupOpen, event.keyCode == 48, mods.isEmpty || mods == [.shift] {
                    GameControllerService.shared.onAction?(mods.isEmpty ? .navigateDown : .navigateUp)
                    return nil
                }
                guard mods.isEmpty, !(event.window?.firstResponder is NSText) else { return event }
                let setupAction: GamepadAction?
                switch event.keyCode {
                case 123: setupAction = .navigateLeft
                case 124: setupAction = .navigateRight
                case 125: setupAction = .navigateDown
                case 126: setupAction = .navigateUp
                case 36, 76, 49: setupAction = .confirm
                case 53: setupAction = .cancel
                default: setupAction = nil
                }
                guard let setupAction else { return nil }
                if showsSettingsNotice && setupAction == .confirm && event.isARepeat { return nil }
                GameControllerService.shared.onAction?(setupAction)
                return nil
            }
            // The Close Game and Delete confirmations take the keyboard: arrows, Return, Space and Esc go to them.
            if isCloseGameOpen, mods.isEmpty {
                let closeAction: GamepadAction?
                switch event.keyCode {
                case 123: closeAction = .navigateLeft
                case 124: closeAction = .navigateRight
                case 125: closeAction = showsUpdateOffer || showsSettingsNotice || viewModel.cloudLibraryGameID != nil ? .navigateDown : nil
                case 126: closeAction = showsUpdateOffer || showsSettingsNotice || viewModel.cloudLibraryGameID != nil ? .navigateUp : nil
                case 36, 76, 49: closeAction = .confirm
                case 53: closeAction = .cancel
                default: closeAction = nil
                }
                if let closeAction {
                    if showsSettingsNotice && closeAction == .confirm && event.isARepeat { return nil }
                    GameControllerService.shared.onAction?(closeAction)
                    return nil
                }
                if viewModel.cloudLibraryGameID != nil { return nil }
            }
            // The open control center takes the keyboard: arrows, Return, Space and Esc go to the menu,
            // and no screen underneath sees them.
            // Typing in a menu's text field (the Theme screen's search): keys go to the field, Esc leaves it.
            if mods == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "p" {
                if !event.isARepeat { GameControllerService.shared.onAction?(.profiles) }
                return nil
            }
            if router.isPalettePresented, !isCloseGameOpen { return paletteKey(event) }
            if viewModel.profileOwnsInput || (router.route == .profile && !router.isMenuPresented
                && !viewModel.isGameOptionsOpen && !nativeDialogOwnsInput),
               !showsWelcome, !viewModel.showSetupCheck, !isCloseGameOpen {
                return profileKey(event)
            }
            if router.isMenuPresented, router.activityCenterFocus != nil {
                guard mods.isEmpty else { return event }
                if let action = activityCenterKey(event.keyCode),
                   !event.isARepeat || action == .navigateUp || action == .navigateDown {
                    GameControllerService.shared.onAction?(action)
                }
                return nil
            }
            if router.isMenuPresented, event.window?.firstResponder is NSText, event.keyCode != 53 {
                return event
            }
            if router.isMenuPresented, mods.isEmpty {
                let menuAction: GamepadAction?
                switch event.keyCode {
                case 123: menuAction = .navigateLeft     // Left arrow
                case 124: menuAction = .navigateRight    // Right arrow
                case 125: menuAction = .navigateDown     // Down arrow
                case 126: menuAction = .navigateUp       // Up arrow
                case 36, 76, 49: menuAction = .confirm   // Return, keypad Enter, Space
                case 53: menuAction = .cancel            // Esc
                case 51: menuAction = router.isThemePickerOpen ? .contextAction : nil   // Delete: remove your own wallpaper
                case 12: menuAction = .tabPrevious                                    // Q: as LB
                case 14: menuAction = .tabNext                                        // E: as RB
                case 7: menuAction = router.isThemePickerOpen ? .secondaryAction : nil  // X: open the page
                case 16: menuAction = router.isThemePickerOpen ? .contextAction : nil   // Y: remove
                default: menuAction = nil
                }
                if let menuAction {
                    GameControllerService.shared.onAction?(menuAction)
                    return nil
                }
            }
            if !router.isMenuPresented, mods.isEmpty,
               let action = router.route == .gameInbox ? GameInboxView.keyAction(event.keyCode)
                 : router.route == .integrations ? IntegrationsView.keyAction(event.keyCode) : nil {
                if !event.isARepeat || [.navigateUp, .navigateDown, .navigateLeft, .navigateRight].contains(action) {
                    GameControllerService.shared.onAction?(action)
                }
                return nil
            }
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let typing = event.window?.firstResponder is NSText
            var action: GamepadAction?
            switch (event.keyCode, key, mods) {
            case (_, "v", []):
                if typing || !isHomeRoute { return event }
                action = .view
            case (_, "f", [.command]):              // Cmd+F
                if typing || !(isHomeRoute || router.route.isDetail) { return event }
                action = .search
            case (_, "z", [.command]):              // Cmd+Z; a text field keeps its own
                if typing || !canUndoLastChange { return event }
                if !event.isARepeat { undoLastChange() }
                return nil
            case (_, ",", [.command]):              // Cmd+,
                // Same as holding Menu. Consumed, so the menu-bar Settings command does not open Settings a second time.
                action = .menuHold
            case (115, _, []):                      // Home
                if typing { return event }
                action = .jumpToStart
            case (119, _, []):                      // End
                if typing { return event }
                action = .jumpToEnd
            default:
                return event
            }
            if let action, !event.isARepeat { GameControllerService.shared.onAction?(action) }
            return nil
        }
    }

    /// The last reversible gesture can be undone here: no dialog, launch, Setup or text field comes first.
    var canUndoLastChange: Bool { viewModel.undoOffers.offer != nil && leavesNoticesRoom }

    /// Nothing that comes first is open.
    var leavesNoticesRoom: Bool {
        !router.isMenuPresented && !router.isPalettePresented && !router.isScreenshotViewerOpen && !isCloseGameOpen && !viewModel.showSetupCheck && !showsWelcome
            && viewModel.launchOverlay == nil && !nativeDialogOwnsInput && !viewModel.profileOwnsInput && !viewModel.isGameOptionsOpen
    }

    func undoLastChange() {
        guard canUndoLastChange, viewModel.undoOffers.perform() else { return }
        SoundEffectService.shared.play(.click)
    }

    func turnOffTips() {
        settings.settings.showsTips = false
        viewModel.tips.dismiss()
    }

    /// The keys of the notice on screen, in their order.
    var noticeKeys: [() -> Void] {
        guard leavesNoticesRoom else { return [] }
        if viewModel.undoOffers.isShown { return [undoLastChange] }
        return viewModel.tips.shown == nil ? [] : [viewModel.tips.dismiss, turnOffTips]
    }

    func chooseNotice() {
        guard !viewModel.noticeFocus.isActive, !noticeKeys.isEmpty else { return }
        viewModel.noticeFocus.enter(keys: noticeKeys.count)
        SoundEffectService.shared.play(.focus)
    }

    /// The notice has the input: it moves between its keys, presses one, or gives the screen back as it was.
    func noticeInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let before = viewModel.noticeFocus
            viewModel.noticeFocus.move(by: action == .navigateLeft ? -1 : 1)
            if viewModel.noticeFocus != before { SoundEffectService.shared.play(.focus) }
        case .confirm:
            let keys = noticeKeys
            let index = viewModel.noticeFocus.index
            viewModel.noticeFocus.leave()
            if let index, keys.indices.contains(index) { keys[index]() }
        case .cancel, .notice:
            viewModel.noticeFocus.leave()
            SoundEffectService.shared.play(.back)
        default: break
        }
    }

    /// Tab and the arrows while the notice has the input; nil leaves the key alone.
    private func noticeKeyAction(_ keyCode: UInt16) -> GamepadAction? {
        switch keyCode {
        case 123: return .navigateLeft
        case 124: return .navigateRight
        case 36, 76, 49: return .confirm
        case 53, 48: return .cancel
        default: return nil
        }
    }

    func removeGestureKeyMonitor() {
        if let monitor = gestureKeyMonitor { NSEvent.removeMonitor(monitor) }
        gestureKeyMonitor = nil
    }

    /// Arrows move within the current layer; the shoulders switch icons or panels.
    /// A selects; B (or Esc) closes the open panel, then the menu. Hold Menu for Settings.
    func menuInput(_ action: GamepadAction) {
        if router.activityCenterFocus != nil, action != .tabPrevious, action != .tabNext {
            activityCenterInput(action, router: router, viewModel: viewModel)
            return
        }
        if action == .menu { return }
        // The Theme screen owns its input, including its own confirmations.
        if router.isThemePickerOpen {
            NotificationCenter.default.post(name: .nxThemePickerGamepadAction, object: action)
            return
        }
        if action == .menuHold {
            router.closeMenu()
            if case .settings = router.route { return }
            router.openSettings(.startUp)
            return
        }
        let step: MenuStep
        switch action {
        case .navigateLeft: step = .left
        case .navigateRight: step = .right
        case .navigateUp: step = .up
        case .navigateDown: step = .down
        case .tabPrevious: step = .previous
        case .tabNext: step = .next
        case .confirm: step = .confirm
        case .cancel: step = .back
        default: return
        }
        let previous = router.menuSelection.selected
        switch router.menuStep(step) {
        case .none:
            if (step == .previous || step == .next), router.menuSelection.selected != previous {
                SoundEffectService.shared.play(.focus)
            }
        case .action(let action): runMenuAction(action)
        case .entry(let entry): runMenuEntry(entry)
        case .power(let power): runPower(power)
        }
    }

    /// A row button. Profile and Library open or close their card, Power its pills (`pressMenuIcon`); the others
    /// act at once, closing the menu before they navigate.
    func runMenuAction(_ action: MenuAction) {
        router.pressMenuIcon(action)
        switch action {
        case .profile, .library, .power:
            break
        case .activityCenter:
            var focus = ActivityCenterFocus()
            focus.selected = ActivityCenterView.rows(viewModel).first
            router.activityCenterFocus = focus
            SoundEffectService.shared.play(.openPanel)
        case .settings:
            router.closeMenu()
            router.openSettings(.startUp)
        }
    }

    /// A line of the Profile or Library card. The card closes first, so that coming back from a profile
    /// screen or Theme (B) lands on the row with the focus on the same icon.
    func runMenuEntry(_ entry: MenuEntry) {
        router.closeEntryMenu()
        switch entry {
        case .myProfile: router.closeMenu(); openProfilePage()
        case .switchProfile: openProfile(.picker, fromMenu: true)
        case .editProfile:
            router.closeMenu()
            router.openSettings(.profileIdentity)
        case .theme:
            // The menu's own screen: the theme's colors, then the background.
            router.isThemePickerOpen = true
        case .players:
            router.closeMenu()
            router.openSettings(.controllers, rowID: "players")
        case .addGame:
            router.closeMenu()
            openFreshAddGame()
        case .manageSources:
            router.closeMenu()
            router.openSettings(.sources)
        case .refreshLibrary:
            router.closeMenu()
            viewModel.refreshLibrary()
        case .gameInbox:
            router.closeMenu()
            router.openGameInbox()
        }
    }

    func runPower(_ action: PowerAction) {
        guard let ask = action.confirmation else { return performPower(action) }
        router.closeMenu()
        viewModel.confirmSetting(ask.title, message: ask.message, action: action.title,
                                 destructive: action == .quit || action == .relaunch) { performPower(action) }
    }

    private func performPower(_ action: PowerAction) {
        switch action {
        case .quit:
            NSApplication.shared.terminate(nil)
        case .sleep:
            router.closeMenu()
            // Sleeping would stall a cloud transfer, like a restart would.
            guard !viewModel.cloudLibrary.isWorking else {
                viewModel.showSettingsNotice(title: L10n.text("Sleep"), message: L10n.text("After the cloud transfer"))
                return
            }
            let sleep = Process()
            sleep.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            sleep.arguments = ["sleepnow"]
            try? sleep.run()
        case .hide:
            router.closeMenu()
            NSApplication.shared.hide(nil)
        case .relaunch:
            relaunchApp()
        }
    }

    /// Starts a helper that waits for this process to exit and then opens the bundle again, then quits.
    /// A second instance cannot be opened while this one runs (LSMultipleInstancesProhibited), so
    /// the new one must start after this one has gone.
    private func relaunchApp() {
        router.closeMenu()
        guard profiles.guest == nil else {
            viewModel.showSettingsNotice(title: L10n.text("Restart app"), message: L10n.text("End the guest session before restarting."))
            return
        }
        guard !viewModel.cloudLibrary.isWorking else {
            viewModel.showSettingsNotice(title: L10n.text("Restart app"), message: L10n.text("After the cloud transfer"))
            return
        }
        guard !router.requestSettingsDeparture({ self.relaunchApp() }) else { return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done; exec /usr/bin/open \"$2\"",
            "relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path
        ]
        do {
            try helper.run()
        } catch {
            viewModel.alertMessage = L10n.format("Arcane could not restart: %@", [String(describing: error.localizedDescription)])
            return
        }
        AppDelegate.relaunchScheduled = true
        NSApplication.shared.terminate(nil)
    }
}
