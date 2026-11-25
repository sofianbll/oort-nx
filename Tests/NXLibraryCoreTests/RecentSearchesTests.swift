import XCTest
@testable import NXLibraryCore

final class NextStepCopyTests: XCTestCase {
    /// What a player reads alone, without a button beside it, says what to do: a second sentence in each language.
    func testErrorsAndEmptyScreensReadAloneSayWhatIsNext() {
        let keys = ["That file is not an image Arcane can read.", "This archive can't be opened.", "The key file has no header_key.",
                    "The backup folder could not be opened.", "Could not load the library entry for %@.",
                    "The app bundle is missing: %@", "This game has no valid title ID.",
                    "Arcane could not restart: %@", "Friends list unavailable.", "The player setup could not be saved."]
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
