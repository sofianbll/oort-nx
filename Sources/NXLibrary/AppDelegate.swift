import AppKit
import ArcanePorting
import NXLibraryCore
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "local.nxlibrary", category: "rename")
    /// Set by the shell: true while a build, an update or a save operation still needs this bundle's path.
    @MainActor static var isBusy: () -> Bool = { false }
    /// Set when a helper will reopen this bundle at its current path after the app quits.
    @MainActor static var relaunchScheduled = false
    /// The profile's store outlives the last window so it can finish a selection write when quitting.
    @MainActor static var settingsStore: AppSettingsStore?
    @MainActor static var cloudLibrary: CloudLibraryModel?
    @MainActor static weak var activityOwner: AppViewModel?
    @MainActor static var showCloudQuit: (() -> Void)?
    @MainActor static var requestGuestQuit: (() -> Void)?
    @MainActor private static var guestQuitConfirmed = false
    @MainActor static weak var shellWindow: NSWindow?
    @MainActor private static var cloudQuitCleanupComplete = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        SeleneFonts.register()
    }

    /// A release copy still called "NX Library.app" takes its current name on its way out
    /// (`AppBundleRename`); a failure is logged and never holds up quitting.
    func applicationWillTerminate(_ notification: Notification) {
        Self.settingsStore?.flushPendingSelection()
        let bundle = Bundle.main.bundleURL
        guard let target = AppBundleRename.target(
            bundleURL: bundle,
            isRelease: AppUpdate.installability(bundle) != .developer,
            isTranslocated: AppUpdate.isTranslocated(bundle),
            isBusy: Self.relaunchScheduled || Self.isBusy()
        ) else { return }
        do {
            try AppBundleRename.perform(bundleURL: bundle, to: target)
        } catch {
            Self.log.error("Renaming the app to \(target.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let cloud = Self.cloudLibrary else { return .terminateNow }
        // .terminateLater runs a modal loop that stalls shell input and main-actor cleanup.
        let activity = Self.activityOwner
        if activity?.porting.isAdoptingBuildCache == true { return .terminateCancel }
        let decision = CloudQuitDecision.resolve(isWorking: cloud.isWorking, hasQueueWrites: cloud.hasQueueWrites
                                            || cloud.driveToolTask != nil
                                            || activity?.hasActivityWrites == true || activity?.porting.hasBuildQueueWrites == true
                                            || activity?.buildQueue.isEmpty == false || activity?.activityResults.entries.isEmpty == false,
                                         isQuitting: cloud.isQuitting, cleanupComplete: Self.cloudQuitCleanupComplete,
                                         relaunchScheduled: Self.relaunchScheduled)
        if decision != .cancel, !Self.guestQuitConfirmed, activity?.localProfiles?.guest != nil {
            if let window = Self.shellWindow, !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            Self.requestGuestQuit?()
            return .terminateCancel
        }
        switch decision {
        case .quit:
            return .terminateNow
        case .cancel:
            return .terminateCancel
        case .confirm:
            if let window = Self.shellWindow {
                if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
                Self.showCloudQuit?()
            }
            return .terminateCancel
        case .flush:
            Self.finishCloudQuit(sender)
            return .terminateCancel
        }
    }

    @MainActor static func quitAfterGuestConfirmation() {
        guestQuitConfirmed = true
        NSApplication.shared.terminate(nil)
    }

    @MainActor static func cancelGuestQuitConfirmation() {
        guestQuitConfirmed = false
    }

    @MainActor static func finishCloudQuit(_ sender: NSApplication) {
        guard let cleanup = cloudLibrary?.stopForQuit() else { return }
        Task {
            await cleanup.value
            if let owner = activityOwner {
                await owner.restoreActivity()
                await owner.porting.buildQueueStore.flush()
                await owner.activityStore.flush()
            }
            cloudQuitCleanupComplete = true
            sender.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let window = sender.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
            return true
        }
        return false
    }
}
