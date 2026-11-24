import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// What a game's page and Game options ask of the library: options, Favorite, Hidden, cloud saves, Close Game and removal.
extension AppViewModel {
    /// Opens Game options for a game, remembering the screen it was opened from.
    func openGameOptions(_ game: PortedGame, from origin: GameOptionsOrigin, opensMods: Bool = false) {
        gameOptionsOrigin = origin
        gameOptionsOpensMods = opensMods
        steamOptionsGame = nil
        gameForSettingsSheet = game
    }

    /// Opens a Steam game's Options, remembering the screen it was opened from.
    func openSteamOptions(_ game: CatalogGame, from origin: GameOptionsOrigin) {
        guard game.integration == .steam else { return }
        gameOptionsOrigin = origin
        gameForSettingsSheet = nil
        steamOptionsGame = game
    }

    /// Flips the favorite heart and saves the library.
    func toggleFavorite(_ game: PortedGame) {
        if toggleLocalFavorite(game.id) { return }
        updateStoredGame(game) { $0.isFavorite.toggle() }
    }

    func toggleLocalFavorite(_ id: UUID) -> Bool {
        guard let profiles = localProfiles, let active = profiles.active, active.id != profiles.originalID else { return false }
        if profiles.toggleFavorite(id) { refreshProfileFavorites() }
        else {
            showSettingsNotice(title: L10n.text("Profiles could not be saved."),
                               message: L10n.text("Your changes could not be saved. Try again."))
        }
        return true
    }

    /// Flips the hidden flag and saves the library. Hidden games leave Spotlight,
    /// Collection and Surprise me; the screens reconcile their selection on the change.
    func toggleHidden(_ game: PortedGame) {
        updateStoredGame(game) { $0.isHidden.toggle() }
    }

    /// Applies one change to the stored game and saves the library, the same way for every flag.
    private func updateStoredGame(_ game: PortedGame, _ change: (inout PortedGame) -> Void) {
        do { applyCatalog(try catalogRepository.updateNXNative(id: game.id, change)) }
        catch { reportCatalogFailure(error) }
    }

    /// Opens the Close Game confirmation for a running game (Spotlight and Details).
    func askCloseGame(_ game: PortedGame) {
        closeGameFocus = .cancel
        gameToClose = game
    }

    func dismissCloseGame() {
        gameToClose = nil
        closeGameFocus = .cancel
    }

    /// Spotlight's Delete on a failed porting: the same confirmation as Game options' removal.
    func askRemoveGame(_ game: PortedGame) {
        removeGameFocus = .cancel
        gameToRemove = game
    }

    func dismissRemoveGame() {
        gameToRemove = nil
        removeGameFocus = .cancel
    }

    func confirmRemoveGame() {
        guard let game = gameToRemove else { return }
        dismissRemoveGame()
        deletePortedGame(game)
    }

    /// A library that could not be written: what the player sees would be gone at the next start, so say so once
    /// (in the log every time) instead of losing it in silence.
    func reportLibrarySaveFailure(_ error: Error) {
        let message = L10n.text("Arcane could not save your library, so recent changes may be lost when it quits: ")
            + error.localizedDescription
        logs.append(LogEntry(level: .error, message: message))
        if alertMessage == nil { alertMessage = message }
    }

    func updateStoredStatus(_ status: GameStatus, for game: PortedGame) {
        updateStoredGame(game) { $0.status = status }
    }

    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
