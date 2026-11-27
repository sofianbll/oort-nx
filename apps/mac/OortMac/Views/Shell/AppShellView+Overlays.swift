import SwiftUI
import AppKit
import Combine
import OortLibrary
import NxnativeAdapter

/// The shell's dialogs and notices: settings notices, welcome, install failure, Close Game, removal and the update offer.
extension AppShellView {
    func cloudQuitOverlay() -> some View {
        let movingLibrary = viewModel.cloudLibrary.libraryMove != nil
        return SeleneOverlay(style: .dialog) {
            SeleneConfirmDialog(title: movingLibrary ? "Moving the cloud library" : "A cloud transfer is in progress",
                                message: movingLibrary
                                    ? L10n.text("Quitting stops the move between files. Files already moved stay in the new folder.")
                                    : L10n.text("Quitting stops the transfer. Your files and cloud copies stay intact. The next time you open Arcane, confirm uploads again from the game pages."),
                                confirmTitle: "Quit", cancelTitle: "Stay", destructive: true, focus: $cloudQuitFocus,
                                onCancel: { finishCloudQuit(false) },
                                onConfirm: { finishCloudQuit(true) })
        }
    }

    func finishCloudQuit(_ quit: Bool) {
        guard viewModel.cloudQuitRequested, !viewModel.cloudLibrary.isQuitting else { return }
        if quit {
            AppDelegate.finishCloudQuit(NSApp)
        } else {
            AppDelegate.cancelGuestQuitConfirmation()
            cloudQuitFocus = .cancel
            viewModel.cloudQuitRequested = false
        }
    }

    // MARK: - Retry a ready build

    func settingsNoticeOverlay(_ notice: SettingsNotice) -> some View {
        SeleneOverlay(style: .dialog, onOutside: {
            if viewModel.settingsNotice?.id == notice.id { finishSettingsNotice() }
        }) {
            SeleneChoiceDialog(title: notice.title, message: notice.message,
                               answers: notice.answers, focus: $viewModel.settingsNoticeAnswer,
                               details: notice.choiceDetails, notes: notice.notes,
                               notesScrollRequest: viewModel.settingsNoticeNotesScroll,
                               onCancel: { if viewModel.settingsNotice?.id == notice.id { finishSettingsNotice() } },
                               onAnswer: { if viewModel.settingsNotice?.id == notice.id { finishSettingsNotice(answer: $0) } })
        }
    }

    /// At every launch from a temporary copy (`AppUpdate.asksToBeMoved`): that copy never updates itself, and only
    /// moving the downloaded app in the Finder fixes it. The temporary path itself is no help, so this opens Applications.
    func askToMoveIfTranslocated() {
        guard AppUpdate.asksToBeMoved(Bundle.main.bundleURL) else { return }
        viewModel.showSettingsNotice(
            title: L10n.text("Move Arcane to Applications to update"),
            message: L10n.text("macOS is running a temporary copy of Arcane, so it cannot update itself. In the Finder, move Arcane to Applications, then quit it and open it from there."),
            actionTitle: L10n.text("Open Applications"),
            cancelTitle: L10n.text("Not now"), primaryFirst: true,
            retry: { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true)) })
    }

    func finishSettingsNotice(answer: SettingsNotice.AnswerID = .back) {
        let notice = viewModel.settingsNotice
        viewModel.settingsNotice = nil
        notice?.onDismiss?()
        notice?.runAnswer(answer)
        presentLegacyNotice()
    }

    /// Anything that comes before the welcome: Setup, dialogs, a launch, the screenshot viewer.
    private var welcomeBlocked: Bool {
        viewModel.showSetupCheck || showsSettingsNotice || showsInstallFailure
            || showsUpdateOffer || viewModel.gameToClose != nil || viewModel.gameToRemove != nil
            || viewModel.launchOverlay != nil || router.isScreenshotViewerOpen
    }

    var welcomeTrigger: [Bool] {
        [welcomeBlocked, viewModel.setupCompleted, AppData.preferences.bool(forKey: AppViewModel.StorageKeys.onboardingNewsSeen),
         viewModel.gameWithInstallFailure != nil, viewModel.hasActiveSaveOperations]
    }

    func presentWelcomeIfDue() async {
        guard !showsWelcome, !welcomeDismissed, !welcomeBlocked, viewModel.setupCompleted,
              !AppData.preferences.bool(forKey: AppViewModel.StorageKeys.onboardingNewsSeen) else { return }
        // `hasActiveSaveOperations` is in the trigger: the welcome comes back here when the save recovery ends.
        let pending = viewModel.hasActiveSaveOperations || viewModel.saveGate.hasActiveOperations
            || viewModel.gameWithInstallFailure != nil
        guard !Task.isCancelled, !welcomeBlocked,
              ArcaneWelcome.shouldShow(setupCompleted: viewModel.setupCompleted,
                                       shown: AppData.preferences.bool(forKey: AppViewModel.StorageKeys.onboardingNewsSeen),
                                       hasPendingRecovery: pending) else { return }
        withAnimation(reduceMotion ? nil : SeleneTheme.screen) { showsWelcome = true }
    }

    /// The welcome fades first; saving and moving to the library wait until it has gone, so no redraw of the
    /// whole shell lands in the fade's first frames (Selene does its home work once the layer has really gone).
    func closeWelcome(_ exit: ArcaneWelcome.Exit) {
        guard showsWelcome else { return }
        welcomeDismissed = true
        AppData.preferences.set(true, forKey: AppViewModel.StorageKeys.onboardingNewsSeen)
        let finish = {
            settings.settings = ArcaneWelcome.settings(after: exit, from: settings.settings)
            if exit == .openLibrary { router.navigate(to: .library) }
            viewModel.isWelcomeOpen = false
        }
        guard !reduceMotion else {
            showsWelcome = false
            finish()
            return
        }
        withAnimation(SeleneTheme.screen) { showsWelcome = false }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(SeleneTheme.screenDuration * 1_000_000_000))
            finish()
        }
    }

    func presentLegacyNotice() {
        guard viewModel.settingsNotice == nil, let message = viewModel.alertMessage else { return }
        viewModel.alertMessage = nil
        // The message is also in the log only when there is more to read there.
        let logged = viewModel.logs.last { $0.level == .error }?.message == message
        viewModel.showSettingsNotice(title: AppIdentity.displayName, message: message, actionTitle: "Open log",
                                     retry: logged ? { [viewModel] in viewModel.router?.openSettings(.console) } : nil)
    }

    func presentCloudNotice() {
        guard viewModel.settingsNotice == nil, !viewModel.cloudLibrary.isQuitting else { return }
        if let failure = viewModel.cloudLibrary.queueFailure {
            viewModel.cloudLibrary.queueFailure = nil
            viewModel.showCloudFailure(failure, title: L10n.text("Cloud library"), retry: {})
        } else if let failure = viewModel.cloudLibrary.startupFailure {
            viewModel.cloudLibrary.startupFailure = nil
            viewModel.showCloudFailure(failure, title: L10n.text("Cloud library"),
                                       sourceFolder: viewModel.cloudLibrary.checkFailureOnSources) {
                viewModel.retryCloudCheck()
            }
        }
    }

    func settingsNoticeInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateUp, .navigateRight, .navigateDown:
            guard let notice = viewModel.settingsNotice else { return }
            let direction = action == .navigateLeft || action == .navigateUp ? -1 : 1
            if let notes = notice.notes, action == .navigateUp || action == .navigateDown {
                let last = max(0, ReleaseNotesLayout.lines(notes).count - 1)
                viewModel.settingsNoticeNotesScroll = min(last, max(0, viewModel.settingsNoticeNotesScroll + direction))
                return
            }
            viewModel.settingsNoticeAnswer = ActionBarOrder.move(viewModel.settingsNoticeAnswer, by: direction, in: notice.answers.map(\.id))
        case .confirm: finishSettingsNotice(answer: viewModel.settingsNoticeAnswer)
        case .cancel: finishSettingsNotice()
        default: break
        }
    }

    func installFailureOverlay(_ game: PortedGame) -> some View {
        return SeleneOverlay(style: .dialog, onOutside: { viewModel.gameWithInstallFailure = nil }) {
            SeleneConfirmDialog(title: L10n.text("Installation failed"),
                                message: L10n.format("The new build of %@ has been kept.", [String(describing: game.name)])
                                    + "\n" + viewModel.installFailureDetail,
                                confirmTitle: "Retry", cancelTitle: L10n.text("Close"),
                                focus: $viewModel.installFailureFocus,
                                onCancel: { viewModel.gameWithInstallFailure = nil },
                                onConfirm: { viewModel.retryFailedInstallation() })
        }
    }

    func installFailureInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft ? .left : .right
            if viewModel.installFailureFocus != next {
                viewModel.installFailureFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            if viewModel.installFailureFocus == .confirm {
                viewModel.retryFailedInstallation()
            } else {
                viewModel.gameWithInstallFailure = nil
            }
        case .cancel: viewModel.gameWithInstallFailure = nil
        default: break
        }
    }

    // MARK: - Close Game confirmation

    func closeGameOverlay(_ game: PortedGame) -> some View {
        SeleneOverlay(style: .dialog, onOutside: { viewModel.dismissCloseGame() }) {
            SeleneConfirmDialog(title: L10n.format("Close %@?", [String(describing: game.name)]),
                                message: L10n.text("Unsaved progress will be lost."),
                                confirmTitle: "Close",
                                destructive: true, focus: $viewModel.closeGameFocus,
                                onCancel: { viewModel.dismissCloseGame() },
                                onConfirm: confirmCloseGame)
        }
    }

    /// Input while the Close Game confirmation is open: Left and Right pick a pill, A runs it, B cancels.
    func closeGameInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft ? .left : .right
            if viewModel.closeGameFocus != next {
                viewModel.closeGameFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            if viewModel.closeGameFocus == .confirm {
                confirmCloseGame()
            } else {
                viewModel.dismissCloseGame()
            }
        case .cancel:
            viewModel.dismissCloseGame()
        default:
            break
        }
    }

    // MARK: - Delete after a failed porting

    func removeGameOverlay(_ game: PortedGame) -> some View {
        SeleneOverlay(style: .dialog, onOutside: { viewModel.dismissRemoveGame() }) {
            SeleneConfirmDialog(title: L10n.format("Delete %@?", [String(describing: game.name)]),
                                message: L10n.text("It leaves the library. Your game files and the build cache stay on disk."),
                                confirmTitle: "Delete",
                                destructive: true, focus: $viewModel.removeGameFocus,
                                onCancel: { viewModel.dismissRemoveGame() },
                                onConfirm: { viewModel.confirmRemoveGame() })
        }
    }

    // MARK: - A newer release at launch

    func updateOfferOverlay() -> some View {
        SeleneOverlay(style: .dialog, onOutside: { updater.later() }) {
            AppUpdateDialog(updater: updater, requirementNotes: updater.dialogRelease.map {
                AppUpdate.requirementNotes($0.requirements,
                    installedXcode: setup.environmentStatus?.xcodeVersion,
                    currentEngine: viewModel.setup.versions.reference)
            } ?? [], blockedReason: updater.blockedReason())
        }
    }

    func updateOfferInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft && updater.dialogHasSecondaryButton ? .left : .right
            if updater.offerFocus != next {
                updater.offerFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            SoundEffectService.shared.play(.click)
            if updater.offerFocus == .confirm { updater.confirmDialog() } else { updater.later() }
        case .cancel:
            updater.later()
        case .navigateUp, .navigateDown, .jumpToStart, .jumpToEnd:
            let last = max(0, (updater.dialogRelease?.notes.components(separatedBy: "\n").count ?? 1) - 1)
            switch action {
            case .jumpToStart: updater.notesScroll = 0
            case .jumpToEnd: updater.notesScroll = last
            default: updater.notesScroll = min(last, max(0, updater.notesScroll + (action == .navigateUp ? -3 : 3)))
            }
        default:
            break
        }
    }

    func removeGameInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft ? .left : .right
            if viewModel.removeGameFocus != next {
                viewModel.removeGameFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            SoundEffectService.shared.play(.click)
            if viewModel.removeGameFocus == .confirm {
                viewModel.confirmRemoveGame()
            } else {
                viewModel.dismissRemoveGame()
            }
        case .cancel:
            viewModel.dismissRemoveGame()
        default:
            break
        }
    }

    private func confirmCloseGame() {
        guard let game = viewModel.gameToClose else { return }
        viewModel.dismissCloseGame()
        SoundEffectService.shared.play(.click)
        runningGames.close(game)
    }
}
