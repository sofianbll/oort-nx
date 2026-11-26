import XCTest
@testable import NXLibraryCore

final class RecentSearchesTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recent-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try XCTUnwrap(UserDefaults(suiteName: root.appendingPathComponent("prefs").path))
    }

    func testTheNewestComesFirstOnceAndFourAreKept() throws {
        let recent = RecentSearches(defaults: try defaults(), profile: UUID())
        for query in ["zelda", " Pokémon ", "mario", "kirby", "POKEMON", "", "   ", String(repeating: "x", count: 65)] {
            recent.record(query)
        }
        XCTAssertEqual(recent.list, ["POKEMON", "kirby", "mario", "zelda"])
        recent.record("donkey")
        XCTAssertEqual(recent.list, ["donkey", "POKEMON", "kirby", "mario"])
    }

    func testEachProfileSeesAndErasesOnlyItsOwn() throws {
        let store = try defaults(), one = UUID(), two = UUID()
        RecentSearches(defaults: store, profile: one).record("mario")
        RecentSearches(defaults: store, profile: two).record("zelda")
        XCTAssertEqual(RecentSearches(defaults: store, profile: one).list, ["mario"])
        RecentSearches(defaults: store, profile: one).clear()
        XCTAssertEqual(RecentSearches(defaults: store, profile: one).list, [])
        XCTAssertEqual(RecentSearches(defaults: store, profile: two).list, ["zelda"])
        RecentSearches(defaults: store, profile: two).clear()
        XCTAssertNil(store.object(forKey: RecentSearches.storageKey))
    }

    func testUnreadableContentIsAnEmptyList() throws {
        let store = try defaults()
        store.set("broken", forKey: RecentSearches.storageKey)
        XCTAssertEqual(RecentSearches(defaults: store, profile: nil).list, [])
    }
}

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
