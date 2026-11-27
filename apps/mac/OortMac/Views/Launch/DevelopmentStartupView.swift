import AppKit
import SwiftUI
import OortLibrary
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
            let prepared = try await Task.detached(priority: .userInitiated) {
                try CatalogStore(directory: AppData.supportRoot).loadForStartup(previousLibrary: AppData.profile.legacySupportRoot)
            }.value
            logger.notice("Launcher data ready; preparing shell models")
            let store = AppSettingsStore()
            // Complete model/AppKit startup outside the render that inserts MainView.
            let state = AppShellState(settings: store, catalog: prepared.catalog,
                                      repository: CatalogRepository(store: CatalogStore(directory: AppData.supportRoot)))
            let fm = FileManager.default
            let removal = fm.fileExists(atPath: AppData.supportRoot.appendingPathComponent(LibraryPaths.inheritedRemoval).path)
                && fm.fileExists(atPath: AppData.profile.legacySupportRoot.appendingPathComponent(LibraryPaths.removalJournal).path)
            if let notice = Self.libraryMoveNotice(removal: removal, pendingBuild: prepared.keptPreviousBuild) {
                state.viewModel.alertMessage = [state.viewModel.alertMessage, notice].compactMap { $0 }.joined(separator: "\n")
            }
            shell = state
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

    static func libraryMoveNotice(removal: Bool, pendingBuild: Bool) -> String? {
        var messages: [String] = []
        if removal { messages.append(L10n.text("Open the previous version to undo the interrupted removal.")) }
        if pendingBuild { messages.append(L10n.text("Open the previous version to finish installing the game.")) }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
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
                LibraryUnavailableView(failure: failure, working: startup.working, conflict: startup.legacyConflict != nil,
                                       backupGames: startup.recovery?.gameCount,
                                       startsWithoutCopy: startup.canStartWithoutLibraryCopy, context: context,
                                       keep: { Task { await startup.keepCurrentLibrary() } },
                                       restore: { Task { await startup.restoreBackup() } },
                                       startWithoutCopy: { Task { await startup.chooseLibraryCopy(false) } },
                                       retry: { Task { await startup.prepare() } })
                    .seleneCanvasRoot()
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

/// The library could not be opened: its repairs, then the way out on the left and Retry last. Mouse, arrows, Tab,
/// Return, Esc and the controller all reach every key.
struct LibraryUnavailableView: View {
    private enum Key: Hashable { case keep, restore, close, folder, withoutCopy, retry }
    private final class ControllerInput: ObservableObject {
        var handle: ((GamepadAction) -> Void)?
    }

    let failure: String
    let working: Bool
    let conflict: Bool
    let backupGames: Int?
    let startsWithoutCopy: Bool
    let context: AppLocale
    let keep: () -> Void
    let restore: () -> Void
    let startWithoutCopy: () -> Void
    let retry: () -> Void
    @Environment(\.seleneCanvas) private var canvas
    @StateObject private var controller = ControllerInput()
    @State private var focus = Key.retry
    @FocusState private var acceptsKeys: Bool

    private var repairs: [Key] { (conflict ? [.keep] : []) + (backupGames == nil ? [] : [.restore]) }
    private var foot: [Key] { [.close, .folder] + (startsWithoutCopy ? [.withoutCopy] : []) + [.retry] }

    var body: some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.panel)) {
            if working { WaveDots() }
            Text(text("Library unavailable")).seleneFont(.screen, .semibold).accessibilityAddTraits(.isHeader)
            Text(failure).seleneFont(.text).foregroundStyle(SeleneTheme.ink90)
            if conflict {
                Text(text("Keep the games and sources in Arcane. The older app's changes will be archived separately, without merging the libraries."))
                    .seleneFont(.text).foregroundStyle(SeleneTheme.ink75)
            }
            ForEach(repairs, id: \.self) { key in
                OortButton(title: title(key), focused: focus == key, state: working ? .blocked : .ready, preset: .card) { perform(key) }
                    .seleneHover { focus = key }
            }
            OortActionBar(actions: foot.map { key in
                .init(id: key, title: title(key), role: key == .close ? .back : key == .retry ? .primary : .secondary,
                      enabled: !working) { perform(key) }
            }, focused: focus, preset: .card) { id in
                if let key = id.base as? Key { focus = key }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: canvas.u(SeleneTokens.Space.questionMeasure))
        .foregroundStyle(SeleneTheme.ink)
        .padding(canvas.u(SeleneTokens.Space.group))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            SeleneHintsBar(left: [HintItem(.b, "Close") { perform(.close) }],
                           right: [HintItem(.a, "Select") { perform(focus) }])
        }
        // Recovery keeps a fixed background even when the player's palette couldn't be read.
        .background(SeleneTheme.baseGradient(for: .fallback))
        .environment(\.nxAppLocale, context)
        .focusable()
        .focused($acceptsKeys)
        .defaultFocus($acceptsKeys, true)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .tab, .return, .space, .escape]) { key in
            switch key.key {
            case .leftArrow: input(.navigateLeft)
            case .rightArrow: input(.navigateRight)
            case .upArrow: input(.navigateUp)
            case .downArrow: input(.navigateDown)
            case .tab: step(key.modifiers.contains(.shift) ? -1 : 1, in: repairs + foot)
            case .escape: input(.cancel)
            default: input(.confirm)
            }
            return .handled
        }
        .onAppear {
            acceptsKeys = true
            let receiver = controller
            receiver.handle = input
            GameControllerService.shared.onAction = { [weak receiver] in receiver?.handle?($0) }
            LaunchReveal.show()
        }
        // Do not clear the shared router: the shell can already have installed its own handler.
        .onDisappear { controller.handle = nil }
        .onChange(of: repairs) { if !(repairs + foot).contains(focus) { focus = .retry } }
    }

    private func title(_ key: Key) -> String {
        switch key {
        case .keep: text("Keep Arcane's library")
        case .restore: L10n.count("Restore backup (%lld games)", backupGames ?? 0, context: context)
        case .close: text("Close")
        case .folder: text("Open library folder")
        case .withoutCopy: text("Start without a copy")
        case .retry: text("Retry")
        }
    }

    private func text(_ key: String) -> String { L10n.text(key, context: context) }

    private func perform(_ key: Key) {
        if key == .close { NSApplication.shared.terminate(nil); return }
        guard !working else { return }
        switch key {
        case .keep: keep()
        case .restore: restore()
        case .folder: NSWorkspace.shared.open(AppData.supportRoot)
        case .withoutCopy: startWithoutCopy()
        case .retry: retry()
        case .close: break
        }
    }

    private func step(_ delta: Int, in keys: [Key]) {
        guard let index = keys.firstIndex(of: focus), keys.indices.contains(index + delta) else { return }
        focus = keys[index + delta]
    }

    private func input(_ action: GamepadAction) {
        switch action {
        case .navigateLeft: step(-1, in: foot)
        case .navigateRight: step(1, in: foot)
        case .navigateUp:
            if foot.contains(focus) { focus = repairs.last ?? focus } else { step(-1, in: repairs) }
        case .navigateDown:
            if focus == repairs.last { focus = .retry } else { step(1, in: repairs) }
        case .confirm: perform(focus)
        case .cancel: perform(.close)
        default: break
        }
    }
}
