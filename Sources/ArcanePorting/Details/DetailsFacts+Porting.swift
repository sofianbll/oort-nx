import Foundation
import NXLibraryCore

extension DetailsFacts {
    /// A ported game: credits, game version, installed engine, size and app folder.
    public static func switchGame(_ game: PortedGame, metadata: NintendoStoreMetadata?,
                                  folderName: String?, engine: String, locale: Locale = L10n.context.formatLocale) -> [DetailsFact] {
        let players = metadata?.playersTo.map { last in
            let to = last.formatted(.number.locale(locale))
            guard let first = metadata?.playersFrom, first < last else { return to }
            return first.formatted(.number.locale(locale)) + "–" + to
        }
        return rows([.developer: names(metadata?.developers),
              .publisher: names(metadata?.publishers),
              .players: players,
              .ageRating: text(metadata?.ageRating),
              .version: text(game.versionString),
              .engine: engine,
              .size: size(game.sizeBytes, locale: locale),
              .location: text(folderName)])
    }
}
