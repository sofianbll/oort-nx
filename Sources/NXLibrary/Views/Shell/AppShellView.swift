import SwiftUI
import AppKit
import Combine
import NXLibraryCore
import ArcanePorting

struct AppShellView: View {
    @StateObject var viewModel: AppViewModel
    /// The Setup (`SetupModel`): the update offer names the Xcode a release needs.
    @ObservedObject var setup: SetupModel
    /// The Nintendo store's data (`StoreMetadataModel`): descriptions, screenshots and names shown here.
    @ObservedObject var store: StoreMetadataModel
    @StateObject var router: AppRouter
    @StateObject var settings: AppSettingsStore
    @StateObject var playSessions = PlaySessionStore()
    @ObservedObject var profiles: LocalProfileStore
    @State var profileFlow: ProfileFlow?
    @State var profilePageFocus: ProfilePage.Focus?
    @State var steamBlocksIdlePresence = false
    @State var onlinePlayers: [String: Int] = [:]
    static let onlineCounts = NextendoOnlineCounts()
    @StateObject var artwork = ArtworkStore()
    @StateObject var runningGames = RunningGameMonitor()
    @StateObject var sessionCard = SessionCardPresenter()
    @StateObject var updater = AppUpdater()
    @StateObject var sources: CatalogSourcesModel
    private let igdb: IGDBSettings
    private let modStoreHost: ModStoreHost
    @StateObject var nativeMenus = NativeMenuCommands.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject var localization = AppLocalization.shared
    @State var gestureKeyMonitor: Any?
    @State var cloudQuitFocus: SeleneConfirmButton = .cancel
    /// Rescans the Steam source when Steam rewrites a manifest (a download finishing, a game installed or removed).
    @State var steamWatcher = SteamManifestWatcher()
    @State var setupSourceEntryID: UUID?
    /// "Welcome to Arcane" is on screen (once, after the update from NX Library).
    @State var showsWelcome = false
    /// Closed in this session: never presented again, even while its fade has not yet saved it as shown.
    @State var welcomeDismissed = false
    /// Dismisses the Close Game confirmation when its game quits by itself.
    @State var closeGameWatch: AnyCancellable?
    @State var sharedBackdrop: SeleneBackdropRequest?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @MainActor init(state: AppShellState) {
        _sources = StateObject(wrappedValue: state.sources)
        _settings = StateObject(wrappedValue: state.settings)
        _viewModel = StateObject(wrappedValue: state.viewModel)
        _setup = ObservedObject(wrappedValue: state.viewModel.setup)
        _store = ObservedObject(wrappedValue: state.viewModel.store)
        _router = StateObject(wrappedValue: state.router)
        _profiles = ObservedObject(wrappedValue: state.profiles)
        igdb = state.igdb
        _profileFlow = State(initialValue: state.viewModel.profileOwnsInput
            ? ProfileFlow(page: .picker, selected: state.profiles.startupSelection(state.settings.settings.profileStartup), atStartup: true) : nil)
        modStoreHost = state.modStoreHost
        _showsWelcome = State(initialValue: state.opensWithWelcome)
    }

    func updateLocale() {
        let previousLanguage = AppLocalization.shared.context.language
        AppLocalization.shared.configure(settings.settings)
        if previousLanguage != AppLocalization.shared.context.language {
            store.refreshLocalizedMetadata()
        }
    }

    var backdropStyle: SeleneBackdropStyle {
        SeleneBackdropStyle(palette: theme.palette,
                            wallpaperURL: theme.wallpaper(for: settings.settings.wallpaperID)?.url,
                            sizing: settings.settings.backgroundSizing,
                            animated: settings.settings.animatedBackground,
                            brightness: settings.settings.wallpaperBrightness)
    }

    func updateSharedBackdrop(_ request: SeleneBackdropRequest?) {
        if let request {
            sharedBackdrop = request
        } else if var last = sharedBackdrop {
            // No page requests a background: keep its last frame, without a live clock.
            last.still = true
            sharedBackdrop = last
        }
    }

    /// Spotlight or Collection: the screens that pick a game.
    var isHomeRoute: Bool {
        router.route == .library || router.route.isCollection
    }

    /// A shell dialog is open; menu commands wait for it.
    var isCloseGameOpen: Bool {
        viewModel.gameToClose != nil || viewModel.gameToRemove != nil || showsUpdateOffer || showsInstallFailure
            || showsSettingsNotice || viewModel.cloudLibraryGameID != nil || viewModel.cloudQuitRequested
    }
    var showsInstallFailure: Bool {
        viewModel.gameWithInstallFailure != nil && !viewModel.showSetupCheck
            && viewModel.launchOverlay == nil && viewModel.gameToClose == nil && viewModel.gameToRemove == nil
    }
    /// The update dialog waits for the Setup check.
    var showsUpdateOffer: Bool {
        (updater.offer != nil || updater.isCheckPresented) && !viewModel.showSetupCheck
            && !showsInstallFailure && viewModel.gameToClose == nil && viewModel.gameToRemove == nil
            && viewModel.launchOverlay == nil && !router.isScreenshotViewerOpen
    }
    var showsSettingsNotice: Bool {
        viewModel.settingsNotice != nil && !viewModel.showSetupCheck
            && !router.isScreenshotViewerOpen && viewModel.launchOverlay == nil
            && viewModel.gameToClose == nil && viewModel.gameToRemove == nil
            && !showsInstallFailure && !showsUpdateOffer
    }

    var reduceMotion: Bool {
        settings.settings.reduceMotion || accessibilityReduceMotion
    }

    /// Native alerts and file pickers own input, including while their parent has no key window.
    /// Check at delivery: controller actions under a dialog are dropped, never replayed after it closes.
    var nativeDialogOwnsInput: Bool {
        viewModel.alertMessage != nil || NSApp.modalWindow != nil
            || NSApp.keyWindow?.isSheet == true || NSApp.keyWindow?.attachedSheet != nil
            || NSApp.mainWindow?.attachedSheet != nil
    }

    var nativeMenuAvailability: NativeMenuAvailability {
        let general = !viewModel.showSetupCheck && !showsWelcome && profileFlow == nil
            && !isCloseGameOpen && !router.isScreenshotViewerOpen && !router.isSearchPresented
            && router.activityCenterFocus == nil
            && !viewModel.isGameOptionsOpen && viewModel.launchOverlay == nil && !nativeDialogOwnsInput
        let gameCommands = general && !router.isMenuPresented && router.sortMenu == nil
        let game = gameCommands ? viewModel.currentFocusedGame : nil
        let focused = gameCommands ? viewModel.currentFocusedCatalogGame : nil
        let steam = focused?.integration == .steam ? focused : nil
        let shortcut = focused?.macShortcut
        // Steam only has a Spotlight page; a Mac shortcut has no details.
        return NativeMenuAvailability(general: general,
            addMacApp: general && viewModel.macShortcuts.canEdit,
            play: game?.isPlayableLocally == true || steam.map(SteamPlayCoordinator.shared.canPlay) == true || shortcut != nil,
            details: isHomeRoute && focused != nil && shortcut == nil && (steam == nil || router.route == .library),
            options: game != nil || steam != nil,
            catalogRecovery: general && !viewModel.isBuilding && !viewModel.catalogBuildRecoveries.isEmpty)
    }

    /// A game the session card or the launch screen names: a library build, else a Steam game of the catalog.
    func playedGame(_ id: UUID) -> PlayedGame? {
        if let game = viewModel.libraryGames.first(where: { $0.id == id }) { return .nxnative(game) }
        return viewModel.catalogGames.first { $0.id == id && $0.integration == .steam }.map(PlayedGame.steam)
    }

    /// The launch screen, in its own window over every app and Space (`LaunchCoverWindow`). Its window has its own
    /// SwiftUI root: the canvas and the locale are given to it here.
    var launchCover: some View {
        LaunchCoverWindow(state: viewModel.launchOverlay, onPrepared: { SteamPlayCoordinator.shared.launchCoverPrepared(for: $0) }) { state in
            LaunchScreenView(state: state, viewModel: viewModel, store: viewModel.store, artwork: artwork,
                             settings: settings.settings, reduceMotion: reduceMotion)
                .id(state.game.id)
                .seleneCanvasRoot()
                .environment(\.locale, localization.context.formatLocale)
                .environment(\.nxAppLocale, localization.context)
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Game options, Add game and the console open and close alike: a fade with a slight scale.
    var overlayTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
    }

    /// The profile picker over the screen: Selene's Captures blur (40) under its 65 % veil.
    static let profileOverlayBlur = SeleneOverlayStyle.deep.backdropBlur

    var contentBlur: CGFloat {
        if let flow = profileFlow, !flow.atStartup { return Self.profileOverlayBlur }
        // A card or the Power pills open over the control center: the page behind must not read through them.
        if router.isMenuPresented, router.menuSelection.isSubmenuOpen { return Self.profileOverlayBlur }
        return !viewModel.isGameOptionsOpen && !router.route.isOverlay ? 0 : SeleneOverlayStyle.options.backdropBlur
    }

    var currentBackdropCover: ShellBackdropCover {
        .resolve(setup: viewModel.showSetupCheck, welcome: showsWelcome,
                 themePicker: router.isMenuPresented && router.isThemePickerOpen)
    }

    var fullScreenCover: Bool { currentBackdropCover.covers(0) }

    func opacityBelowCover(_ priority: Double) -> Double {
        currentBackdropCover.covers(priority) ? 0.001 : 1
    }

    private var macShortcutCommands: some View {
        nativeGameCommands
            .onReceive(NotificationCenter.default.publisher(for: .nxLibraryAddMacApp)) { _ in
                guard nativeMenuAvailability.addMacApp else { return }
                router.closeMenu()
                viewModel.macShortcuts.chooseApp()
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard isHomeRoute, !router.isMenuPresented, nativeMenuAvailability.addMacApp else { return false }
                return viewModel.macShortcuts.acceptDrop(urls)
            }
    }

    var body: some View {
        macShortcutCommands
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryCheckAppUpdates)) { _ in
            guard nativeMenuAvailability.general else { return }
            router.closeMenu()
            updater.checkNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenMenu)) { _ in
            guard nativeMenuAvailability.general else { return }
            router.isMenuPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenSettings)) { _ in
            guard profileFlow == nil, !isCloseGameOpen, !router.isScreenshotViewerOpen, !viewModel.isGameOptionsOpen else { return }
            router.closeMenu()
            router.openSettings(.startUp)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryRetryCatalogSave)) { _ in
            guard nativeMenuAvailability.catalogRecovery else { return }
            viewModel.retrySavingBuildResults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenConsole)) { _ in
            guard profileFlow == nil, !isCloseGameOpen, !router.isScreenshotViewerOpen, !viewModel.isGameOptionsOpen else { return }
            router.closeMenu()
            router.openConsole()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryPortingNoticeOpened)) { note in
            guard profileFlow == nil, !isCloseGameOpen, !router.isScreenshotViewerOpen, !viewModel.isGameOptionsOpen,
                  let id = (note.userInfo?["gameID"] as? String).flatMap(UUID.init(uuidString:)) else { return }
            router.closeMenu()
            if note.userInfo?["outcome"] as? String == "failed" {
                viewModel.lastBuildGameID = id
                viewModel.porting.reviewsFailureOnAddGame = true
                if router.route == .addGame {
                    viewModel.porting.addGameDidBecomeVisible(defaults: settings.settings.gameDefaults, returningFromBack: false)
                } else {
                    router.openAddGame()
                }
            } else {
                if !router.route.isOverlay || router.underlyingRoute != .library {
                    router.showLibrary()
                }
                router.requestSpotlightSelect(id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenLibrary)) { _ in
            guard profileFlow == nil, !isCloseGameOpen, !router.isScreenshotViewerOpen, !viewModel.isGameOptionsOpen else { return }
            router.closeMenu()
            router.showLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenAddGame)) { _ in
            guard profileFlow == nil, !isCloseGameOpen, !router.isMenuPresented, !router.isScreenshotViewerOpen,
                  !viewModel.isGameOptionsOpen else { return }
            router.closeMenu()
            openFreshAddGame()
        }
        .onExitCommand {
            if router.isScreenshotViewerOpen {
                // The viewer's key monitor closes it.
            } else if showsSettingsNotice {
                finishSettingsNotice()
            } else if showsInstallFailure {
                viewModel.gameWithInstallFailure = nil
            } else if viewModel.gameToClose != nil {
                viewModel.dismissCloseGame()
            } else if viewModel.gameToRemove != nil {
                viewModel.dismissRemoveGame()
            } else if showsUpdateOffer {
                updater.later()
            } else if viewModel.cloudLibraryGameID != nil {
                viewModel.cloudLibraryGameID = nil
            } else if profileFlow != nil {
                postProfileAction(.cancel)
            } else if router.route == .profile && !router.isMenuPresented {
                postProfileAction(.cancel)
            } else if viewModel.isGameOptionsOpen {
                // Game options steps back (dialog, then Edit details) or closes.
                NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: GamepadAction.cancel)
            } else if router.isMenuPresented {
                menuInput(.cancel)
            } else if router.isSearchPresented {
                // FindGameView's key monitor closes it.
            } else if isHomeRoute {
                // Spotlight and Collection handle Esc with their own key monitors.
            } else if case .settings = router.route {
                // SettingsView handles its own Esc.
            } else if case .addGame = router.route {
                // AddGameView handles its own Esc.
            } else if router.route == .gameInbox {
                // The page handles Esc with its own input route.
            } else if router.route == .integrations {
                // The integration page handles Esc with its own input route.
            } else if case .console = router.route {
                // ConsoleView handles its own Esc.
            } else {
                router.back()
            }
        }
        .onChange(of: viewModel.alertMessage) {
            presentLegacyNotice()
        }
        .onChange(of: viewModel.setupCompleted) { _, done in
            // The Steam switch of `found` applies however the first launch ends (Open library, Porting, Skip).
            if done, let choice = viewModel.firstRunSetup.steamChoice,
               choice != sources.configuration.isEnabled {
                sources.configure(enabled: choice, root: sources.discoveryRoot)
            }
            // A first setup finished today: this player starts on Arcane and never needs the welcome.
            if done, !showsWelcome, !settings.settings.welcomeArcaneShown {
                settings.settings = ArcaneWelcome.markShown(settings.settings)
            }
        }
        .task(id: welcomeTrigger) { await presentWelcomeIfDue() }
        .onChange(of: viewModel.settingsNotice?.id) { _, id in
            if id == nil {
                presentLegacyNotice()
                presentCloudNotice()
            }
        }
        .onReceive(viewModel.cloudLibrary.$queueFailure.combineLatest(viewModel.cloudLibrary.$startupFailure)) { queue, startup in
            if queue != nil || startup != nil { Task { @MainActor in presentCloudNotice() } }
        }
    }

    /// The current screen; under Add game or the console, the screen they were opened from.
    @ViewBuilder
    var content: some View {
        switch router.route.isOverlay ? router.underlyingRoute : router.route {
        case .library:
            SpotlightView(
                viewModel: viewModel,
                router: router,
                settings: settings,
                playSessions: playSessions,
                runningGames: runningGames,
                artwork: artwork,
                storeHost: modStoreHost
            )
            .environment(\.integrationBar, AnyView(integrationSurface(isBar: true)))
        case .collection, .profileCollection:
            CollectionView(
                viewModel: viewModel,
                router: router,
                settings: settings,
                playSessions: playSessions,
                artwork: artwork
            )
            .environment(\.integrationBar, router.route == .collection ? AnyView(integrationSurface(isBar: true)) : nil)
        case .integrations:
            integrationSurface(isBar: false)
        case .profile:
            if let profile = profiles.active {
                ProfilePage(profile: profile, viewModel: viewModel, history: playSessions, artwork: artwork,
                            nextendo: viewModel.profileNextendo, router: router, focus: $profilePageFocus,
                            isGuest: profiles.guest != nil,
                            onSwitch: { openProfile(.picker) })
                .id(profile.id)
                .task(id: profileFlow == nil) {
                    guard profileFlow == nil, router.route == .profile else { return }
                    let client = settings.settings.nextendoClientID ?? NextendoLaunch.buildClientID
                    if let nextendo = viewModel.profileNextendo, !nextendo.isBusy {
                        nextendo.check(clientID: client)
                    }
                }
            } else {
                Color.clear.onAppear { router.back() }
            }
        case .detail(let id):
            if let game = viewModel.libraryGames.first(where: { $0.id == id }) {
                GameDetailView(
                    viewModel: viewModel,
                    setup: viewModel.setup,
                    store: viewModel.store,
                    router: router,
                    settings: settings,
                    playSessions: playSessions,
                    runningGames: runningGames,
                    artwork: artwork,
                    game: game
                )
            } else {
                Color.clear
                    .onAppear { router.showLibrary() }
            }
        case .settings(let section):
            SettingsView(initialSection: section,
                         viewModel: viewModel,
                         settings: settings,
                         router: router,
                         artwork: artwork)
        case .gameInbox:
            GameInboxView(model: viewModel.gameInbox, router: router, showsHints: !showsSettingsNotice)
        case .addGame:
            // Never the underlying route; Add game is drawn over `content`.
            Color.clear
        case .console:
            // Never the underlying route; the console is drawn over `content`.
            Color.clear
        }
    }

    private func integrationSurface(isBar: Bool) -> IntegrationSurface {
        IntegrationSurface(router: router, sources: sources, app: viewModel, setup: setup,
                           cloud: viewModel.cloudLibrary, settings: settings, igdb: igdb,
                           nextendo: viewModel.profileNextendo, isBar: isBar)
    }
}

/// Selene's panel and back cues for the shell's overlays and routes.
struct SoundCueHooks: ViewModifier {
    @ObservedObject var router: AppRouter
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .nxSeleneImportFinished)) { _ in
                ThemeStore.shared.reloadWallpapers()
            }
            .onChange(of: router.isMenuPresented) { _, open in
                if open { SoundEffectService.shared.play(.openPanel) }
                else { SoundEffectService.shared.play(.close, legacy: .back) }
            }
            .onChange(of: viewModel.optionsGameID) { _, id in
                if id == nil { SoundEffectService.shared.play(.close, legacy: .back) }
                else { SoundEffectService.shared.play(.openPanel) }
            }
            .onChange(of: viewModel.gameToClose?.id) { _, id in
                if id != nil { SoundEffectService.shared.play(.alert) }
            }
            .onChange(of: viewModel.gameToRemove?.id) { _, id in
                if id != nil { SoundEffectService.shared.play(.alert) }
            }
            .onChange(of: viewModel.gameWithInstallFailure?.id) { _, id in
                if id != nil { SoundEffectService.shared.play(.alert) }
            }
            .onChange(of: router.route) { _, route in
                if router.isReturningFromBack {
                    SoundEffectService.shared.play(.back)
                } else if case .settings = route {
                    SoundEffectService.shared.play(.openPanel)
                }
            }
    }
}
