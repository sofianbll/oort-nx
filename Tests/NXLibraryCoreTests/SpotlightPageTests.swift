import XCTest
@testable import NXLibraryCore

final class SpotlightPageTests: XCTestCase {
    // MARK: - Description excerpt

    func testShortDescriptionIsKept() {
        let short = "A short line."
        XCTAssertEqual(DescriptionExcerpt.make(short, minLines: 4, charsPerLine: 40), .init(text: short, truncated: false))
    }

    func testShortStoreLeadUsesTheLongerLocalTextAndKeepsItsCreditInThePreview() {
        let url = URL(string: "https://fr.wikipedia.org/wiki/Fixture")!
        let lead = "Le jeu commence dans un village."
        let wiki = WikipediaDescription(text: "Les joueurs explorent les environs et rencontrent leurs voisins.", pageURL: url)
        let long = String(repeating: "Le village se développe au fil des saisons. ", count: 6)
        func about(_ text: String, tag: String, wiki: WikipediaDescription?) -> GameAboutDescription {
            let game = GameDetailPresentation(title: "Fixture", console: "", eyebrow: "", description: text,
                descriptionIsEnglishFallback: false, descriptionLanguageNote: tag == "en" ? "English text" : nil,
                descriptionLanguage: tag, descriptionSettled: true, descriptionExcerpt: lead,
                descriptionSource: "Title DB", genres: [], released: nil, developerLine: nil, thisWeek: "",
                rank: nil, publisher: nil, releaseYear: nil, playtime: "", lastPlayed: "", version: "", size: "",
                toolchainVerified: false, toolchainNote: nil, canPlay: false, canRebuild: false, sourcesDetached: false,
                hasBaseSource: false, storeURL: nil, hltbURL: nil, appPath: "", savePath: "")
            return game.aboutDescription(wikipedia: wiki, language: .french)
        }
        let nlib = about(long, tag: "fr", wiki: wiki)
        XCTAssertEqual(nlib.text, lead + " " + long)
        XCTAssertEqual(nlib.sources, ["Nintendo Europe", "Title DB"])
        XCTAssertNil(nlib.preview)
        XCTAssertNil(nlib.wikipediaPage)

        let supplemented = about("Long English fallback.", tag: "en", wiki: wiki)
        XCTAssertEqual(supplemented.text, lead + " " + wiki.text)
        XCTAssertNil(supplemented.preview)
        XCTAssertNil(supplemented.languageNote)
        XCTAssertEqual(supplemented.wikipediaPage, url)

        let fallback = about("Long English fallback.", tag: "en", wiki: nil)
        XCTAssertEqual(fallback.preview, lead)
        XCTAssertEqual(fallback.text, "Long English fallback.")
    }

    func testExcerptReachesTheLinesAtASentence() {
        let text = "First sentence is here. Second sentence follows it! Third one runs on and on past the limit for sure."
        let excerpt = DescriptionExcerpt.make(text, minLines: 2, charsPerLine: 30)
        XCTAssertEqual(excerpt.text, "First sentence is here. Second sentence follows it!")
        XCTAssertTrue(excerpt.truncated)
    }

    func testLineBreaksAndBlankLinesCount() {
        let text = "Title\nIntro line.\n\nBody one. Body two. Body three. Body four is long enough."
        let excerpt = DescriptionExcerpt.make(text, minLines: 3, charsPerLine: 40)
        XCTAssertEqual(excerpt.text, "Title\nIntro line.\n\nBody one.")
        XCTAssertTrue(excerpt.truncated)
    }

    func testAShortRestIsShownInFull() {
        let text = "One two three. Four."
        XCTAssertEqual(DescriptionExcerpt.make(text, minLines: 1, charsPerLine: 15), .init(text: text, truncated: false))
    }

    func testNoSentenceEndCutsAtAWord() {
        let text = String(repeating: "word ", count: 40)
        let excerpt = DescriptionExcerpt.make(text, minLines: 2, charsPerLine: 20)
        XCTAssertEqual(excerpt.text, "word word word word word word word word…")
        XCTAssertTrue(excerpt.truncated)
    }

    func testARunOnSentenceCutsAtAWord() {
        let text = "Short. " + String(repeating: "on ", count: 60) + "end."
        let excerpt = DescriptionExcerpt.make(text, minLines: 2, charsPerLine: 20)
        XCTAssertTrue(excerpt.text.hasSuffix("…"))
        XCTAssertLessThanOrEqual(excerpt.text.count, 41)
        XCTAssertTrue(excerpt.truncated)
    }

    // MARK: - Page scroll

    /// Window 1000 high, hints clearance 130, About at 900 and More at 1500 from the page top, page ends at 1900.
    func testMoreRestsWithThePageEndAboveTheHints() {
        let rest = SpotlightPageScroll.resting(first: -324, aboutTop: 900, moreTop: 1500, pageBottom: 1900,
                                               top: 150, viewport: 1000, bottomInset: 130)
        XCTAssertEqual(rest.actions, -750, "About this game comes up to 150")
        XCTAssertEqual(rest.more, -1030, "the page's end sits 130 above the window's bottom, not More at 150")
        XCTAssertGreaterThan(rest.more, 150 - 1500)
    }

    func testShortPageNeverScrollsPastItsEnd() {
        let rest = SpotlightPageScroll.resting(first: -324, aboutTop: 700, moreTop: 1000, pageBottom: 1300,
                                               top: 150, viewport: 1000, bottomInset: 130)
        XCTAssertEqual(rest.actions, -430, "the page's end limits Details too")
        XCTAssertEqual(rest.more, -430)
    }

    func testTallMoreBandStillComesUpToTheTop() {
        let rest = SpotlightPageScroll.resting(first: -324, aboutTop: 900, moreTop: 1500, pageBottom: 3000,
                                               top: 150, viewport: 1000, bottomInset: 130)
        XCTAssertEqual(rest.more, -1350)
    }

    func testRestsNeverRiseAboveThePills() {
        let rest = SpotlightPageScroll.resting(first: -324, aboutTop: 300, moreTop: nil, pageBottom: 500,
                                               top: 150, viewport: 1000, bottomInset: 130)
        XCTAssertEqual(rest.actions, -324)
        XCTAssertEqual(rest.more, -324)
    }

    func testReadMoreIsBroughtAboveTheHints() {
        XCTAssertEqual(SpotlightPageScroll.revealing(-750, bottom: 2000, viewport: 1000, bottomInset: 130), -1130)
        XCTAssertEqual(SpotlightPageScroll.revealing(-750, bottom: 1500, viewport: 1000, bottomInset: 130), -750,
                       "already visible: the page stays")
    }
}
