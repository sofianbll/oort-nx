import Foundation
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var retry: (() -> Void)?
    var onDismiss: (() -> Void)? = nil
    var actionTitle = "Retry"
    var cancelTitle = "Back"
    var alternatives: [(title: String, run: () -> Void)] = []
    /// The question opens on its main answer: without risk, and never one of `destructive`.
    var primaryFirst = false
    /// The titles of the answers that delete, replace or end something.
    var destructive: Set<String> = []
    var choiceDetails: [String: String] = [:]
    var duringSetup = false
    var notes: String? = nil

    enum AnswerID: Hashable {
        case back, retry, alternative(Int)
    }

    private typealias Answer = (id: AnswerID, title: String)
    var answers: [DialogAnswer<AnswerID>] {
        let main: Answer? = retry.map { _ in (.retry, actionTitle) }
        let other: [Answer] = alternatives.enumerated().map { (.alternative($0.offset), $0.element.title) }
        return ActionBarOrder.question(main: main, others: other, back: (.back, cancelTitle)) {
            destructive.contains($0.title)
        }.map { .init($0.item.id, $0.item.title, $0.role) }
    }

    var defaultAnswer: AnswerID {
        primaryFirst && retry != nil && !destructive.contains(actionTitle) ? .retry : .back
    }

    func runAnswer(_ answer: AnswerID) {
        switch answer {
        case .back: break
        case .retry: retry?()
        case .alternative(let id):
            if alternatives.indices.contains(id) { alternatives[id].run() }
        }
    }

    // Read-only layout observations used by the screen probes. These indices cannot activate anything.
    var choices: [String] { answers.map(\.title) }
    var cancelIndex: Int { answers.firstIndex { $0.id == .back } ?? 0 }
    var initialFocus: Int { answers.firstIndex { $0.id == defaultAnswer } ?? cancelIndex }
    var destructiveIndexes: Set<Int> { Set(answers.indices.filter { answers[$0].role == .destructive }) }

}

final class AppViewModel: ObservableObject {
    /// The automatic Icon's online lookup, shared by Switch and Steam games' Change artwork.
    static let automaticIconArtwork = ArtworkStore()
    let saveGate = SaveOperationGate()
    let cloudLibrary: CloudLibraryModel
    @Published var activityResults = ActivityHistory()
    let activityStore = ActivityQueueFile<ActivityHistory.Result>(file: AppData.supportRoot.appendingPathComponent("activity-results.json"))
    var hasLoadedActivity = false
    var hasActivityWrites = false
    @Published var cloudQuitRequested = false {
        didSet { if !cloudQuitRequested { porting.scheduleNextBuild() } }
    }
    private var cloudConnectionObservation: AnyCancellable?
    @Published var cloudLibraryGameID: UUID?
    @Published var isCheckingCloudBuild = false
    let saveQueue = DispatchQueue(label: "io.github.sofianbll.oortnx.saves", qos: .userInitiated)
    let localAchievementStore = LocalAchievementStore(defaults: AppData.preferences)
    @Published var localAchievementRevision = 0
    let localAchievementUnlocks = PassthroughSubject<(profile: UUID, names: [String]), Never>()
    @Published var settingsNotice: SettingsNotice? {
        didSet {
            if appIcon.iconLaunchWait.gameID != nil, settingsNotice?.id != appIcon.iconLaunchWait.noticeID {
                appIcon.cancelIconLaunchWait()
            }
            if settingsNotice == nil {
                porting.scheduleNextBuild()
                Task { @MainActor [weak self] in self?.offerDriveUpgrade() }
            }
        }
    }
    @Published var settingsNoticeAnswer = SettingsNotice.AnswerID.back
    @Published var settingsNoticeNotesScroll = 0
    var settingsNoticeFocus: Int {
        settingsNotice?.answers.firstIndex { $0.id == settingsNoticeAnswer } ?? 0
    }
    /// The last reversible gesture, for its notice, ⌘Z and Activity.
    let undoOffers = UndoOffers()
    let tips = Tips(defaults: AppData.preferences)
    /// The keys of the notice on screen, while they were asked for.
    @Published var noticeFocus = NoticeFocus()
    /// A SteamGridDB API key is saved (Settings → Online services → SteamGridDB), so Change artwork searches it.
    @Published var hasSteamGridDBKey = SteamGridDBKey().load() != nil
    @Published var isEditingSteamGridDBKey = false
    @Published var isUpdatingApp = false {
        didSet { if !isUpdatingApp { porting.scheduleNextBuild() } }
    }
    @Published private(set) var hasActiveSaveOperations = false
    @Published var runningGameCount = 0

    func showSettingsNotice(title: String, message: String, actionTitle: String = "Retry",
                            cancelTitle: String = "Back", alternatives: [(title: String, run: () -> Void)] = [],
                            primaryFirst: Bool? = nil, destructive: Set<String> = [],
                            choiceDetails: [String: String] = [:], duringSetup: Bool = false, notes: String? = nil,
                            retry: (() -> Void)? = nil) {
        let notice = SettingsNotice(title: title, message: message, retry: retry,
                                    actionTitle: actionTitle, cancelTitle: cancelTitle, alternatives: alternatives,
                                    // Trying again risks nothing.
                                     primaryFirst: primaryFirst ?? (actionTitle == "Retry"), destructive: destructive,
                                     choiceDetails: choiceDetails, duringSetup: duringSetup, notes: notes)
        settingsNoticeNotesScroll = 0
        settingsNoticeAnswer = notice.defaultAnswer
        settingsNotice = notice
    }

    /// Settings keep their current value until a choice other than Cancel is activated.
    func confirmSetting(_ title: String, message: String,
                        choices: [(title: String, run: () -> Void)], details: [String: String] = [:],
                        destructive: Set<String> = [], duringSetup: Bool = false) {
        guard settingsNotice == nil else { return }
        showSettingsNotice(title: title, message: message, cancelTitle: "Cancel",
                           alternatives: choices, destructive: destructive, choiceDetails: details, duringSetup: duringSetup)
    }

    func confirmSetting(_ title: String, message: String, action: String, destructive: Bool = false, duringSetup: Bool = false,
                        apply: @escaping () -> Void) {
        confirmSetting(title, message: message, choices: [(action, apply)], destructive: destructive ? [action] : [], duringSetup: duringSetup)
    }

    // MARK: - Storage Keys for Persistence
    enum StorageKeys {
        static let savedGameFolder = "NXNative_SavedGameFolder"
        static let lastPortingFinishSeconds = "NXLibrary.lastPortingFinishSeconds"
        static let savedLibraryFolder = "NXNative_SavedLibraryFolder"
        static let savedProdKeysPath = "NXNative_SavedProdKeysPath"
        static let savedIconAppearanceMode = "NXNative_SavedIconAppearanceMode"
        static let allowUntestedToolchain = "NXLibrary_AllowUntestedToolchain"
        static let setupCompleted = "NXLibrary_SetupCompleted"
        static let setupPage = "NXLibrary_SetupPage"
        static let legacySetupSteamChoice = "NXLibrary_SetupSteamChoice"
        static let setupSteamChoice = "NXLibrary_SetupSteamExplicitChoice"
        static let onboardingNewsSeen = "OortNX_WhatsNew_0_4"
        static let onboardingFreshProfile = "OortNX_OnboardingFreshProfile"
        static let onboardingExclusions = "OortNX_Onboarding_ExcludedLocalGames"
        /// A chosen engine folder other than ~/nxnative.
        static let savedEngineFolder = "NXLibrary_EngineFolder"
        static let newestEngineChoice = "NXLibrary_NewestEngineChoice"
    }

    // MARK: - Workspace & Paths
    @Published var defaultInstallPath: String = ""

    /// The shell's update dialog owns input; screens leave the keyboard to it.
    var appUpdateDialogOwnsInput = false
    @Published var profileOwnsInput = false
    var shellDialogOwnsInput: Bool { appUpdateDialogOwnsInput || cloudQuitRequested || profileOwnsInput || router?.isPalettePresented == true
        || noticeFocus.isActive || launchOverlay != nil }
    /// "Welcome to Arcane" is on screen, until its fade has ended: screens' own keyboard monitors let Return and
    /// the arrows go to it, and Spotlight holds its entrance until it has gone.
    @Published var isWelcomeOpen = false
    /// The window is still taking its launch mode (Start in fullscreen): Spotlight's entrance waits for it, so the
    /// fullscreen transition never cuts the flight (`StartupWindowObserver`, at most 4 s from attachment).
    @Published var isWindowSettling = true
    /// A home screen (Spotlight or Collection) has shown since launch: Spotlight's entrance plays only on the first.
    var homeSeen = false

    var gameAppsFolder: URL {
        libraryFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    }

    // MARK: - Drag & Drop & ZIP
    @Published var dropErrorMessage: String? = nil

    // MARK: - Library
    @Published private(set) var libraryGames: [PortedGame] = [] {
        didSet {
            refreshInstalledEngineVersions()
        }
    }
    /// Results of the last background scan; tiles never probe app bundles, sources or Git.
    @Published private(set) var installedVersions: [UUID: InstalledVersion.Status] = [:]
    var gamesWithFilesHere: Set<UUID> { cloudLibrary.localSourceIDs }
    private var installedVersionsRefresh: Task<Void, Never>?

    @discardableResult
    func refreshInstalledEngineVersions(reset: Bool = false) -> Task<Void, Never> {
        installedVersionsRefresh?.cancel()
        if reset { installedVersions = [:] }
        let games = libraryGames
        let checkout = setup.nxnativePath
        let versions = setup.versions
        let selected = versions.expected
        let place = Place(UUID())
        let profile = Profile(localProfiles?.active?.id ?? UUID())
        let generation = Generation(UUID())
        let engine: any EngineAdapter = MacNXNative(place: place, checkout: checkout,
            prescribed: versions.reference, expected: selected, apps: games.reduce(into: [:]) { apps, game in
                if game.url.pathExtension.lowercased() == "app" && game.cloudImportPending != true {
                    apps[Installation(game.id)] = game.url
                }
            })
        let task = Task.detached(priority: .utility) { [weak self] in
            var versions: [UUID: InstalledVersion.Status] = [:]
            var local: Set<UUID> = []
            for game in games {
                guard !Task.isCancelled else { return }
                let binding = EngineBinding(place, Entry(game.id), installation: Installation(game.id),
                                            profile: profile, generation: generation)
                versions[game.id] = (try? await engine.game(binding).embedded.status) ?? .unknown
                if GameResourceState.sourcesAvailable(for: game) { local.insert(game.id) }
            }
            await MainActor.run { [weak self, versions, local] in
                guard !Task.isCancelled, let self,
                      self.installedVersions != versions || self.gamesWithFilesHere != local else { return }
                self.cloudLibrary.localSourceIDs = local
                self.installedVersions = versions
            }
            await Self.warmPlayerEngines(games.filter(\.isPlayableLocally).map(\.url), path: checkout)
        }
        installedVersionsRefresh = task
        return task
    }
    @Published private(set) var catalogGames: [CatalogGame] = []
    private(set) var catalogSnapshot = CatalogDocument()
    @Published private(set) var catalogSourceConfigurations: [CatalogSourceConfiguration] = []
    @Published private(set) var personalizations = CatalogPersonalizations.empty
    /// Finished file operations whose catalog save must still be retried.
    @Published var catalogBuildRecoveries = CatalogBuildRecoveries()
    @Published var libraryFolder: URL?
    var defaultGameAppsPath: String { URL(fileURLWithPath: defaultInstallPath).appendingPathComponent("Applications").path }
    var legacyGameAppsPath: String? { AppData.preferences.string(forKey: StorageKeys.savedLibraryFolder) }
    /// First use asks where to find existing games and install new ones; later visits keep that choice.
    var requiresGameAppsFolderChoice: Bool {
        !setupCompleted && settingsStore?.settings.launcherChoices.gameAppsPath == nil && legacyGameAppsPath == nil
    }
    @Published var isScanningLibrary: Bool = false
    /// Non-blocking scan details shown beside Library refresh, never an automatic launch dialog.
    @Published var libraryScanWarnings: [String] = []
    @Published var gameForSettingsSheet: PortedGame? = nil
    /// The Steam game whose Options are open (`SteamOptionsView`); never open with `gameForSettingsSheet`.
    @Published var steamOptionsGame: CatalogGame? = nil
    /// Any game's Options are open: the screens underneath stop reading input.
    var isGameOptionsOpen: Bool { gameForSettingsSheet != nil || steamOptionsGame != nil }
    /// The game whose Options are open, for the panels' own key monitors.
    var optionsGameID: UUID? { gameForSettingsSheet?.id ?? steamOptionsGame?.id }
    /// Where the open Game options came from; decides its rows (Move is Spotlight-only).
    @Published var gameOptionsOrigin: GameOptionsOrigin = .collection
    /// Game options opens straight on its Mods panel (the Details page's Mods band).
    @Published var gameOptionsOpensMods = false
    /// The running game whose Close Game confirmation is open. The shell draws the dialog.
    @Published var gameToClose: PortedGame? = nil
    @Published var closeGameFocus: SeleneConfirmButton = .cancel
    @Published var storageSnapshot: StorageSnapshot? = nil
    var storageUsage: StorageUsage? { storageSnapshot?.total }
    @Published var isCalculatingStorage: Bool = false
    @Published private(set) var isCleaningStorage = false
    @Published private(set) var storageCleanupMessage: String?
    var storageRefreshRequested = false

    var canCleanStorage: Bool {
        !isBuilding && !isCheckingCloudBuild && !isCleaningStorage && !isCalculatingStorage && !isUpdatingApp && !cloudLibrary.isWorking
    }
    @Published var showSetupCheck: Bool = false
    /// The Setup check's state and installs; lives with the app so an install survives closing the screen.
    lazy var setupCheck = SetupCheckModel(viewModel: self)
    @Published private(set) var firstRunSetup = FirstRunSetup() {
        didSet {
            AppData.preferences.set(firstRunSetup.isCompleted, forKey: StorageKeys.setupCompleted)
            if let page = firstRunSetup.pageToRemember {
                AppData.preferences.set(page, forKey: StorageKeys.setupPage)
            } else {
                AppData.preferences.removeObject(forKey: StorageKeys.setupPage)
            }
            if let choice = firstRunSetup.steamChoiceToRemember {
                AppData.preferences.set(choice, forKey: StorageKeys.setupSteamChoice)
            } else {
                AppData.preferences.removeObject(forKey: StorageKeys.setupSteamChoice)
            }
            if firstRunSetup.isCompleted {
                AppData.preferences.removeObject(forKey: StorageKeys.legacySetupSteamChoice)
            }
        }
    }
    var setupCompleted: Bool { firstRunSetup.isCompleted }
    var isGuidedSetupOpen: Bool { showSetupCheck && firstRunSetup.page.isGuided }
    @Published var lastError: String? = nil
    @Published var alertMessage: String? = nil
    @Published var buildLogURL: URL? = nil
    @Published var currentBuildGameID: UUID? = nil
    @Published var lastBuildGameID: UUID? = nil

    // MARK: - Build State
    /// What Add Game and its Porting step show of a build; the home reads only the three values here.
    private(set) lazy var porting = PortingModel(app: self)
    @MainActor private(set) lazy var gameInbox = GameInboxModel(app: self)
    /// The Switch Setup: engine, keys, environment and the Metal gate (`SetupModel`), observed on its own.
    private(set) lazy var setup = SetupModel(app: self)
    /// A built game's saved choices for its next launch (`RuntimeSettingsModel`).
    private(set) lazy var runtimeSettings = RuntimeSettingsModel(app: self)
    /// What a game's cheats are and what to do with added files (`CheatsModel`).
    private(set) lazy var cheats = CheatsModel(app: self)
    /// The game's app icon in Finder and the Dock (`AppIconModel`), observed by Change artwork.
    private(set) lazy var appIcon = AppIconModel(app: self)
    @MainActor private(set) lazy var libraryRefresh = LibraryRefreshModel(app: self)
    /// The Nintendo store's data for each game, in the app language (`StoreMetadataModel`), observed by the screens
    /// that show it.
    private(set) lazy var store = StoreMetadataModel(app: self)
    @Published var isBuilding: Bool = false
    @Published var buildQueue: [UUID] = []
    /// The running (or just finished) porting folded into one overall fraction for the home.
    @Published var portingProgress: PortingProgress? = nil
    /// The game ported last in this session leads Spotlight's row until quit.
    @Published var frontGameID: UUID? = nil
    /// The Steam games seen downloading this session lead the row after it, until quit.
    @Published private(set) var sessionDownloads = SessionDownloads()
    /// Spotlight's Delete on a failed porting asks first.
    @Published var gameToRemove: PortedGame? = nil
    @Published var removeGameFocus: SeleneConfirmButton = .cancel
    @Published var logs: [LogEntry] = []
    /// The existing Selene dialog offers retrying the ready app, or closing it.
    @Published var gameWithInstallFailure: PortedGame? = nil
    var installFailureDetail = ""
    @Published var installFailureFocus: SeleneConfirmButton = .cancel

    var canRetryReadyInstall: Bool {
        porting.buildState == .failed && porting.portingFailureReason == nil
            && (libraryGames.contains { $0.id == lastBuildGameID && $0.pendingInstall != nil }
                || catalogBuildRecoveries.values.contains { $0.id == lastBuildGameID && $0.pendingInstall != nil })
    }
    @Published private(set) var iconAppearanceMode: AppIconAppearanceMode = .auto
    static var legacyDockIcon: String? { AppData.preferences.string(forKey: StorageKeys.savedIconAppearanceMode) }
    func useDockIcon(_ value: String?) {
        let next: AppIconAppearanceMode = (value ?? Self.legacyDockIcon) == AppIconAppearanceMode.mono.rawValue ? .mono : .auto
        guard next != iconAppearanceMode else { return }
        iconAppearanceMode = next
        updateDockIcon()
    }

    // MARK: - Navigation
    @Published var librarySelection = LibrarySelectionState()
    /// Spotlight's row selection and focus; lives here so it survives Details and back.
    @Published var spotlight = SpotlightState()
    var router: AppRouter?
    /// GameTDB box covers for Collection and More like this.
    lazy var boxArt = BoxArtService(artwork: ArtworkStore(),
                                           index: GameTDBStore(directory: core.appendingPathComponent("metadata")))
    /// Bumps when a new GameTDB index arrives, so covers that found nothing look again.
    @Published private(set) var boxArtIndexVersion = 0
    @Published var launchingGameId: UUID? = nil
    /// The launch screen: shown on Play, `isReady` once the game's window is up (or the probe gave up).
    @Published var launchOverlay: LaunchOverlayState? = nil {
        didSet {
            SoundEffectService.shared.setQuietLaunch(
                launchOverlay != nil && (settingsStore?.settings.quietLaunch ?? true))
        }
    }
    var launchProbeTask: Task<Void, Never>?

    var playSessionStore: PlaySessionStore?
    @MainActor lazy var macShortcuts = MacShortcutAdapter(app: self)
    @MainActor lazy var playRouter = GamePlay([NXNativePlayConnector(app: self), SteamPlayCoordinator.shared, macShortcuts])
    var localProfiles: LocalProfileStore?
    private var profileNextendoAccounts: [UUID: NextendoSettings] = [:]
    @MainActor var profileNextendo: NextendoSettings? {
        guard localProfiles?.guest == nil, let id = localProfiles?.active?.id else { return nil }
        if let account = profileNextendoAccounts[id] { return account }
        let account = NextendoSettings(store: NextendoLaunch.tokenStore(profileID: id, originalID: localProfiles?.originalID)) { [weak self] result in
            Task { @MainActor in
                let level: LogLevel = (200..<300).contains(result.code) ? .info : .warning
                self?.logs.append(LogEntry(level: level, message: "Nextendo: \(result.route) · \(result.code)"))
            }
        }
        profileNextendoAccounts[id] = account
        return account
    }
    var usesSharedNextendo: Bool { localProfiles?.active?.id == localProfiles?.originalID }
    var settingsStore: AppSettingsStore?

    let availableLanguages: [(code: String, label: String)] = [
        ("auto", "Game Default"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("ja", "Japanese"),
        ("pt-BR", "Portuguese (Brazil)"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("zh-Hans", "Chinese (Simplified)"),
        ("ko", "Korean")
    ]

    static let defaultPinnedEngineCommit = "99224562186a8fdb7e97afb872319a21941ec317"
    let engineOverride = SetupActions.engineOverride(in: Bundle.main.infoDictionary)
    let core = AppData.supportRoot
    let catalogRepository: CatalogRepository
    /// Sizes of built apps are remembered between launches, so a scan walks only new or rebuilt apps.
    lazy var importService = ImportService(sizeCache: AppSizeCache(file: core.appendingPathComponent("app-sizes.json")))
    let launchService = LaunchService()
    weak var runningGameMonitor: RunningGameMonitor?
    let developmentOperations = DevelopmentOperationStore()
    lazy var storageManager = StorageManager()
    var gameSaveLaunches: [UUID: (pid: pid_t, date: Date?, profile: UUID?)] = [:]
    let sourceCatalog = SourceCatalog()
    lazy var workspaceManager = WorkspaceManager(root: core.appendingPathComponent("workspaces"))
    var libraryScanRequest = LibraryScanRequest.standalone
    var pendingLibraryScan: LibraryScanRequest?

    init(settingsStore: AppSettingsStore, catalog: CatalogDocument, repository: CatalogRepository,
         localProfiles: LocalProfileStore? = nil, registerNotifications: Bool = true) {
        self.catalogRepository = repository
        self.settingsStore = settingsStore
        self.localProfiles = localProfiles
        self.cloudLibrary = CloudLibraryModel(activation: settingsStore.settings.launcherChoices.cloudActivation)
        applyCatalog(catalog)
        saveGate.onActivityChange = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.hasActiveSaveOperations = self.saveGate.hasActiveOperations
                self.cloudLibrary.appInstallWake?.yield(())
                MainActor.assumeIsolated { self.startNextCloudOperation() }
                self.porting.scheduleNextBuild()
            }
        }
        let startup = settingsStore.settings
        cloudConnectionObservation = cloudLibrary.$isChangingConnection.dropFirst().sink { [weak self] changing in
            if !changing { self?.porting.scheduleNextBuild() }
        }
        let didCompleteSetup = AppData.preferences.bool(forKey: StorageKeys.setupCompleted)
        // 0.3.0 wrote true on detection, but only the player could write false.
        let legacySteamChoice = AppData.preferences.object(forKey: StorageKeys.legacySetupSteamChoice) as? Bool
        let explicitSteamChoice = AppData.preferences.object(forKey: StorageKeys.setupSteamChoice) as? Bool
        self.firstRunSetup = FirstRunSetup(completed: didCompleteSetup,
                                           savedPage: AppData.preferences.string(forKey: StorageKeys.setupPage),
                                           savedSteamChoice: explicitSteamChoice ?? (legacySteamChoice == false ? false : nil))
        self.showSetupCheck = !didCompleteSetup
        if firstRunSetup.page.isGuided { AppData.preferences.set(true, forKey: StorageKeys.onboardingFreshProfile) }

        // 1. Resolve safe root directory (anchored to SSD / Bundle, NEVER "/")
        let root = SystemDetector.shared.resolveRootDirectory()
        self.defaultInstallPath = root.path

        // The launcher's old ~/Games default is not a Mac-app library.
        let oldGamesDefault = root.appendingPathComponent("Games").standardized.path
        if let savedLib = startup.launcherChoices.gameAppsPath ?? legacyGameAppsPath,
           savedLib != oldGamesDefault, !savedLib.isEmpty, savedLib != "/" {
            self.libraryFolder = URL(fileURLWithPath: savedLib)
        } else {
            self.libraryFolder = root.appendingPathComponent("Applications")
            AppData.preferences.removeObject(forKey: StorageKeys.savedLibraryFolder)
        }

        // Restore user preferences
        useDockIcon(startup.launcherChoices.dockIconAppearance)

        setup.restoreBuildInputs(automatic: true,
                                 readKeys: !AppData.preferences.bool(forKey: StorageKeys.onboardingFreshProfile))
        if !AppData.profile.isDevelopment && startup.checkEngineAtLaunch && !firstRunSetup.page.isGuided {
            setup.refreshCompatibility()
        }

        // Keep Game files as a picker preference, not an active Add game draft.
        // Assigning selectedGameFolder scans it; launch refresh only concerns installed apps.

        recoverSavesAtStartup()
        if !AppData.profile.isDevelopment {
            let games = libraryGames
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let manager = StorageManager()
                for game in games {
                    guard let cache = try? manager.cacheURL(for: game, protecting: games) else { continue }
                    let target = CloudArchiveGame(titleID: game.titleId ?? "", locations: [.cache: cache],
                                                  installedApp: game.cloudImportPending == true ? nil : game.url)
                    do { try CloudGameArchive.recoverInterruptedFree(at: cache, for: target) }
                    catch {
                        let message = error.localizedDescription
                        DispatchQueue.main.async { [weak self] in self?.logs.append(LogEntry(level: .error, message: message)) }
                    }
                }
            }
        }
        if !setupCompleted && firstRunSetup.page == .games { prepareInitialGameAppsFolder() }
        if (!firstRunSetup.page.isGuided && startup.refreshLibraryAtLaunch) ||
            (!setupCompleted && firstRunSetup.page == .games) { scanLibrary(using: catalog) }
        updateDockIcon()
        // Register notification-click routing at launch without asking for permission.
        if registerNotifications { _ = NotificationService.shared }

        let held = PendingInstaller.keptFolders(libraryGames)
        let staging = AppData.profile.automaticStagingFolders(
            appFolders: [gameAppsFolder] + libraryGames.map { $0.url.deletingLastPathComponent() })
        DispatchQueue.global(qos: .utility).async {
            PortingModel.sweepStaleBuildTemp(in: staging, keeping: held)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.porting.buildService?.terminateNow()
            self?.cloudLibrary.stopRemoteControl()
            if let temp = self?.porting.buildTempDirectory {
                try? FileManager.default.removeItem(at: temp)
            }
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-setup") {
            self.showSetupCheck = true
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-build") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.porting.previewBuild()
            }
        }
        #endif
    }

    // MARK: - Dynamic Dock Icon
    func updateDockIcon() {
        // The system draws the bundle icon in light, dark and tinted appearances.
        guard iconAppearanceMode == .mono else {
            NSApplication.shared.applicationIconImage = nil
            return
        }
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let url = Bundle.main.url(forResource: isDark ? "AppIcon-Particles-Dark" : "AppIcon-Particles-Light",
                                     withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = img
        }
    }

    /// Fetches GameTDB's index at launch when it is missing or 30 days old.
    func refreshBoxArtIndex() {
        let service = boxArt
        Task { @MainActor [weak self] in
            if await service.refreshIndexIfNeeded() { self?.boxArtIndexVersion += 1 }
        }
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func advanceSetupToGames() {
        guard showSetupCheck else { return }
        if !setupCompleted { prepareInitialGameAppsFolder() }
        importExistingBuilds()
        firstRunSetup.advance()
    }

    func returnToSetupRequirements() { firstRunSetup.goBack() }

    /// The Porting card on the first launch's `found` page.
    func openPortingFromFound() {
        guard showSetupCheck, !setupCompleted else { return }
        firstRunSetup.openPorting()
    }

    /// The Steam switch on `found`; the shell applies it when the first launch finishes.
    func chooseSteamOnFound(_ on: Bool) { firstRunSetup.chooseSteam(on) }

    /// Back from the requirements to `found`, during the first launch only.
    func returnToFound() { firstRunSetup.returnToFound() }

    /// Open library on `found`. Ported apps already in the Game apps folder join the library, which
    /// turns the Switch source on; without them it stays off until the player chooses Porting.
    func finishFromFound(importPorted: Bool) {
        guard showSetupCheck, !setupCompleted else { return }
        if importPorted {
            prepareInitialGameAppsFolder()
            importExistingBuilds()
        }
        completeSetup()
    }

    private func prepareInitialGameAppsFolder() {
        do {
            try GameAppDestination.prepareInitialFolder(gameAppsFolder,
                hasExplicitChoice: settingsStore?.settings.launcherChoices.gameAppsPath != nil || legacyGameAppsPath != nil)
        } catch {
            logs.append(LogEntry(level: .warning, message: L10n.format("Could not prepare the default Game apps folder: %@", [String(describing: error.localizedDescription)])))
        }
    }

    func completeSetup() {
        AppData.preferences.set(true, forKey: StorageKeys.onboardingNewsSeen)
        prepareInitialGameAppsFolder()
        AppData.preferences.set(gameAppsFolder.path, forKey: StorageKeys.savedLibraryFolder)
        firstRunSetup.finish()
        showSetupCheck = false
        logs.append(LogEntry(level: .success, message: L10n.text("Setup completed.")))
    }

    func reopenSetup() {
        guard !isBuilding, !isUpdatingApp else { return }
        if router?.requestSettingsDeparture({ [weak self] in self?.reopenSetup() }) == true { return }
        firstRunSetup.goBack()
        showSetupCheck = true
    }

    func reopenOnboarding() {
        guard !isBuilding, !isUpdatingApp else { return }
        firstRunSetup.openTour()
        showSetupCheck = true
    }

    @discardableResult func moveOnboarding(_ offset: Int) -> Bool { firstRunSetup.moveTour(offset) }

    func finishOnboarding() {
        AppData.preferences.set(true, forKey: StorageKeys.onboardingNewsSeen)
        firstRunSetup.finish()
        showSetupCheck = false
    }

    func cleanStorage(games: [PortedGame], caches: Bool) {
        isCleaningStorage = true
        storageCleanupMessage = nil
        let manager = storageManager
        let protectedGames = libraryGames
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var removed = 0
            var failures: [String] = []
            for game in games {
                do {
                    if caches {
                        if try manager.deleteCache(for: game, protecting: protectedGames) { removed += 1 }
                    } else {
                        if try manager.deleteLogs(for: game) { removed += 1 }
                    }
                } catch { failures.append("\(game.name): \(error.localizedDescription)") }
            }
            let message = caches
                ? (removed == 0 ? L10n.text("No build caches were deleted.") : L10n.count("Deleted %lld build caches. Future rebuilds may take longer.", removed, arguments: []))
                : (removed == 0 ? L10n.text("No logs were deleted.") : L10n.count("Deleted logs for %lld games.", removed, arguments: []))
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCleaningStorage = false
                self.storageCleanupMessage = message
                self.logs.append(LogEntry(level: .info, message: message))
                if !failures.isEmpty {
                    self.showSettingsNotice(title: L10n.text("Some files were not deleted"), message: failures.joined(separator: "\n"))
                }
                self.refreshStorageUsage()
                self.porting.scheduleNextBuild()
            }
        }
    }

    func applyCatalog(_ document: CatalogDocument) {
        catalogSnapshot = document
        refreshProfileFavorites()
        // Published only when a game is new, so a rescan that changes nothing redraws nothing for it.
        var downloads = sessionDownloads
        if downloads.note(document.games) { sessionDownloads = downloads }
        catalogSourceConfigurations = document.sources
        personalizations = CatalogPersonalizations(document: document)
        if !buildQueue.isEmpty { porting.scheduleNextBuild() }
    }

    func refreshProfileFavorites() {
        let document = catalogSnapshot
        let favorites = localProfiles.flatMap { store in
            store.active.flatMap { $0.id == store.originalID ? nil : $0.favorites }
        }
        catalogGames = document.games.map { original in
            guard let favorites else { return original }
            var game = original
            game.setFavorite(favorites.contains(game.id))
            return game
        }
        libraryGames = document.nxnativeGames.map { original in
            guard let favorites else { return original }
            var game = original
            game.isFavorite = favorites.contains(game.id)
            return game
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var cloudSavesPreferences = CloudSavesPreferences()
}
