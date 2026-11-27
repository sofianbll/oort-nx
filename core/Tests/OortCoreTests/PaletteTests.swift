import XCTest
@testable import OortCore

final class PaletteTests: XCTestCase {
    private func game(_ name: String, _ id: String? = nil) -> PaletteItem {
        PaletteItem(id: "game:" + (id ?? name), kind: .game, title: name, secondary: "Options")
    }
    private func action(_ title: String, english: String? = nil, section: String = "Library", remembered: Bool = true) -> PaletteItem {
        PaletteItem(id: "action:" + title, kind: .action, title: title, section: section,
                    aliases: english.map { [$0] } ?? [], isRemembered: remembered)
    }
    private func setting(_ title: String, notes: [String] = [], section: String = "General") -> PaletteItem {
        PaletteItem(id: "setting:" + title, kind: .setting, title: title, section: section, notes: notes)
    }
    private func titles(_ groups: [PaletteGroup]) -> [[String]] { groups.map { $0.items.map(\.title) } }

    // MARK: - Text

    func testTextIgnoresCaseAccentsMarksAndPunctuation() {
        XCTAssertEqual(PaletteText.normalize("  Pokémon™ Légendes : Z-A "), "pokemon legendes z a")
        XCTAssertEqual(PaletteText.normalize("Cœur d’Or"), "coeur d or")
        XCTAssertEqual(PaletteText.normalize("Straße"), "strasse")
        XCTAssertEqual(PaletteText.normalize("ＡＢＣ"), "abc")
        XCTAssertEqual(PaletteText.normalize(""), "")
    }

    func testAWordIsFoundByItsStartWithoutAccents() {
        let items = [game("Forêt Étoilée"), game("Lunar Observatory")]
        XCTAssertEqual(titles(Palette.groups(query: "etoi", in: items)), [["Forêt Étoilée"]])
        XCTAssertEqual(titles(Palette.groups(query: "ÉTOILÉE FOR", in: items)), [["Forêt Étoilée"]])
    }

    func testASmallMistakeStillFinds() {
        let items = [game("Lunar Observatory"), action("Thème", english: "Theme"), action("Joueurs", english: "Players")]
        for query in ["lunra", "luner", "lnuar", "lunarr", "observatroy"] {
            XCTAssertEqual(titles(Palette.groups(query: query, in: items)), [["Lunar Observatory"]], query)
        }
        XCTAssertEqual(titles(Palette.groups(query: "theem", in: items)), [["Thème"]])
        XCTAssertEqual(titles(Palette.groups(query: "plyers", in: items)), [["Joueurs"]])
    }

    func testAShortWordIsNeverGuessed() {
        XCTAssertEqual(titles(Palette.groups(query: "sno", in: [setting("Son"), setting("Sol")])), [])
        XCTAssertEqual(titles(Palette.groups(query: "zzzzzz", in: [game("Lunar Observatory")])), [])
    }

    func testAnExactTitleKeepsGuessesOut() {
        let items = [game("Comet"), game("Comets Away"), game("Covet")]
        XCTAssertEqual(titles(Palette.groups(query: "comet", in: items)), [["Comet", "Comets Away"]])
    }

    func testAMistakeIsStillFoundWhenOnlyADescriptionMatches() {
        let items = [setting("Son", notes: ["Un mot lunra au milieu."]), game("Lunar Observatory")]
        XCTAssertEqual(Set(titles(Palette.groups(query: "lunra", in: items)).flatMap { $0 }), ["Son", "Lunar Observatory"])
    }

    func testOneLetterOnlyMatchesTheStartOfAWord() {
        let items = [game("Lunar Observatory"), game("Solar Field")]
        XCTAssertEqual(titles(Palette.groups(query: "o", in: items)), [["Lunar Observatory"]])
    }

    func testChineseIsFoundInsideATitle() {
        XCTAssertEqual(titles(Palette.groups(query: "戏", in: [action("游戏库")])), [["游戏库"]])
        XCTAssertEqual(titles(Palette.groups(query: "戲", in: [action("游戏库")])), [])
    }

    func testLettersTypedTogetherFindASplitName() {
        XCTAssertEqual(titles(Palette.groups(query: "za", in: [game("Orbit Z-A")])), [["Orbit Z-A"]])
    }

    func testEnglishNamesFindTranslatedActions() {
        XCTAssertEqual(titles(Palette.groups(query: "sleep", in: [action("Mettre le Mac en veille", english: "Sleep")])),
                       [["Mettre le Mac en veille"]])
    }

    func testTheWordThePlayerReadsComesBeforeTheEnglishOne() {
        let items = [action("Trier les fichiers", english: "Sort files"), setting("Sons")]
        XCTAssertEqual(titles(Palette.groups(query: "so", in: items)), [["Sons"], ["Trier les fichiers"]])
    }

    func testTheBestTitleComesFirstAndTheLibraryOrderStays() {
        let items = [game("Star Orbit"), game("Orbit"), game("Orbit Two"), game("Far Orbit")]
        XCTAssertEqual(titles(Palette.groups(query: "orbit", in: items)), [["Orbit", "Orbit Two", "Star Orbit", "Far Orbit"]])
    }

    // MARK: - Groups

    func testGroupsHoldFiveThenSeeAll() throws {
        let items = (1...7).map { game("Orbit \($0)") } + [action("Orbit")]
        let groups = Palette.groups(query: "orbit", in: items)
        XCTAssertEqual(groups.map(\.id), [.kind(.action), .kind(.game)])
        let games = try XCTUnwrap(groups.last)
        XCTAssertEqual(games.items.count, 5)
        XCTAssertEqual(games.seeAll, .game)
        XCTAssertEqual(games.total, 7)
        XCTAssertNil(groups[0].seeAll)
        XCTAssertEqual(Palette.groups(query: "orbit", scope: .game, in: items).map(\.items.count), [7])
        XCTAssertTrue(Palette.groups(query: "orbit", scope: .game, in: items).allSatisfy { $0.seeAll == nil })
    }

    func testSameScoreKeepsGamesThenActionsThenSettings() {
        let items = [setting("Orbit c"), action("Orbit b"), game("Orbit a")]
        XCTAssertEqual(Palette.groups(query: "orbit", in: items).map(\.id), [.kind(.game), .kind(.action), .kind(.setting)])
    }

    func testAnEmptyFieldShowsRecentsSuggestionsAndWhatToBrowse() {
        let actions = (1...8).map { action("Action \($0)") }
        let items = [game("Lunar")] + actions + [setting("Son")]
        let groups = Palette.groups(query: " ", in: items, recents: ["game:Lunar", "gone", "action:Action 1"],
                                    suggestions: actions.map(\.id))
        XCTAssertEqual(groups.map(\.id), [.recents, .suggestions, .browse])
        XCTAssertEqual(groups[0].items.map(\.title), ["Lunar", "Action 1"])
        XCTAssertEqual(groups[1].items.map(\.title), ["Action 2", "Action 3", "Action 4", "Action 5", "Action 6"])
        XCTAssertEqual(groups[2].rows, [.seeAll(.game, 1), .seeAll(.action, 8), .seeAll(.setting, 1)])
    }

    func testNothingInstalledStillShowsSuggestions() {
        let groups = Palette.groups(query: "", in: [action("Add")], suggestions: ["action:Add"])
        XCTAssertEqual(groups.map(\.id), [.suggestions, .browse])
        XCTAssertEqual(groups[1].rows, [.seeAll(.action, 1)])
    }

    func testBrowsingKeepsTheSectionsInOrder() {
        let items = [action("A", section: "Library"), action("B", section: "Power"), action("C", section: "Library")]
        let groups = Palette.groups(query: "", scope: .action, in: items)
        XCTAssertEqual(groups.map(\.id), [.section("Library"), .section("Power")])
        XCTAssertEqual(titles(groups), [["A", "C"], ["B"]])
    }

    // MARK: - Focus

    func testFocusMovesClampsAndReturnsToTheTopWithTheQuery() {
        var state = PaletteState()
        XCTAssertFalse(state.move(by: -1, count: 4))
        XCTAssertTrue(state.move(by: 1, count: 4))
        XCTAssertTrue(state.jump(toEnd: true, count: 4))
        XCTAssertEqual(state.focus, 3)
        XCTAssertFalse(state.move(by: 1, count: 4))
        state.setQuery("a")
        XCTAssertEqual(state.focus, 0)
        XCTAssertFalse(state.move(by: 1, count: 0))
        state.settle(count: 0)
        XCTAssertEqual(state.focus, 0)
    }

    func testFocusStaysOnItsRowWhenTheListGetsShorter() {
        var state = PaletteState()
        _ = state.jump(toEnd: true, count: 9)
        state.settle(count: 3)
        XCTAssertEqual(state.focus, 2)
    }

    func testShouldersGoFromGroupToGroup() {
        let items = (1...7).map { game("Orbit \($0)") } + [action("Orbit x"), setting("Orbit y")]
        let groups = Palette.groups(query: "orbit", in: items)      // games 6 rows, action 1, setting 1
        var state = PaletteState()
        XCTAssertTrue(state.moveGroup(by: 1, in: groups))
        XCTAssertEqual(state.focus, 6)
        XCTAssertTrue(state.moveGroup(by: 1, in: groups))
        XCTAssertEqual(state.focus, 7)
        XCTAssertFalse(state.moveGroup(by: 1, in: groups))
        XCTAssertTrue(state.moveGroup(by: -1, in: groups))
        XCTAssertEqual(state.focus, 6)
        state.focus = 4
        XCTAssertTrue(state.moveGroup(by: -1, in: groups))
        XCTAssertEqual(state.focus, 0)
        XCTAssertFalse(state.moveGroup(by: -1, in: groups))
    }

    func testBackLeavesSeeAllFirstAndFindsItsRowAgain() {
        var state = PaletteState(query: "orbit")
        state.focus = 5
        state.open(.game)
        XCTAssertEqual(state.scope, .game)
        XCTAssertEqual(state.focus, 0)
        state.focus = 3
        XCTAssertTrue(state.back())
        XCTAssertNil(state.scope)
        XCTAssertEqual(state.focus, 5)
        XCTAssertEqual(state.query, "orbit")
        XCTAssertFalse(state.back())
    }

    func testANewQueryInsideSeeAllForgetsTheOldRow() {
        var state = PaletteState(query: "orbit")
        state.focus = 5
        state.open(.game)
        state.setQuery("orb")
        XCTAssertTrue(state.back())
        XCTAssertEqual(state.focus, 0)
    }

    // MARK: - Recents

    func testRecentsKeepTheLastFiveOnce() {
        var recents: [String] = []
        for id in ["a", "b", "c", "d", "e", "f", "b"] { recents = PaletteRecents.adding(id, to: recents) }
        XCTAssertEqual(recents, ["b", "f", "e", "d", "c"])
    }

    func testAnActionThatEndsTheSessionIsNotRemembered() {
        XCTAssertEqual(PaletteRecents.adding(action("Quit", remembered: false), to: ["a"]), ["a"])
        XCTAssertEqual(PaletteRecents.adding(action("Theme"), to: ["a"]), ["action:Theme", "a"])
    }

    func testEveryKeystrokeStaysLight() {
        let items = (0..<600).map { game("Lunar Observatory volume \($0)") }
            + (0..<200).map { setting("Réglage \($0)", notes: ["Une phrase assez longue pour décrire ce réglage."]) }
        measure { _ = Palette.groups(query: "observatroy", in: items) }
    }
}
