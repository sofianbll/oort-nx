import AppKit
import SwiftUI
import NXLibraryCore
import Darwin
import os

@MainActor
final class DevelopmentStartup: ObservableObject {
    enum Notice: Equatable {
        case copy([DowngradeCheckpoint.Omission])
        case failed, diskFull

        var canContinueWithoutCopy: Bool { self == .failed || self == .diskFull }
    }
    @Published private(set) var shell: AppShellState?
    @Published private(set) var failure: String?
    @Published private(set) var working = false
    @Published private(set) var recovery: CatalogRecoveryCandidate?
    @Published private(set) var legacyConflict: CatalogLegacyConflictCandidate?
    @Published private(set) var downgradeNotice: Notice?
    @Published private(set) var showCopyProgress = false
    @Published private(set) var paletteID = SelenePaletteCatalog.defaultID
    @Published private(set) var offersLibraryCopy = false
    private var libraryCopyChoice: DevelopmentProfileImporter.Contents?
    var canStartWithoutLibraryCopy: Bool { libraryCopyChoice == .library && shell == nil && !working }
    private var skipCheckpoint = false
    private var profileLease: DowngradeCheckpoint.ProfileLease?
    private let logger = Logger(subsystem: "io.github.sofianbll.oortnx", category: "Startup")
    private let checkpoint: @Sendable (URL, Bool) throws -> DowngradeCheckpoint.Result

    init(checkpoint: @escaping @Sendable (URL, Bool) throws -> DowngradeCheckpoint.Result = { root, acceptingWarning in
        try DowngradeCheckpoint.prepare(in: root, acceptingWarning: acceptingWarning) {
            let defaults = AppData.preferences
            guard defaults.synchronize() else { throw CocoaError(.fileReadUnknown) }
            return defaults.persistentDomain(forName: AppData.profile.preferencesDomain) ?? [:]
        }
    }) {
        self.checkpoint = checkpoint
    }

    func prepare(acceptingDowngradeWarning: Bool = false) async {
        guard shell == nil, !working else { return }
        working = true
        defer { working = false }
        failure = nil
        recovery = nil
        legacyConflict = nil
        downgradeNotice = nil
        var profileReady = false
        do {
            if libraryCopyChoice == nil, await Task.detached(operation: {
                DevelopmentProfileImporter.offersLibraryCopy(for: AppData.profile)
            }).value {
                offersLibraryCopy = true
                return
            }
            // Services and SwiftUI StateObjects are created only after the profile transaction finishes.
            if [AppDataProfile.identifier, AppDataProfile.legacyIdentifier].flatMap(NSRunningApplication.runningApplications(withBundleIdentifier:))
                .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                throw DevelopmentStartupFailure.otherCopyRunning
            }
            let contents = libraryCopyChoice ?? .empty
            try await Task.detached(priority: .userInitiated) { try AppData.prepare(contents: contents) }.value
            if !AppData.profile.isDevelopment && profileLease == nil {
                do {
                    profileLease = try await Task.detached { try DowngradeCheckpoint.ProfileLease(in: AppData.supportRoot) }.value
                } catch let error as POSIXError where error.code == .EWOULDBLOCK {
                    throw DevelopmentStartupFailure.otherCopyRunning
                }
            }
            if !AppData.profile.isDevelopment && !skipCheckpoint {
                paletteID = await Task.detached { DowngradeCheckpoint.savedPalette(in: AppData.supportRoot) }.value
                let progress = Task {
                    try await Task.sleep(for: .seconds(1))
                    showCopyProgress = true
                }
                defer { progress.cancel(); showCopyProgress = false }
                do {
                    let result = try await Task.detached(priority: .userInitiated) { [checkpoint] in
                        // After a move the untouched old folder is the way back, so there is nothing to warn about.
                        try checkpoint(AppData.supportRoot, acceptingDowngradeWarning || LibraryMove.moved(AppData.supportRoot))
                    }.value
                    if case let .warning(omissions) = result {
                        downgradeNotice = .copy(omissions)
                        return
                    }
                } catch {
                    logger.error("Launcher checkpoint failed: \(String(describing: error), privacy: .private)")
                    downgradeNotice = Self.isDiskFull(error) ? .diskFull : .failed
                    return
                }
            }
            profileReady = true
            let catalog = try await Task.detached(priority: .userInitiated) {
                try CatalogStore(directory: AppData.supportRoot).loadOrMigrate()
            }.value
            logger.notice("Launcher data ready; preparing shell models")
            let store = AppSettingsStore()
            // Complete model/AppKit startup outside the render that inserts MainView.
            shell = AppShellState(settings: store, catalog: catalog, repository: CatalogRepository(store: CatalogStore(directory: AppData.supportRoot)))
            logger.notice("Shell models ready")
        } catch {
            logger.error("Launcher preparation failed")
            failure = error.localizedDescription
            if profileReady {
                recovery = try? await Task.detached(priority: .userInitiated) {
                    try CatalogStore(directory: AppData.supportRoot).recoveryCandidate()
                }.value
                legacyConflict = try? await Task.detached(priority: .userInitiated) {
                    try CatalogStore(directory: AppData.supportRoot).legacyConflictCandidate()
                }.value
            }
        }
    }

    func chooseLibraryCopy(_ copy: Bool) async {
        guard !working, offersLibraryCopy || (!copy && canStartWithoutLibraryCopy) else { return }
        offersLibraryCopy = false
        libraryCopyChoice = copy ? .library : .empty
        await prepare()
    }

    func continueWithoutCopy() async {
        guard !working, downgradeNotice?.canContinueWithoutCopy == true else { return }
        skipCheckpoint = true
        await prepare()
    }

    private static func isDiskFull(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        for _ in 0..<4 {
            guard let candidate = current else { break }
            if (candidate.domain == NSPOSIXErrorDomain && candidate.code == Int(ENOSPC))
                || (candidate.domain == NSCocoaErrorDomain && candidate.code == CocoaError.fileWriteOutOfSpace.rawValue) {
                return true
            }
            current = (candidate.userInfo[NSUnderlyingErrorKey] as? Error).map { $0 as NSError }
        }
        return false
    }

    func restoreBackup() async {
        guard !working, let candidate = recovery else { return }
        working = true
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try CatalogStore(directory: AppData.supportRoot).restoreBackup(candidate)
            }.value
            working = false
            await prepare()
        } catch {
            failure = error.localizedDescription
            recovery = nil
            working = false
        }
    }

    func keepCurrentLibrary() async {
        guard !working, let candidate = legacyConflict else { return }
        working = true
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try CatalogStore(directory: AppData.supportRoot).keepCurrentLibrary(candidate)
            }.value
            working = false
            await prepare()
        } catch {
            failure = error.localizedDescription
            legacyConflict = nil
            working = false
        }
    }

}

private enum DevelopmentStartupFailure: LocalizedError {
    case otherCopyRunning
    var errorDescription: String? {
        let context = AppLocale(language: .automatic, region: nil)
        return L10n.text("Close the other Arcane copy, then try again. Your original library has not been changed.", context: context)
    }
}

/// Bootstrap has no app stores, themes or game-operation hooks until its profile is ready.
struct DevelopmentStartupView: View {
    @StateObject private var startup = DevelopmentStartup()
    private let context = AppLocale(language: .automatic, region: nil)
    var body: some View {
        Group {
            if let shell = startup.shell {
                MainView(state: shell)
                    .onAppear {
                        Logger(subsystem: "io.github.sofianbll.oortnx", category: "Startup").notice("Library view appeared")
                    }
            } else if startup.offersLibraryCopy {
                OnboardingCopyOffer { copy in Task { await startup.chooseLibraryCopy(copy) } }
                    .seleneCanvasRoot()
            } else if let notice = startup.downgradeNotice {
                DowngradeWarningView(notice: notice, retry: { Task { await startup.prepare() } }, proceed: {
                    Task {
                        if notice.canContinueWithoutCopy { await startup.continueWithoutCopy() }
                        else { await startup.prepare(acceptingDowngradeWarning: true) }
                    }
                }).seleneCanvasRoot()
            } else if let failure = startup.failure {
                VStack(spacing: 20) {
                    if startup.working { ProgressView().controlSize(.large) }
                    Text(L10n.text("Library unavailable", context: context))
                        .font(.system(size: 28, weight: .semibold))
                    Text(failure)
                        .font(.system(size: 17)).multilineTextAlignment(.center)
                    if startup.legacyConflict != nil {
                        Text(L10n.text("Keep the games and sources in Arcane. The older app's changes will be archived separately, without merging the libraries.", context: context))
                            .font(.system(size: 15)).multilineTextAlignment(.center)
                        Button(L10n.text("Keep Arcane's library", context: context)) {
                            Task { await startup.keepCurrentLibrary() }
                        }.keyboardShortcut("k", modifiers: [.command, .shift])
                            .disabled(startup.working)
                    }
                    if let candidate = startup.recovery {
                        Button(L10n.count("Restore backup (%lld games)", candidate.gameCount, context: context)) {
                            Task { await startup.restoreBackup() }
                        }.keyboardShortcut("r", modifiers: [.command, .shift])
                            .disabled(startup.working)
                    }
                    HStack(spacing: 24) {
                        Button(L10n.text("Close", context: context)) { NSApplication.shared.terminate(nil) }
                            .keyboardShortcut(.cancelAction)
                        Button(L10n.text("Open library folder", context: context)) { NSWorkspace.shared.open(AppData.supportRoot) }
                            .keyboardShortcut("o", modifiers: [.command])
                        Button(L10n.text("Retry", context: context)) { Task { await startup.prepare() } }
                            .keyboardShortcut(.defaultAction)
                        if startup.canStartWithoutLibraryCopy {
                            Button(L10n.text("Start without a copy", context: context)) {
                                Task { await startup.chooseLibraryCopy(false) }
                            }
                        }
                    }.disabled(startup.working)
                }
                .foregroundColor(.white)
                .padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                .onAppear { LaunchReveal.show() }
            } else if startup.showCopyProgress {
                DowngradeCopyProgress(context: context).seleneCanvasRoot()
            } else {
                // While the profile is prepared (a fraction of a second) the window is still transparent
                // (`LaunchReveal`) and stays on the scrim, with no words or spinner.
                SeleneTheme.scrim.ignoresSafeArea()
            }
        }
        .background(LaunchRevealHold())
        .onChange(of: startup.paletteID, initial: true) { _, id in
            if startup.shell == nil { ThemeStore.shared.apply(id: id) }
        }
        .task { await startup.prepare() }
    }
}
