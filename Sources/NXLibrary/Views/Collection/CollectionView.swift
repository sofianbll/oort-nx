import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// Collection (spec §5.3, Selene Main.xaml SeleneLibrary, `library.png`): the
/// whole library as one row of portrait covers over the selected game's art.
/// It shares Spotlight's frame (`SeleneHomeChrome`): the top bar, the 80 margin
/// and the hints sit where Spotlight has them. On the stage: top bar 0–100, the
/// logo / stats / genres at x 80 from y 110, the cover band 576–976 (400 high).
/// The art and the row reach the window edges.
struct CollectionView: View {
    @ObservedObject var viewModel: AppViewModel
    /// The Nintendo store's data (`StoreMetadataModel`): descriptions, screenshots and names shown here.
    @ObservedObject var store: StoreMetadataModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var playSessions: PlaySessionStore
    @ObservedObject var artwork: ArtworkStore
    @ObservedObject var cloud: CloudLibraryModel

    @Environment(\.seleneCanvas) var canvas
    @Environment(\.controllerHomeAvailable) private var controllerHomeAvailable
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.integrationBar) var integrationBar

    @StateObject var art = SeleneHeroArt()
    /// Art the player picks redraws the hero and logo (their task keys carry its revision).
    @ObservedObject var picks = ArtworkPicks.shared
    /// Steam Play phases drive the A hint.
    @ObservedObject var steamPlayer = SteamPlayCoordinator.shared
    @State var keyMonitor: Any?
    @State var profileFocused = false
    @State var importFocused = false
    @Environment(\.profilePortrait) var profile

    init(viewModel: AppViewModel, router: AppRouter, settings: AppSettingsStore,
                playSessions: PlaySessionStore, artwork: ArtworkStore) {
        self.viewModel = viewModel
        self.store = viewModel.store
        self.router = router
        self.settings = settings
        self.playSessions = playSessions
        self.artwork = artwork
        self.cloud = viewModel.cloudLibrary
    }

    // MARK: - Model

    /// The filter is shared with Spotlight.
    var filter: LibraryFilter { viewModel.librarySelection.query.filter }

    var profileCard: ProfilePageCard? {
        if case .profileCollection(let card) = router.route { return card }
        return nil
    }

    var games: [CatalogGame] { games(using: viewModel.librarySelection.query) }

    private func games(using query: LibraryQuery) -> [CatalogGame] {
        let games = viewModel.visibleCatalogGames
        guard let card = profileCard else {
            return viewModel.queryLibrary(query, history: playSessions)
        }
        let now = Date.now
        return card.games(in: games, activity: playSessions.profileActivity(at: now),
                          week: Activity.summary(sessions: playSessions.sessions, now: now, calendar: .current,
                                                 topLimit: games.count), now: now)
    }

    var hasAnyGame: Bool { !viewModel.visibleCatalogGames.isEmpty }
    private var usesCloudShelf: Bool { profileCard == nil && filter == .cloud }
    var showsEmptyActions: Bool { profileCard == nil && !usesCloudShelf && !hasAnyGame && !viewModel.isScanningLibrary }

    private func selectedCatalogGame(in games: [CatalogGame]) -> CatalogGame? {
        guard let id = viewModel.librarySelection.selectedGameID else { return nil }
        return games.first { $0.id == id }
    }

    var selectedGame: PortedGame? { selectedCatalogGame?.nxnativeGame }
    var selectedCatalogGame: CatalogGame? { selectedCatalogGame(in: games) }

    // MARK: - Body

    var body: some View {
        let games = self.games
        let record = selectedCatalogGame(in: games)
        let game = record?.nxnativeGame
        let lifecycle = sortAndLifecycle(on: chrome(games: games, record: record, game: game))
        let library = libraryChanges(on: lifecycle)
        let input = inputEvents(on: library)
        return loadSelection(game, record: record, on: input)
    }

    private func chrome(games: [CatalogGame], record: CatalogGame?, game: PortedGame?) -> some View {
        let hints = contextHints(game, record: record)
        return SeleneHomeChrome(
            leftHints: profileCard != nil ? [HintItem(.b, "Back", action: router.back)] : HintItem.homeGlobals(other: "Spotlight",
                                             onOther: settings.settings.viewButtonSwitches ? { handle(.view) } : nil,
                                             onMenu: { router.isMenuPresented = true },
                                             onSearch: { handle(.search) },
                                             onProfiles: { ProfileFlow.requestPicker() },
                                             layout: GamepadLayout(settings.settings), hasHome: controllerHomeAvailable,
                                             showsOptions: !router.integrationBarFocused && hints.contains { $0.button == .menu }),
            rightHints: router.integrationBarFocused ? [HintItem(.a, L10n.text("Open")) { handle(.confirm) }]
                : hints + (profileCard == nil
                ? [LibrarySortMenu.hint(settings.settings.librarySort, action: openSort)]
                : [HintItem(.lb, "Previous") { handle(.tabPrevious) }, HintItem(.rb, "Next") { handle(.tabNext) }]),
            hintsHidden: router.overlayHasHints(viewModel)
                || (selectedCatalogGame?.macShortcut != nil && viewModel.settingsNotice != nil),
            backdrop: {
                SeleneArtBackground(image: art.image, imageKey: art.key,
                                    shade: settings.settings.backgroundShade,
                                    showsArt: !settings.settings.keepWallpaperOnGames)
            },
            stage: { stage(games: games, game: game, record: record) })
    }

    private func sortAndLifecycle(on content: some View) -> some View {
        content
        .accessibilityHidden(router.sortMenu != nil)
        .overlay {
            if let sortMenu = router.sortMenu {
                LibrarySortMenu(current: settings.settings.librarySort, focused: sortMenu, choose: setSort) {
                    router.sortMenu = nil
                }
            }
        }
        .onAppear(perform: appear)
        // A launch on Collection: Spotlight's entrance belongs to the first home only (`SpotlightView+Entrance`).
        .onAppear { viewModel.homeSeen = true }
        .onDisappear {
            router.sortMenu = nil
            removeKeyMonitor()
        }
    }

    private func libraryChanges(on content: some View) -> some View {
        let filteredIDs: Set<UUID> = filter == .cloud ? viewModel.cloudOnlyGameIDs : []
        return content
        .onChange(of: viewModel.catalogGames) {
            store.preloadCachedStoreMetadata()
            reconcile()
        }
        .onChange(of: viewModel.catalogSourceConfigurations) { reconcile() }
        .onChange(of: filter) { reconcile() }
        .onChange(of: filteredIDs) { reconcile() }
        .onChange(of: settings.settings.librarySort) { reconcile() }
        .onChange(of: showsEmptyActions) { _, shown in if !shown { importFocused = false } }
        .onChange(of: viewModel.librarySelection.selectedGameID) { selectionChanged() }
    }

    private func inputEvents(on content: some View) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: .nxCollectionGamepadAction)) { note in
            guard viewModel.alertMessage == nil, viewModel.settingsNotice == nil else { return }
            if let action = note.object as? GamepadAction { handle(action) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxFindGameSelect)) { note in
            guard profileCard == nil, let id = note.object as? UUID else { return }
            // Find a game lands on Collection; a tab without the game gives way to All games.
            if !games.contains(where: { $0.id == id }) { setFilter(.all) }
            select(id)
        }
        .onChange(of: playSessions.sessions.count) { reconcile() }
        .onChange(of: playSessions.profileID) { reconcile() }
        .onChange(of: viewModel.isScanningLibrary) { reconcile() }
    }

    private func loadSelection(_ game: PortedGame?, record: CatalogGame?, on content: some View) -> some View {
        content
        .task(id: art.heroTaskKey(game, metadata: game.flatMap { store.storeMetadata[$0.id] })) { await loadHero(game) }
        .task(id: art.steamHeroTaskKey(record)) { await art.loadSteamHero(game: record, current: { selectedCatalogGame?.id }, artwork: artwork) }
        .task(id: art.logoTaskKey(game, metadata: game.flatMap { store.storeMetadata[$0.id] })) { await loadLogo(game) }
        .task(id: game) { await viewModel.prefetchCloudLibrary(game) }
    }

    private func stage(games: [CatalogGame], game: PortedGame?, record: CatalogGame?) -> some View {
        ZStack(alignment: .topLeading) {
            if let profileCard {
                Text(L10n.text(profileCard.title, context: localization))
                    .seleneFont(.screen, .semibold)
                    .foregroundStyle(SeleneTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.chromeGutter))
                    .frame(height: canvas.u(SeleneTokens.Space.stageHeader))
            } else {
                SpotlightTopBar(filter: filter, sort: settings.settings.librarySort, showClock: settings.settings.showClock,
                                profileFocused: profileFocused, nextendo: viewModel.profileNextendo, onSelect: { setFilter($0) })
            }

            if let game {
                CollectionInfoView(game: game, logo: art.logo(for: game),
                                   cloudOnly: cloud.downloadItem(for: game) != nil,
                                   presentation: LibraryPresentation(
                                       game: game, metadata: store.storeMetadata[game.id],
                                       totalPlaytime: playSessions.totalDuration(for: game.id),
                                       lastPlayed: playSessions.lastPlayed(for: game.id)))
                    .id(game.id)
                    // Spotlight's left margin; the logo starts just under the top bar.
                    .frame(width: canvas.u(1100), alignment: .topLeading)
                    .offset(x: canvas.u(80), y: canvas.u(110))
            } else if let record, record.integration == .steam {
                CatalogSteamInfo(game: record, totalPlaytime: playSessions.totalDuration(for: record.id),
                                 lastPlayed: playSessions.lastPlayed(for: record.id), collection: true)
                    .id(record.id)
                    .frame(width: canvas.u(1100), alignment: .topLeading)
                    .offset(x: canvas.u(80), y: canvas.u(110))
            } else if let record = selectedCatalogGame, record.macShortcut != nil {
                MacShortcutInfo(game: record, collection: true, canEdit: viewModel.macShortcuts.canEdit) { action in
                    if action == 0 { activateCatalog(record) }
                    else { viewModel.macShortcuts.showTileOptions(record) }
                }
                .id(record.id)
                .frame(width: canvas.u(1100), alignment: .topLeading)
                .offset(x: canvas.u(80), y: canvas.u(110))
            }

            if games.isEmpty {
                emptyState
                    .frame(width: canvas.stageSize.width, height: canvas.u(980), alignment: .center)
            } else {
                CollectionCoverRow(
                    games: games,
                    selectedID: viewModel.librarySelection.selectedGameID,
                    artwork: artwork,
                    boxArt: viewModel.boxArt,
                    boxArtIndexVersion: viewModel.boxArtIndexVersion,
                    officialName: { store.storeMetadata[$0.id]?.name },
                    needsMetadata: { store.loadStoreMetadata(for: $0) },
                    tileLook: viewModel.portingTileLook,
                    cloud: viewModel.cloudLibrary,
                    showsCloudBadges: settings.settings.cloudTileBadges.showsOnCollection,
                    badgePosition: settings.settings.tileBadgePosition,
                    onSelect: { select($0.id) },
                    onActivate: { record in select(record.id); activateCatalog(record) })
                    .offset(y: canvas.u(576))
            }
        }
    }

    // MARK: - Empty state

    private var cloudEmptyKey: String {
        guard cloud.preference.enabled, cloud.preference.remote != nil else {
            return "Connect your cloud library in Settings → Porting → Cloud library."
        }
        if cloud.importTask != nil { return "Looking for cloud games…" }
        if cloud.hasCloudReadFailure || cloud.referenceCheck?.incomplete == true || cloud.hasPendingMove
            || (cloud.archive == nil && cloud.needsDriveTool) {
            return "Could not check the cloud library. Check your connection in Settings."
        }
        // Connection OK alone only verifies access, not the inventory.
        if cloud.triedAutomaticImport, cloud.lastCompleteCheck != nil,
           cloud.preference.referenceFolder == nil || cloud.referenceCheck?.count != nil {
            return "No cloud games to download."
        }
        return "Looking for cloud games…"
    }

    @ViewBuilder
    private var emptyState: some View {
        if usesCloudShelf {
            Text(L10n.text(cloudEmptyKey, context: localization))
                .seleneFont(.screen)
                .foregroundColor(SeleneTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: canvas.u(1080))
                .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
        } else if viewModel.isScanningLibrary {
            EmptyView()
        } else if profileCard != nil {
            Text(L10n.text("No games in this view.", context: localization))
                .seleneFont(.screen)
                .foregroundColor(SeleneTheme.ink)
        } else if hasAnyGame {
            Text(L10n.format("No games in %@", [L10n.text(filter.rawValue)]))
                .seleneFont(.screen)
                .foregroundColor(SeleneTheme.ink)
                .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
                .allowsHitTesting(false)
        } else {
            VStack(spacing: canvas.u(14)) {
                Text(L10n.text("Add your first game")).seleneFont(.screen).foregroundColor(SeleneTheme.ink)
                Text(L10n.text("Choose game files or find your existing apps."))
                    .seleneFont(.text).foregroundColor(SeleneTheme.ink60)
                HStack(spacing: canvas.u(14)) {
                    SelenePillButton(title: L10n.text("Add game"), focused: !profileFocused && !importFocused) { router.openAddGame() }
                    SelenePillButton(title: L10n.text("Import existing builds"), minWidth: 0, focused: !profileFocused && importFocused) {
                        viewModel.importExistingBuilds()
                    }
                }
                .padding(.top, canvas.u(SeleneTokens.Space.control))
            }
            .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
        }
    }

    // MARK: - Hints

    private func contextHints(_ game: PortedGame?, record: CatalogGame?) -> [HintItem] {
        func options(_ label: String, action: (() -> Void)? = nil) -> HintItem {
            .browsingOptions(GamepadLayout(settings.settings), label, hasHome: controllerHomeAvailable, action: action)
        }
        if let steam = record, steam.integration == .steam {
            return SteamPlayCoordinator.shared.hint(for: steam)
                + [options("Game options")]
        }
        if let record, record.macShortcut != nil {
            return [HintItem(.a, "Open") { self.activateCatalog(record) }]
                + (viewModel.macShortcuts.canEdit ? [options("Tile options") { self.viewModel.macShortcuts.showTileOptions(record) }] : [])
        }
        guard let game else {
            guard showsEmptyActions else { return [] }
            return [HintItem(.a, importFocused ? L10n.text("Import existing builds") : L10n.text("Add game"))]
        }
        if let item = cloud.downloadItem(for: game) {
            return [HintItem(.a, item.primaryDownloadTitle), HintItem(.x, "Details"), options("Game options")]
        }
        if game.isPlayableLocally {
            return [HintItem(.a, L10n.text("Play")), HintItem(.x, L10n.text("Details")), options("Game options")]
        }
        if game.isCloudSourcePlaceholder, viewModel.gamesWithFilesHere.contains(game.id) {
            return [HintItem(.a, "Build"), HintItem(.x, "Details"), options("Game options")]
        }
        return [HintItem(.a, L10n.text("Details")), options("Game options")]
    }

    // MARK: - Selection

    func appear() {
        installKeyMonitor()
        router.isSearchPresented = false
        store.preloadCachedStoreMetadata()
        // The starting tab is applied once per session, on the first visit to either screen.
        if profileCard == nil, !viewModel.spotlight.startingTabApplied {
            viewModel.spotlight.startingTabApplied = true
            viewModel.librarySelection.query.filter = LibraryFilter(startingTab: settings.settings.startingTab)
        }
        reconcile()
        selectionChanged()
    }

    /// Keeps the selection inside the filtered list, in the same frame as any change to it.
    func reconcile() {
        var state = viewModel.librarySelection
        if profileCard == nil { state.query.sort = settings.settings.librarySort }
        state.reconcileIDs(games(using: state.query).map(\.id),
                           preferred: profileCard == nil && settings.settings.restoreLastGame ? settings.lastSelectedGameID : nil)
        if state != viewModel.librarySelection { viewModel.librarySelection = state }
    }

    func setFilter(_ next: LibraryFilter) {
        guard next != filter else { return }
        viewModel.librarySelection.query.filter = next
        reconcile()
        SoundEffectService.shared.play(.tabSwitch)
    }

    func openSort() { router.sortMenu = settings.settings.librarySort }

    func setSort(_ sort: LibrarySort) {
        router.sortMenu = nil
        settings.settings.librarySort = sort
        reconcile()
        SoundEffectService.shared.play(.tabSwitch)
    }

    func select(_ id: UUID) {
        if viewModel.librarySelection.selectedGameID != id { viewModel.librarySelection.selectedGameID = id }
    }

    private func selectionChanged() {
        let game = selectedGame
        if profileCard == nil, let id = game?.id ?? selectedCatalogGame?.id { settings.rememberLastSelectedGame(id) }
        if let game { store.loadStoreMetadata(for: game) }
    }

    // MARK: - Art

    private func loadHero(_ game: PortedGame?) async {
        // On a Steam game the nxnative art stays until the Steam hero replaces it, so the change is one crossfade.
        await art.loadHero(game: game, current: { selectedGame?.id },
                           metadata: game.flatMap { store.storeMetadata[$0.id] }, artwork: artwork, personalizations: viewModel.personalizations,
                           keepsWithoutGame: selectedCatalogGame?.integration == .steam)
    }

    private func loadLogo(_ game: PortedGame?) async {
        await art.loadLogo(game: game, metadata: game.flatMap { store.storeMetadata[$0.id] },
                           artwork: artwork, personalizations: viewModel.personalizations)
    }
}

/// The selected game's logo, stats and genres, left aligned like Spotlight's
/// info: a 250 high logo area (logo up to 700 × 240, Spotlight's size, bottom
/// left; else the name at 56), stats 28 below, Spotlight's genre chips 20 below.
/// The column arrives together on each game change: hold 0.12 s, fade in to
/// 0.42 s while sliding from x −24 (0.3 s cubic out).
struct CollectionInfoView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let game: PortedGame
    let logo: NSImage?
    let cloudOnly: Bool
    let presentation: LibraryPresentation

    @State private var shown = true
    @State private var slid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logoArea
            if !cloudOnly, let reason = GameResourceState.unavailableReason(for: game) {
                Text(reason.title)
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.ink75)
                    .padding(.top, canvas.u(SeleneTokens.Space.panel))
                Text(reason.detail)
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink60)
                    .padding(.top, canvas.u(SeleneTokens.Space.tight))
            } else if !cloudOnly, !game.isPlayableLocally, game.status != .building, game.portingFailure == nil {
                Text(L10n.text("Not built yet"))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink75)
                    .padding(.top, canvas.u(SeleneTokens.Space.panel))
            }
            SeleneStatsRow(presentation: presentation)
                .padding(.top, canvas.u(SeleneTokens.Space.feature))
            if !presentation.genres.isEmpty {
                SpotlightGenreChips(genres: presentation.genres)
                    .padding(.top, canvas.u(SeleneTokens.Space.panel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .opacity(shown ? 1 : 0)
        .offset(x: slid ? 0 : canvas.u(Self.slideDistance))
        .onAppear { reveal() }
    }

    private var logoArea: some View {
        GameLogoArea(title: game.name, logo: logo, collection: true)
    }

    /// The whole column's fade and slide after a change. A Steam game's column uses the same.
    /// Quicker than Spotlight's head (a grid is browsed fast) but with its curve, easing out like `logoFade`.
    static let fade = Animation.easeOut(duration: 0.3).delay(0.12)
    static let slide = SeleneTheme.cubicOut(0.3).delay(0.12)
    static let slideDistance: CGFloat = -24

    /// The fade always runs; the slide is movement and drops under reduce motion.
    private func reveal() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            shown = false
            slid = reduceMotion
        }
        DispatchQueue.main.async {
            withAnimation(Self.fade) { shown = true }
            if !reduceMotion {
                withAnimation(Self.slide) { slid = true }
            }
        }
    }
}
