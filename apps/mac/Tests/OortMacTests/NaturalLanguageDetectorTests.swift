import XCTest
@testable import OortLibrary
@testable import OortMac

/// The Mac's detector names the languages the core's tests assume (`WikipediaLanguageFixtures`), and the core's
/// choices hold with it: what NaturalLanguage did inside the core before.
final class NaturalLanguageDetectorTests: XCTestCase {
    private let detector = NaturalLanguageDetector()
    private let english = "Stardew Valley is a farming simulation game where you inherit your grandfather's old farm plot."
    private let italian = "Stardew Valley è un videogioco indipendente del 2016, sviluppato da ConcernedApe e pubblicato da Chucklefish."
    private let simplified = "《超级马力欧兄弟 惊奇》是一款由任天堂企划制作本部开发，并由任天堂发行在任天堂Switch平台上的平台动作游戏，于2023年10月20日发售。"
    private let traditional = "《超級瑪利歐兄弟 驚奇》是一款由任天堂企劃製作本部開發，並由任天堂發行在任天堂Switch平台上的平台動作遊戲，於2023年10月20日發售。"

    override func invokeTest() {
        PlatformServices.$scoped.withValue(.init(languageDetector: detector)) { super.invokeTest() }
    }

    func testTheFixturesLanguagesAreNaturalLanguagesOwn() throws {
        for (text, tag) in [(english, "en"), (italian, "it"), (simplified, "zh-Hans"), (traditional, "zh-Hant")] {
            let found = try XCTUnwrap(detector.dominantLanguage(of: text), tag)
            XCTAssertEqual(found.tag, tag)
            XCTAssertGreaterThanOrEqual(found.confidence, WikipediaDescriptions.minimumConfidence, tag)
        }
    }

    func testStoreTextInAnotherLanguageIsReplacedAndTheSameIsKept() {
        XCTAssertTrue(WikipediaDescriptions.wanted(description: english, descriptionLanguage: nil, language: .italian))
        XCTAssertFalse(WikipediaDescriptions.wanted(description: italian, descriptionLanguage: nil, language: .italian))
        XCTAssertFalse(WikipediaDescriptions.wanted(description: simplified, descriptionLanguage: nil, language: .chineseSimplified))
        XCTAssertTrue(WikipediaDescriptions.wanted(description: traditional, descriptionLanguage: nil, language: .chineseSimplified))
        XCTAssertFalse(WikipediaDescriptions.wanted(description: "A farming game.", descriptionLanguage: nil, language: .italian))
    }

    func testSpanishOpeningPunctuationIsNotMistakenForCatalan() {
        XCTAssertEqual(NaturalLanguageDetector.resolvedTag(.catalan, text: "¡Visita el pueblo y busca a tus amigos!"), "es")
        XCTAssertEqual(NaturalLanguageDetector.resolvedTag(.catalan, text: "Visita el poble i cerca els teus amics!"), "ca")
    }
}
