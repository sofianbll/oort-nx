import SwiftUI
import AppKit
import Combine
import NXLibraryCore

/// The shell's screen: its layers, overlays and modifiers, split from `body` for the type checker.
extension AppShellView {
    /// The screen plus the overlays that sit on it; split from `body` for the type checker.
    private var layers: some View {
        ZStack {
            let background = sharedBackdrop ?? SeleneBackdropRequest(style: backdropStyle, still: true)
            SeleneBackdrop(baseOpacity: background.baseOpacity, still: background.still, modsTint: background.modsTint)
                .environment(\.seleneBackdropStyle, background.style)
                .environment(\.seleneSharesBackdrop, false)
                .blur(radius: contentBlur)
            content
                // Game options, Add game and the console blur the screen behind instead of darkening it.
                .blur(radius: contentBlur)
                // Keep artwork/tiles drawn and warm, as during Spotlight's entrance, while the full page covers them.
                .opacity(fullScreenCover ? 0.001 : 1)
                .seleneOverlayOwnership(!fullScreenCover && !router.route.isOverlay && !viewModel.isGameOptionsOpen
                                        && !isCloseGameOpen && !router.isMenuPresented && !router.isSearchPresented && profileFlow == nil)
            if router.route == .addGame {
                AddGameView(viewModel: viewModel,
                            router: router,
                            artwork: artwork,
                            showsHints: settings.settings.showButtonHints,
                            reviewSelectionID: setupSourceEntryID)
                    .opacity(opacityBelowCover(0.8))
                    .seleneOverlayOwnership(!currentBackdropCover.covers(0.8) && !router.isMenuPresented && profileFlow == nil && !isCloseGameOpen)
                    .transition(overlayTransition)
                    .zIndex(0.8)
            }
            if router.route == .console {
                ConsoleView(viewModel: viewModel, router: router,
                            showsHints: settings.settings.showButtonHints)
                    .opacity(opacityBelowCover(0.8))
                    .seleneOverlayOwnership(!currentBackdropCover.covers(0.8) && !router.isMenuPresented && profileFlow == nil && !isCloseGameOpen)
                    .transition(overlayTransition)
                    .zIndex(0.8)
            }
            if router.isSearchPresented && (router.route == .library || router.route == .collection) {
                FindGameView(router: router, viewModel: viewModel, playSessions: playSessions,
                             artwork: artwork)
                    .opacity(opacityBelowCover(0.5))
                    .seleneOverlayOwnership(!currentBackdropCover.covers(0.5) && !router.isMenuPresented && profileFlow == nil && !isCloseGameOpen)
                    .transition(.opacity)
                    .zIndex(0.5)
            }
            if viewModel.showSetupCheck {
                Group {
                    if viewModel.firstRunSetup.page == .found {
                        FoundGamesSetupView(viewModel: viewModel, steamRoot: sources.discoveryRoot,
                                            steamEnabled: sources.configuration.isEnabled) { importPorted in
                            finishFromFound(importPorted: importPorted)
                        }
                    } else if viewModel.firstRunSetup.page == .games {
                        YourGamesSetupView(viewModel: viewModel,
                                           onChooseFiles: { chooseFirstGame(usingFolder: false) },
                                           onChooseFolder: { chooseFirstGame(usingFolder: true) },
                                           onFinish: {
                                               viewModel.completeSetup()
                                               router.navigate(to: .library)
                                           })
                    } else {
                        SetupCheckView(viewModel: viewModel, isFirstRun: !viewModel.setupCompleted)
                    }
                }
                    .transition(.opacity)
                    .zIndex(ShellBackdropCover.setup.priority)
                    .transformPreference(SeleneBackdropRequestKey.self) { $0?.priority = ShellBackdropCover.setup.priority }
            }
            if showsWelcome {
                ArcaneWelcomeView(steamEnabled: sources.configuration.isEnabled,
                                  steamRoot: sources.discoveryRoot,
                                  appsFolder: viewModel.gameAppsFolder,
                                  onAddSteam: {
                                      sources.configure(enabled: true, root: sources.discoveryRoot)
                                  },
                                  onExit: closeWelcome)
                    .opacity(opacityBelowCover(ShellBackdropCover.welcome.priority))
                    .allowsHitTesting(!currentBackdropCover.covers(ShellBackdropCover.welcome.priority))
                    .transition(.opacity)
                    // Below Setup: a Setup check that opens after the welcome owns the input, so it is drawn on top.
                    .zIndex(ShellBackdropCover.welcome.priority)
                    .transformPreference(SeleneBackdropRequestKey.self) { $0?.priority = ShellBackdropCover.welcome.priority }
            }
            if let game = viewModel.gameToClose {
                closeGameOverlay(game)
                    .seleneOverlayOwnership(!viewModel.cloudQuitRequested)
                    .transition(.opacity)
                    .zIndex(3)
            }
            if let game = viewModel.gameToRemove {
                removeGameOverlay(game)
                    .seleneOverlayOwnership(!viewModel.cloudQuitRequested)
                    .transition(.opacity)
                    .zIndex(3)
            }
            if showsUpdateOffer {
                updateOfferOverlay()
                    .seleneOverlayOwnership(!viewModel.cloudQuitRequested)
                    .transition(.opacity)
                    .zIndex(3)
            }
            if showsInstallFailure, let game = viewModel.gameWithInstallFailure {
                installFailureOverlay(game)
                    .seleneOverlayOwnership(!viewModel.cloudQuitRequested)
                    .transition(.opacity)
                    .zIndex(3)
            }
            if let id = viewModel.cloudLibraryGameID,
               let game = viewModel.libraryGames.first(where: { $0.id == id }) {
                CloudLibraryPanel(viewModel: viewModel, model: viewModel.cloudLibrary, game: game)
                    .seleneOverlayOwnership(!showsSettingsNotice && !showsUpdateOffer && !showsInstallFailure
                                            && viewModel.gameToClose == nil && viewModel.gameToRemove == nil && !viewModel.cloudQuitRequested)
                    .zIndex(showsUpdateOffer || showsInstallFailure || viewModel.gameToClose != nil || viewModel.gameToRemove != nil ? 2.9 : 3.1)
            }
            if showsSettingsNotice, let notice = viewModel.settingsNotice {
                settingsNoticeOverlay(notice)
                    .seleneOverlayOwnership(!viewModel.cloudQuitRequested)
                    .transition(.opacity)
                    .zIndex(4)
            }
            if router.isMenuPresented {
                Group {
                    if let focus = router.activityCenterFocus {
                        ActivityCenterView(viewModel: viewModel, porting: viewModel.porting, cloudLibrary: viewModel.cloudLibrary, focus: focus,
                                           onFocus: { router.activityCenterFocus?.selected = $0 },
                                           onOpen: { openActivityCenterRow($0, router: router, viewModel: viewModel) },
                                           onCancel: { cancelActivityCenterRow($0, viewModel: viewModel) },
                                           onBack: { router.menuStep(.back) },
                                           onOutside: router.closeMenu,
                                           onTab: { menuInput($0 < 0 ? .tabPrevious : .tabNext) })
                            .transition(.opacity)
                    } else if router.isThemePickerOpen {
                        ThemePickerView(viewModel: viewModel, router: router, settings: settings, games: viewModel.libraryGames)
                            .transition(.opacity)
                            .transformPreference(SeleneBackdropRequestKey.self) { $0?.priority = ShellBackdropCover.themePicker.priority }
                    } else {
                        MenuOverlayView(
                            router: router,
                            cloudLibrary: viewModel.cloudLibrary,
                            activeProfile: profiles.active,
                            hasBuildActivity: viewModel.isBuilding || viewModel.isCheckingCloudBuild
                                || !viewModel.buildQueue.isEmpty || !viewModel.activityResults.entries.isEmpty,
                            onSelect: { runMenuAction($0) },
                            onSelectPower: { runPower($0) },
                            onSelectEntry: { runMenuEntry($0) },
                            onTab: { menuInput($0 < 0 ? .tabPrevious : .tabNext) }
                        )
                        .transition(.opacity)
                    }
                }
                .opacity(opacityBelowCover(ShellBackdropCover.themePicker.priority))
                .seleneOverlayOwnership(!currentBackdropCover.covers(ShellBackdropCover.themePicker.priority)
                                        && profileFlow == nil && !isCloseGameOpen)
                .zIndex(ShellBackdropCover.themePicker.priority)
            }
            if profileFlow != nil, !showsWelcome, !viewModel.showSetupCheck {
                profileLayer.seleneOverlayOwnership(!isCloseGameOpen).transition(.opacity).zIndex(2.5)
            }
            if let game = viewModel.gameForSettingsSheet {
                GameOptionsView(
                    viewModel: viewModel,
                    game: game,
                    origin: viewModel.gameOptionsOrigin,
                    onClose: { viewModel.gameForSettingsSheet = nil },
                    onShowBuild: {
                        viewModel.gameForSettingsSheet = nil
                        router.openAddGame()
                    },
                    onMove: {
                        viewModel.gameForSettingsSheet = nil
                        router.requestSpotlightMove(SpotlightItem.game(game.id).key)
                    },
                    opensMods: viewModel.gameOptionsOpensMods
                )
                .opacity(opacityBelowCover(2))
                .seleneOverlayOwnership(!currentBackdropCover.covers(2) && profileFlow == nil
                                        && !router.isMenuPresented && !isCloseGameOpen)
                .transition(overlayTransition)
                .zIndex(2)
            }
            if let game = viewModel.steamOptionsGame {
                SteamOptionsView(
                    viewModel: viewModel,
                    game: game,
                    origin: viewModel.gameOptionsOrigin,
                    onClose: { viewModel.steamOptionsGame = nil },
                    onMove: {
                        viewModel.steamOptionsGame = nil
                        router.requestSpotlightMove(SpotlightItem.game(game.id).key)
                    }
                )
                .opacity(opacityBelowCover(2))
                .seleneOverlayOwnership(!currentBackdropCover.covers(2) && profileFlow == nil
                                        && !router.isMenuPresented && !isCloseGameOpen)
                .id(game.id)
                .transition(overlayTransition)
                .zIndex(2)
            }
            if profileFlow == nil && !isCloseGameOpen && !nativeDialogOwnsInput && !nativeMenus.isTracking
                && !viewModel.showSetupCheck && !showsWelcome && viewModel.launchOverlay == nil
                && !viewModel.isGameOptionsOpen && !router.isSearchPresented
                && !router.isScreenshotViewerOpen && router.activityCenterFocus == nil
                && !router.isThemePickerOpen {
                switch router.route {
                case .settings: EmptyView()
                default:
                    MenuHoldIndicator()
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .zIndex(5)
                }
            }
        }
        .onPreferenceChange(SeleneBackdropRequestKey.self, perform: updateSharedBackdrop)
    }

    /// Layers with environment, sheets and lifecycle; split from `body` for the type checker.
    private var styled: some View {
        layers
        .allowsHitTesting(!nativeMenus.isTracking)
        .background(FullscreenCursorView())
        .background(StartupWindowView(fullscreen: settings.settings.startInFullscreen) {
            viewModel.isWindowSettling = false
        })
        .focusedSceneValue(\.nxMenuAvailability, nativeMenuAvailability)
        .overlay {
            SessionCardLayer(presenter: sessionCard, game: playedGame,
                             metadata: store.storeMetadata, artwork: artwork)
        }
        .background { launchCover }
        .overlay {
            if viewModel.cloudQuitRequested { cloudQuitOverlay() }
        }
        .modifier(SoundCueHooks(router: router, viewModel: viewModel))
        // Inside the canvas root so the sheet inherits the window's canvas units.
        .seleneCanvasRoot()
        .animation(Motion.screen(reduceMotion), value: viewModel.optionsGameID)
        .animation(Motion.overlay(reduceMotion), value: router.isMenuPresented)
        .animation(Motion.anchoredCard(reduceMotion), value: router.menuSelection.isSubmenuOpen)
        .animation(Motion.screen(reduceMotion), value: router.isThemePickerOpen)
        .animation(Motion.overlay(reduceMotion), value: profileFlow != nil)
        .animation(Motion.overlay(reduceMotion), value: router.isSearchPresented)
        .animation(Motion.screen(reduceMotion), value: viewModel.showSetupCheck)
        .animation(Motion.screen(reduceMotion), value: viewModel.firstRunSetup.page)
        .animation(Motion.screen(reduceMotion), value: router.route == .addGame)
        .animation(Motion.screen(reduceMotion), value: router.route == .console)
        .animation(Motion.overlay(reduceMotion), value: viewModel.gameToClose?.id)
        .animation(Motion.overlay(reduceMotion), value: viewModel.gameToRemove?.id)
        .animation(Motion.overlay(reduceMotion), value: viewModel.gameWithInstallFailure?.id)
        .animation(Motion.overlay(reduceMotion), value: viewModel.settingsNotice?.id)
        .animation(Motion.overlay(reduceMotion), value: showsUpdateOffer)
        .environment(\.seleneReduceMotion, reduceMotion)
        .environment(\.seleneBackdropStyle, backdropStyle)
        .environment(\.seleneSharesBackdrop, true)
        .environment(\.seleneShowButtonHints, settings.settings.showButtonHints)
        .environment(\.seleneButtonNames, settings.settings.buttonNames)
        .environmentObject(updater)
        .environmentObject(sources)
        .onAppear { [sources] in
            steamWatcher.onChange = { [weak sources] in sources?.steamFilesChanged() }
            sources.startIfEnabled()
        }
        .onReceive(sources.$libraryRoots) { roots in steamWatcher.watch(roots, root: sources.configuration.rootURL) }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1100, minHeight: 700)
        .onAppear(perform: startRuntime)
        .background { profilePresenceTask }
        .onReceive(SteamPlayCoordinator.shared.$states.map { SteamPlayCoordinator.blocksIdlePresence($0) }
            .removeDuplicates()) { steamBlocksIdlePresence = $0 }
        .task { await viewModel.restoreActivity() }
        .onReceive(viewModel.cloudLibrary.$archive) { _ in
            Task { @MainActor in
                viewModel.restoreCloudQueue()
                viewModel.importCloudGames()
            }
        }
        .onChange(of: viewModel.isScanningLibrary) { _, scanning in
            if !scanning {
                viewModel.restoreCloudQueue()
                viewModel.importCloudGames()
                viewModel.porting.scheduleNextBuild()
            }
        }
        .onReceive(settings.$loadError) { error in
            guard error != nil else { return }
            let writing = settings.errorKind == .writing
            viewModel.showSettingsNotice(
                title: writing ? L10n.text("Settings not saved") : L10n.text("Settings unavailable"),
                message: writing ? L10n.text("Your changes could not be saved. Try again.")
                    : L10n.text("Defaults are in use. Your previous settings file has been kept."),
                retry: writing ? { _ = settings.save() } : nil)
            viewModel.settingsNotice?.onDismiss = { settings.dismissError() }
        }
        .onDisappear {
            runningGames.stop()
            SteamPlayCoordinator.shared.stop()
            SteamPlaytimeCoordinator.shared.stop()
            SteamAchievementsStore.shared.stop()
            steamWatcher.stop()
            removeGestureKeyMonitor()
        }
        .onChange(of: viewModel.catalogSnapshot.revision) {
            let games = viewModel.catalogSnapshot.games
            runningGames.setGames(viewModel.catalogSnapshot.nxnativeGames)
            SteamPlayCoordinator.shared.setGames(games, sources: viewModel.catalogSourceConfigurations)
            SteamPlaytimeCoordinator.shared.setGames(games, sources: viewModel.catalogSourceConfigurations)
        }
        .onChange(of: LocalProfile.Look(settings.settings)) { _, look in
            guard var profile = profiles.active, profile.look != look else { return }
            profile.look = look
            _ = profiles.update(profile)
        }
        .onChange(of: viewModel.catalogSourceConfigurations) { _, sources in
            SteamPlayCoordinator.shared.setGames(viewModel.catalogGames, sources: sources)
            SteamPlaytimeCoordinator.shared.setGames(viewModel.catalogGames, sources: sources)
            SteamAchievementsStore.shared.setSources(sources)
        }
        .onReceive(playSessions.starts) { gameID in
            // A game that starts leads the Spotlight row, as on a console's home; a move in progress is left alone.
            guard viewModel.spotlight.lift == nil else { return }
            let order = SpotlightRow.playing(gameID, previousOrder: settings.settings.spotlightOrder)
            if order != settings.settings.spotlightOrder { settings.settings.spotlightOrder = order }
        }
        .onReceive(runningGames.$endedSession) { summary in
            sessionCard.ended(summary, enabled: settings.settings.showsSessionCard)
        }
        .onReceive(viewModel.localAchievementUnlocks) { unlocks in
            if profiles.active?.id == unlocks.profile { sessionCard.unlocked(unlocks.names) }
        }
        .onChange(of: profiles.active?.id) { sessionCard.profileDidChange() }
        .onReceive(runningGames.$pausedGameIDs) { ids in
            // A game can reach Home before the launch cover has faded, especially across Spaces.
            if let launch = viewModel.launchOverlay, ids.contains(launch.game.id) { viewModel.dismissLaunchOverlay() }
        }
        .onReceive(SteamPlayCoordinator.shared.$endedSession) { summary in
            sessionCard.ended(summary, enabled: settings.settings.showsSessionCard)
        }
        .onReceive(SteamPlayCoordinator.shared.$launchScreen) { screen in
            // A Steam game's launch screen is the nxnative one: shown on Play, leaving when the coordinator says.
            guard let screen else { return }
            if viewModel.launchOverlay?.game.id == screen.gameID {
                if screen.ready { viewModel.launchOverlay?.isReady = true }
            } else if !screen.ready, viewModel.launchOverlay == nil, let game = playedGame(screen.gameID) {
                viewModel.launchOverlay = LaunchOverlayState(game: game)
                SoundEffectService.shared.play(.launch)
            } else {
                // Not on screen (another launch is) or already over: there is no wait to hold the front for.
                SteamPlayCoordinator.shared.launchScreenClosed(screen.gameID)
            }
        }
        .onChange(of: viewModel.launchOverlay?.game.id) { _, shown in
            // The screen faded, the player dismissed it or another game's took its place: Arcane stops holding
            // the front for the Steam game.
            if let screen = SteamPlayCoordinator.shared.launchScreen, shown != screen.gameID {
                SteamPlayCoordinator.shared.launchScreenClosed(screen.gameID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            sessionCard.becameActive()
            SteamPlaytimeCoordinator.shared.refresh()
        }
        .onChange(of: settings.settings.showsSessionCard) { _, on in
            if !on { sessionCard.clear() }
        }
        .onChange(of: showsUpdateOffer) { viewModel.appUpdateDialogOwnsInput = $1 }
        // Closing clears it once the fade has ended (`closeWelcome`), so nothing under it moves or takes input before.
        .onChange(of: showsWelcome) { if $1 { viewModel.isWelcomeOpen = true } }
        .onChange(of: router.route) { _, route in
            viewModel.cloudLibraryGameID = nil
            if route == .profile && !router.isReturningFromBack { profilePageFocus = nil }
            recordLastHome(route)
            switch route {
            case .addGame:
                viewModel.porting.addGameDidBecomeVisible(
                    defaults: settings.settings.gameDefaults,
                    returningFromBack: router.isReturningFromBack,
                    preservingSelection: setupSourceEntryID != nil
                )
            case .library, .collection, .detail, .gameInbox, .profile, .profileCollection, .integrations:
                setupSourceEntryID = nil
                viewModel.porting.addGameDidLeave()
            default:
                break
            }
        }
    }

    var nativeGameCommands: some View {
        styled
        .environment(\.locale, localization.context.formatLocale)
        .environment(\.nxAppLocale, localization.context)
        .environment(\.catalogPersonalizations, viewModel.personalizations)
        .environment(\.profilePortrait, router.isMenuPresented ? nil : profiles.active)
        .environment(\.onlinePlayersByTitle, onlinePlayers)
        .task(id: profiles.active?.id) {
            guard !Task.isCancelled else { return }
            onlinePlayers = [:]
            guard let store = viewModel.profileNextendo?.store else { return }
            while !Task.isCancelled {
                let counts = (try? await Self.onlineCounts.read(tokenStore: store)) ?? [:]
                guard !Task.isCancelled else { return }
                if counts != onlinePlayers { onlinePlayers = counts }
                try? await Task.sleep(for: .seconds(180))
            }
        }
        .onChange(of: settings.settings.appLanguage) { updateLocale() }
        .onReceive(NotificationCenter.default.publisher(for: .nxOpenLocalProfile)) { _ in openProfilePage() }
        .onReceive(NotificationCenter.default.publisher(for: .nxProfileCardsSaveFailed)) { _ in
            viewModel.showSettingsNotice(title: L10n.text("Settings not saved"),
                                         message: L10n.text("Your changes could not be saved. Try again."))
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxToggleProfilePicker)) { _ in toggleProfilePicker() }
        .onChange(of: settings.settings.appRegion) { updateLocale() }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryPlayFocused)) { _ in
            guard !router.isMenuPresented,
                  nativeMenuAvailability.play,
                  !viewModel.isGameOptionsOpen,
                  !isCloseGameOpen else { return }
            if let steam = viewModel.currentFocusedCatalogGame, steam.integration == .steam {
                SteamPlayCoordinator.shared.press(steam)
            } else if let game = viewModel.currentFocusedGame {
                viewModel.launchGame(game)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenDetails)) { _ in
            guard nativeMenuAvailability.details,
                  let game = viewModel.currentFocusedCatalogGame else { return }
            if router.route == .library { viewModel.spotlight.showGameDetails() }
            else if game.integration != .steam { router.showDetail(game.id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenGameOptions)) { _ in
            guard nativeMenuAvailability.options else { return }
            switch router.route {
            case .library, .collection, .profileCollection:
                let origin: GameOptionsOrigin = router.route == .library ? .spotlight : .collection
                if let steam = viewModel.currentFocusedCatalogGame, steam.integration == .steam {
                    viewModel.openSteamOptions(steam, from: origin)
                } else if let game = viewModel.currentFocusedGame {
                    viewModel.openGameOptions(game, from: origin)
                }
            case .detail(let id):
                if let game = viewModel.libraryGames.first(where: { $0.id == id }) {
                    viewModel.openGameOptions(game, from: .details)
                }
            default:
                break
            }
        }
    }
}

private struct MenuHoldIndicator: View {
    @ObservedObject private var controller = GameControllerService.shared
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        if let start = controller.menuHoldStartedAt {
            TimelineView(.animation(paused: reduceMotion)) { _ in
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                let progress = min(1, max(0, elapsed / HoldDetector.defaultThreshold))
                HStack(spacing: canvas.u(10)) {
                    Circle()
                        .stroke(SeleneTheme.ink25, lineWidth: canvas.u(3))
                        .overlay {
                            if !reduceMotion {
                                Circle().trim(from: 0, to: progress)
                                    .stroke(SeleneTheme.focus, style: StrokeStyle(lineWidth: canvas.u(3), lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                        }
                        .frame(width: canvas.u(22), height: canvas.u(22))
                    Text(L10n.text("Hold: Settings")).seleneFont(19)
                }
                .foregroundStyle(SeleneTheme.ink)
                .padding(.horizontal, canvas.u(16))
                .padding(.vertical, canvas.u(9))
                .background(SeleneTheme.glassCard, in: Capsule())
                .padding(.bottom, canvas.u(SeleneBottomScrim.hintsBottom + 50))
            }
            .allowsHitTesting(false)
        }
    }
}
