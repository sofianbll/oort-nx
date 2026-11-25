import XCTest
@testable import NXLibraryCore

final class NextStepCopyTests: XCTestCase {
    func testEveryEmptyTabSaysWhatFillsItInEveryLanguage() {
        for filter in LibraryFilter.allCases {
            XCTAssertNotEqual(filter.emptyCopy.title, filter.emptyCopy.hint)
            for language in AppLanguage.allCases {
                let locale = AppLocale(language: language, region: "FR")
                for text in [filter.emptyCopy.title, filter.emptyCopy.hint] {
                    XCTAssertFalse(L10n.text(text, context: locale).isEmpty)
                }
            }
        }
    }

    /// What a player reads alone, without a button beside it, says what to do: a second sentence in each language.
    func testErrorsAndEmptyScreensReadAloneSayWhatIsNext() {
        let keys = ["That file is not an image Arcane can read.", "This archive can't be opened.", "The key file has no header_key.",
                    "The backup folder could not be opened.", "Could not load the library entry for %@.",
                    "The app bundle is missing: %@", "This game has no valid title ID.",
                    "Arcane could not restart: %@", "Friends list unavailable.", "The player setup could not be saved.",
                    "No games match.", "No settings match.", "Nothing changed yet.", "No achievements here yet.",
                    "No completed builds yet.", "No friends yet.", "No games in this view.", "No controllers connected",
                    "No cloud games to download.", "No matching files or folders."]
        for key in keys {
            for language in AppLanguage.allCases {
                let text = L10n.text(key, context: AppLocale(language: language, region: "FR"))
                let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".。!：:")).filter {
                    !$0.trimmingCharacters(in: .whitespaces).isEmpty
                }
                XCTAssertGreaterThan(sentences.count, 1, "\(language): \(text)")
            }
        }
    }
}
