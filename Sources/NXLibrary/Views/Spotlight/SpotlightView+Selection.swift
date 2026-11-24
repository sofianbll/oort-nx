import SwiftUI
import AppKit
import NXLibraryCore

/// Selection: appearing, filter and library changes, and keeping the selected game in the row.
extension SpotlightView {
    // MARK: - Selection

    func mutate(_ change: (inout SpotlightState) -> Void) {
        var state = viewModel.spotlight
        change(&state)
        if viewModel.spotlight.focus == .row, state.focus != .row {
            router.integrationBarFocused = false
            profileFocused = false
        }
        if state != viewModel.spotlight { viewModel.spotlight = state }
    }

    func appear() {
        installKeyMonitor()
        router.isSearchPresented = false
        store.preloadCachedStoreMetadata()
        if !viewModel.spotlight.startingTabApplied {
            mutate { $0.startingTabApplied = true }
            viewModel.librarySelection.query.filter = LibraryFilter(startingTab: settings.settings.startingTab)
        }
        hadGames = !viewModel.visibleCatalogGames.isEmpty
        reconcile()
        selectionChanged()
        consumePendingMove()
        consumePendingSelect()
    }

    /// Selects the item whose Move was requested and lifts it.
    func consumePendingMove() {
        guard let key = router.pendingSpotlightMove else { return }
        router.pendingSpotlightMove = nil
        if !items.contains(where: { $0.key == key }), filter != .all {
            viewModel.librarySelection.query.filter = .all
        }
        let items = self.items
        guard let item = items.first(where: { $0.key == key }) else { return }
        cardMenu = nil
        mutate { state in
            state.cancelLift()
            state.select(item)
            state.beginLift(in: items)
        }
        SoundEffectService.shared.play(.click)
    }

    func gamesChanged() {
        store.preloadCachedStoreMetadata()
        // The whole library, not the filtered row: a filter change never
        // counts as "the library arrived".
        let hasGames = !viewModel.visibleCatalogGames.isEmpty
        // The library loads after the first frame: a card picked while it was
        // empty gives way to the restored (or first) game.
        if !hadGames, hasGames, case .card = selectedItem {
            mutate { $0.selectedKey = nil }
        }
        hadGames = hasGames
        reconcile()
        if selectedItem == .card(.mods) { openStore() }
    }

    func reconcile() {
        // The lifted tile vanished (library reload, settings change): put it back.
        if let lifted = viewModel.spotlight.lift?.key, !items.contains(where: { $0.key == lifted }) {
            mutate { $0.cancelLift() }
        }
        let preferred = settings.settings.restoreLastGame ? settings.lastSelectedGameID : nil
        let items = self.items
        mutate { $0.reconcile(with: items, preferredGameID: preferred) }
    }

    func setFilter(_ next: LibraryFilter) {
        guard next != filter else { return }
        viewModel.librarySelection.query.filter = next
        mutate { $0.focus = .row }
        reconcile() // Same frame: the selection is never missing from the row.
        SoundEffectService.shared.play(.tabSwitch)
    }

    func openSort() {
        guard viewModel.spotlight.focus == .row, !viewModel.spotlight.isLifted,
              cardMenu == nil, viewer == nil, achievementsScreen == nil,
              !router.overlayHasHints(viewModel) else { return }
        router.sortMenu = settings.settings.librarySort
    }

    func setSort(_ sort: LibrarySort) {
        router.sortMenu = nil
        settings.settings.librarySort = sort
        SoundEffectService.shared.play(.tabSwitch)
    }

    func selectionChanged() {
        if selectedItem == .card(.mods) { openStore() } else { storeHost.close() }
        updateModsBackdrop()
        // A Steam game is a game too: moving to or from it keeps the art until the next arrives, never the wallpaper.
        artRule.select(viewModel.spotlight.selectedKey, isGame: selectedGame != nil || selectedCatalogGame?.integration == .steam)
        reloadMods()
        startModsOnline(viewModel.spotlight.focus)
        let game = selectedGame
        if let id = game?.id ?? selectedCatalogGame?.id { settings.rememberLastSelectedGame(id) }
        loadAchievements()
        if let game { store.loadStoreMetadata(for: game) }
    }
}
