import XCTest
@testable import NXLibraryCore

/// The one setting behind every Nextendo player count: where it shows and whether it is asked for.
final class OnlinePlayersDisplayTests: XCTestCase {
    private let title = "01000000000000AB"
    private let counts = ["01000000000000ab": 12, "01000000000000bb": 0]

    func testFourChoicesWithTheDotByDefault() {
        XCTAssertEqual(OnlinePlayersDisplay.allCases, [.dot, .selectedGame, .gamePage, .never])
        XCTAssertEqual(OnlinePlayersDisplay.allCases.map(\.label),
                       ["Dot", "On selected game", "Game page only", "Never"])
        XCTAssertEqual(AppSettings().onlinePlayersDisplay, .dot)
    }

    func testEachChoiceShowsTheCountInItsOwnPlaces() {
        let shown: [OnlinePlayersDisplay: Set<OnlinePlayersDisplay.Place>] = [
            .dot: [.tile, .gamePage], .selectedGame: [.selectedGame], .gamePage: [.gamePage], .never: [],
        ]
        for display in OnlinePlayersDisplay.allCases {
            for place in OnlinePlayersDisplay.Place.allCases {
                XCTAssertEqual(display.count(for: title, in: counts, at: place),
                               shown[display]!.contains(place) ? 12 : nil, "\(display) \(place)")
            }
        }
    }

    func testNoCountForNoTitleNobodyOnlineOrAnUnknownTitle() {
        for title in [nil, "01000000000000BB", "01000000000000cc"] {
            XCTAssertNil(OnlinePlayersDisplay.dot.count(for: title, in: counts, at: .tile))
        }
    }

    func testOnlyNeverStopsAskingTheService() {
        XCTAssertEqual(OnlinePlayersDisplay.allCases.map(\.asksService), [true, true, true, false])
    }

    func testAMissingOrUnknownChoiceReadsAsTheDot() throws {
        for json in ["{}", #"{"onlinePlayersDisplay":"somethingNewer"}"#, #"{"onlinePlayersDisplay":3}"#] {
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.onlinePlayersDisplay, .dot, json)
        }
    }

    func testTheChoiceSurvivesSavingAndKeepsItsStoredName() throws {
        XCTAssertEqual(OnlinePlayersDisplay.allCases.map(\.rawValue), ["dot", "selectedGame", "gamePage", "never"])
        var settings = AppSettings()
        settings.onlinePlayersDisplay = .never
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).onlinePlayersDisplay, .never)
    }

    func testResettingMultiplayerBringsTheDotBack() {
        var settings = AppSettings()
        settings.onlinePlayersDisplay = .never
        XCTAssertEqual(SettingsReset.resetShared(.multiplayer, in: settings).onlinePlayersDisplay, .dot)
    }

    func testTheRowSitsInMultiplayerAndIsMarkedChanged() throws {
        let row = try XCTUnwrap(SettingsCatalog.baseRows.first { $0.id == "onlinePlayersDisplay" })
        XCTAssertEqual(row.group, .multiplayer)
        XCTAssertEqual(row.title, "Online players")
        var settings = AppSettings()
        XCTAssertFalse(row.isChanged(settings))
        settings.onlinePlayersDisplay = .gamePage
        XCTAssertTrue(row.isChanged(settings))
    }

    func testTheCountJoinsThePlayersFact() {
        let french = AppLocale(language: .french, region: "FR")
        let facts = [DetailsFact(kind: .publisher, value: "P"), DetailsFact(kind: .players, value: "1–4"),
                     DetailsFact(kind: .version, value: "1.0")]
        let added = facts.addingOnlinePlayers(12, context: french)
        XCTAssertEqual(added.map(\.kind), [.publisher, .players, .version])
        XCTAssertEqual(added[1].value, "1–4 · 12 en ligne")
        XCTAssertEqual(facts.addingOnlinePlayers(nil, context: french), facts)
    }

    func testTheCountMakesThePlayersFactInItsPlaceWhenTheStoreHasNone() {
        let french = AppLocale(language: .french, region: "FR")
        let facts = [DetailsFact(kind: .developer, value: "D"), DetailsFact(kind: .version, value: "1.0")]
        let added = facts.addingOnlinePlayers(3, context: french)
        XCTAssertEqual(added.map(\.kind), [.developer, .players, .version])
        XCTAssertEqual(added[1].value, "3 en ligne")
    }
}
