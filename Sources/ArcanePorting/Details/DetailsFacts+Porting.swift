import Foundation
import NXLibraryCore

extension DetailsFacts {
    /// A ported game: credits, game version, installed engine, size and app folder.
    public static func switchGame(_ game: PortedGame, metadata: NintendoStoreMetadata?,
                                  folderName: String?, engine: String, locale: Locale = L10n.context.formatLocale) -> [DetailsFact] {
        rows([.developer: names(metadata?.developers),
              .publisher: names(metadata?.publishers),
              .version: text(game.versionString),
              .engine: engine,
              .size: size(game.sizeBytes, locale: locale),
              .location: text(folderName)])
    }
}
