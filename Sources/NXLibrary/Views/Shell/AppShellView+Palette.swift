import AppKit
import ArcanePorting
import NXLibraryCore
import SwiftUI

/// The command palette's rows and what each one runs. Everything it runs has its own place elsewhere.
extension AppShellView {
    /// Above the menu and the search, below every dialog.
    static let paletteLayer = 1.5

    /// Over any screen that asks nothing: not over a question, a setup, the profile picker, a game's options or a launch.
    var paletteAvailable: Bool {
        !viewModel.showSetupCheck && !showsWelcome && profileFlow == nil && !isCloseGameOpen
            && !router.isScreenshotViewerOpen && !viewModel.isGameOptionsOpen && viewModel.launchOverlay == nil
            && !filePicker.isOpen && !nativeDialogOwnsInput
    }

    func togglePalette(query: String = "") {
        if router.isPalettePresented { return closePalette() }
        guard paletteAvailable else { return }
        palette.onChoose = { item, secondary in runPalette(item, secondary: secondary) }
        palette.onClose = closePalette
        palette.open(query: query, items: paletteItems, recents: profiles.active.map { PaletteRecentsStore().load(for: $0.id) } ?? [],
                     suggestions: paletteSuggestions, symbols: paletteSymbols)
        SoundEffectService.shared.play(.openPanel)
        router.isPalettePresented = true
    }

    func updatePalette() {
        if router.isPalettePresented { palette.update(items: paletteItems, symbols: paletteSymbols) }
    }

    private func closePalette() {
        router.isPalettePresented = false
    }

    // MARK: - Input

    func paletteInput(_ action: GamepadAction) {
        switch action {
        case .controlCenter:
            router.isMenuPresented = true
        case .menuHold, .fullMenu:
            closePalette()
            if !router.route.isSettings { router.openSettings(.startUp) }
        default: palette.handle(action)
        }
    }

    /// The field keeps letters, ← and →; the rest moves the list. Menu bar shortcuts pass.
    func paletteKey(_ event: NSEvent) -> NSEvent? {
        // An input method finishing a word owns Return, the arrows and Esc.
        if (event.window?.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
        guard let action = CommandPalette.action(keyCode: event.keyCode, modifiers: event.modifierFlags) else { return event }
        let moves: Set<GamepadAction> = [.navigateUp, .navigateDown, .tabNext, .tabPrevious]
        if !event.isARepeat || moves.contains(action) { GameControllerService.shared.onAction?(action) }
        return nil
    }

    // MARK: - Rows

    var paletteItems: [PaletteItem] { paletteGames.map(gameItem) + paletteActions + paletteSettings }

    /// The games Find a game lists, the last played first.
    private var paletteGames: [CatalogGame] {
        LibraryQuery(filter: .all).applyCatalog(to: viewModel.visibleCatalogGames, history: playSessions)
    }

    private func gameItem(_ game: CatalogGame) -> PaletteItem {
        let editable = game.macShortcut == nil || viewModel.macShortcuts.canEdit
        return PaletteItem(id: gameID(game.id), kind: .game, title: game.name, detail: L10n.text(platform(of: game).rawValue),
                           primary: primaryLabel(game), secondary: editable ? "Options" : nil, notes: game.librarySearchTerms)
    }

    private func gameID(_ id: UUID) -> String { "game:\(id.uuidString)" }

    private func platform(of game: CatalogGame) -> PlatformKind {
        if game.integration == .steam { return .steam }
        if game.macShortcut != nil { return .mac }
        return game.nxnativeGame?.isSwitch2 == true ? .switch2 : .switch1
    }

    /// What the home screens write on A for this game.
    private func primaryLabel(_ record: CatalogGame) -> String {
        if record.integration == .steam { return SteamPlayCoordinator.shared.hint(for: record).first?.label ?? "Details" }
        guard let game = record.nxnativeGame else { return record.macShortcut == nil ? "Details" : "Open" }
        if runningGames.runningGameIDs.contains(game.id) { return "Resume" }
        if let item = viewModel.cloudLibrary.downloadItem(for: game) { return item.primaryDownloadTitle }
        if game.isPlayableLocally { return "Play" }
        return game.isCloudSourcePlaceholder && viewModel.gamesWithFilesHere.contains(game.id) ? "Build" : "Details"
    }

    private var paletteActions: [PaletteItem] {
        let onHome = router.route == .library || router.route == .collection
        return PaletteAction.allCases.filter(isAvailable).map { $0.item(showsShortcut: $0 != .changeView || onHome) }
    }

    /// What cannot run now is not listed.
    private func isAvailable(_ action: PaletteAction) -> Bool {
        switch action {
        case .addApp: viewModel.macShortcuts.canEdit
        case .gameInbox: settings.settings.gameInboxEnabled
        case .myProfile: profiles.active != nil && router.route != .profile
        case .switchProfile: profiles.active != nil
        default: true
        }
    }

    private var paletteSettings: [PaletteItem] {
        SettingsCatalog.visible(supportsNextendo: false, hasProfileAccount: viewModel.profileNextendo != nil,
                                cloudConfigured: viewModel.cloudLibrary.preference.remote != nil).map { row in
            PaletteItem(id: settingID(row), kind: .setting, title: L10n.text(row.title),
                        detail: SettingsDescriptorList.path(row.group),
                        section: SettingsCategory(section: row.group)?.title() ?? row.group.title,
                        aliases: [row.title], notes: [L10n.text(row.about)])
        }
    }

    private var paletteSuggestions: [String] {
        let last = paletteGames.first { playSessions.lastPlayed(for: $0.id) != nil }
        return (last.map { [gameID($0.id)] } ?? []) + PaletteAction.suggested.map(\.itemID)
    }

    /// Only what is already in memory: the palette reads no file and asks no service.
    private var paletteSymbols: [String: CommandPalette.Symbol] {
        var symbols: [String: CommandPalette.Symbol] = [:]
        for action in PaletteAction.allCases { symbols[action.itemID] = .icon(action.icon) }
        for row in SettingsCatalog.all { symbols[settingID(row)] = .icon(row.group.icon) }
        for game in paletteGames {
            let art = game.nxnativeGame == nil ? nil : TileArtMemo.shared.object(forKey: "nxnative|\(game.id)" as NSString)
            symbols[gameID(game.id)] = art.map { .art($0) } ?? .platform(platform(of: game))
        }
        return symbols
    }

    private func settingID(_ row: SettingDescriptor) -> String { "setting:\(row.id)" }

    private func paletteAction(_ item: PaletteItem) -> PaletteAction? {
        item.kind == .action ? PaletteAction.allCases.first { $0.itemID == item.id } : nil
    }

    private func paletteGame(_ item: PaletteItem) -> CatalogGame? {
        item.kind == .game ? viewModel.visibleCatalogGames.first { gameID($0.id) == item.id } : nil
    }

    // MARK: - Choices

    private func runPalette(_ item: PaletteItem, secondary: Bool) {
        if let active = profiles.active, profiles.guest == nil {
            let store = PaletteRecentsStore()
            store.save(PaletteRecents.adding(item, to: store.load(for: active.id)), for: active.id,
                       known: Set(profiles.profiles.map(\.id)))
        }
        closePalette()
        if let action = paletteAction(item) {
            runPaletteAction(action)
        } else if let game = paletteGame(item) {
            if secondary { openOptions(game) } else { activate(game) }
        } else if let row = SettingsCatalog.all.first(where: { settingID($0) == item.id }) {
            router.openSettings(row.group, rowID: row.id)
        }
    }

    /// A on the game's tile, whichever screen is under the palette.
    private func activate(_ record: CatalogGame) {
        guard let game = record.nxnativeGame else {
            if viewModel.playRouter.supports(record.integration) { viewModel.pressPlay(record) }
            else { router.showDetail(record.id) }
            return
        }
        if viewModel.portingPills(game) == .porting { router.openAddGame() }
        else if viewModel.cloudLibrary.downloadItem(for: game) != nil { viewModel.downloadCloudGame(game) }
        else if game.isPlayableLocally { viewModel.launchGame(game) }
        else if game.isCloudSourcePlaceholder, viewModel.gamesWithFilesHere.contains(game.id) {
            viewModel.porting.startBuild(for: game) { router.openAddGame() }
        } else { router.showDetail(game.id) }
    }

    /// Options open over a library screen, with the game selected there.
    private func openOptions(_ record: CatalogGame) {
        let home = isHomeRoute || router.route == .detail(record.id)
        let open = {
            if !home {
                router.showLibrary()
                router.requestSpotlightSelect(record.id)
            }
            let origin: GameOptionsOrigin = router.route == .library ? .spotlight : .collection
            if record.macShortcut != nil { viewModel.macShortcuts.showTileOptions(record) }
            else if record.integration == .steam { viewModel.openSteamOptions(record, from: origin) }
            else if let game = record.nxnativeGame { viewModel.openGameOptions(game, from: origin) }
        }
        if home { open() } else { afterSettings(open) }
    }

    /// Unsaved settings are asked about first.
    private func afterSettings(_ run: @escaping () -> Void) {
        if !router.requestSettingsDeparture(run) { run() }
    }

    private func runPaletteAction(_ action: PaletteAction) {
        switch action {
        case .addGame: runMenuEntry(.addGame)
        case .addApp: viewModel.macShortcuts.chooseApp()
        case .manageSources: runMenuEntry(.manageSources)
        case .refreshLibrary: runMenuEntry(.refreshLibrary)
        case .gameInbox: runMenuEntry(.gameInbox)
        case .myProfile: runMenuEntry(.myProfile)
        case .switchProfile: openProfile(.picker)
        case .editProfile: runMenuEntry(.editProfile)
        case .theme: openInMenu(.profile) { runMenuEntry(.theme) }
        case .players: runMenuEntry(.players)
        case .changeView: router.setInitialRoute(router.route == .library ? .collection : .library)
        case .fullscreen: NSApp.mainWindow?.toggleFullScreen(nil)
        case .zoomIn, .zoomOut, .actualSize:
            NotificationCenter.default.post(name: .nxInterfaceZoom, object: action == .zoomIn ? 1 : action == .zoomOut ? -1 : 0)
        case .controls: router.openSettings(.controllers, rowID: SettingsView.controlsGuideRowID)
        case .settings: router.openSettings(.startUp)
        case .controlCenter: router.isMenuPresented = true
        case .activityCenter: openInMenu(.activityCenter) { runMenuAction(.activityCenter) }
        case .checkUpdates: updater.checkNow()
        case .sleep: runPower(.sleep)
        case .hide: runPower(.hide)
        case .relaunch: runPower(.relaunch)
        case .quit: runPower(.quit)
        }
    }

    private func openInMenu(_ icon: MenuAction, _ run: @escaping () -> Void) {
        afterSettings {
            router.isMenuPresented = true
            router.menuSelection.selected = icon
            run()
        }
    }
}
