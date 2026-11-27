import AppKit
import NXLibraryCore

extension AppViewModel {
    var visibleCatalogGames: [CatalogGame] {
        CatalogLibraryProjection.visible(games: catalogGames, sources: catalogSourceConfigurations)
    }
    func setCatalogFavorite(_ game: CatalogGame) {
        if toggleLocalFavorite(game.id) { return }
        let removing = catalogGames.first { $0.id == game.id }?.isFavorite == true
        do {
            applyCatalog(try catalogRepository.toggleFavorite(for: game.id))
            if removing { offerFavoriteUndo(game.id) }
        } catch { reportCatalogFailure(error) }
    }
    @discardableResult
    func setCatalogHidden(_ hidden: Bool, game: CatalogGame) -> Bool {
        let hiding = hidden && catalogGames.first { $0.id == game.id }?.isHidden == false
        do {
            applyCatalog(try catalogRepository.setHidden(hidden, for: game.id))
            if hiding { offerHiddenUndo(game.id) }
            return true
        } catch { reportCatalogFailure(error); return false }
    }
    var currentFocusedCatalogGame: CatalogGame? {
        let id: UUID?
        switch router?.route {
        case .detail(let value): id = value
        case .library: id = spotlight.selectedGameID
        case .collection, .profileCollection: id = librarySelection.selectedGameID
        default: id = nil
        }
        guard let id else { return nil }
        return visibleCatalogGames.first { $0.id == id }
    }
}
