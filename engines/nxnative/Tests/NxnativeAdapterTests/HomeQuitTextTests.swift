import XCTest
import NXLibraryCore
@testable import ArcanePorting

final class HomeQuitTextTests: XCTestCase {
    override func tearDown() { L10n.setContext(AppLocale(language: .english, region: "US")) }

    /// The engine reads one text per line and keeps its own for an empty one; each must fit its 256 bytes.
    func testTheGamesQuestionIsInThePlayersLanguage() {
        let expected = ["fr": "La progression non enregistrée sera perdue.", "en": "Unsaved progress will be lost."]
        for (language, note) in [(AppLanguage.french, expected["fr"]!), (.english, expected["en"]!)] {
            L10n.setContext(AppLocale(language: language, region: nil))
            let lines = LaunchService.quitText(gameName: "Tomb\nRaid").components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 7, "\(language)")
            XCTAssertEqual(lines[2], note)
            XCTAssertTrue(lines[1].contains("Tomb Raid"))
            XCTAssertTrue(lines[6].contains(AppIdentity.displayName))
            for line in lines { XCTAssertFalse(line.isEmpty); XCTAssertLessThan(line.utf8.count, 256) }
        }
        L10n.setContext(AppLocale(language: .french, region: nil))
        XCTAssertEqual(Array(LaunchService.quitText(gameName: "Tomb").components(separatedBy: "\n").prefix(5)),
                       ["Maintiens pour quitter", "Quitter Tomb ?", "La progression non enregistrée sera perdue.", "Quitter", "Annuler"])
    }

    func testEveryGameStartedFromOortGetsIt() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let launch = try String(contentsOf: root.appendingPathComponent("Sources/NXLibrary/ViewModels/AppViewModel+Launch.swift"), encoding: .utf8)
        XCTAssertTrue(launch.contains("launchService.launch(appURL: native.url, environment: spoken,"))
    }
}
