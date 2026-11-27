import XCTest
@testable import OortLibrary

final class OnlinePlayersDisplayTests: XCTestCase {
    func testAllSixteenCombinationsKeepTheirOwnPlacesAndRoundTrip() throws {
        let places = OnlinePlayersDisplay.Place.allCases
        XCTAssertEqual(places.count, 4)
        for mask in 0..<16 {
            let enabled = places.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            var settings = AppSettings()
            settings.onlinePlayersDisplay = .init(Set(enabled))
            let loaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(loaded, settings)
            XCTAssertEqual(loaded.onlinePlayersDisplay.asksService, mask != 0)
            for place in places {
                XCTAssertEqual(loaded.onlinePlayersDisplay.count(for: "AB", in: ["ab": 12], at: place),
                               enabled.contains(place) ? 12 : nil)
            }
        }
    }

    func testOldStringsKeepTheirVisiblePlaces() throws {
        let old: [String: Set<OnlinePlayersDisplay.Place>] = [
            "dot": [.tile, .details], "selectedGame": [.selectedGame], "gamePage": [.details], "never": [],
        ]
        for (raw, places) in old {
            let data = Data(#"{"onlinePlayersDisplay":"\#(raw)"}"#.utf8)
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).onlinePlayersDisplay, .init(places), raw)
        }
    }

    func testAbsentUnknownAndResetUseTheNewDefault() throws {
        let expected = OnlinePlayersDisplay([.tile, .selectedGame])
        XCTAssertEqual(AppSettings().onlinePlayersDisplay, expected)
        for json in ["{}", #"{"onlinePlayersDisplay":"somethingNewer"}"#] {
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).onlinePlayersDisplay, expected)
        }
        var settings = AppSettings()
        settings.onlinePlayersDisplay = .init([])
        XCTAssertEqual(SettingsReset.resetShared(.multiplayer, in: settings).onlinePlayersDisplay, expected)
    }

    func testToggleChangesOnlyItsPlaceAndItsCatalogRow() throws {
        let places = OnlinePlayersDisplay.Place.allCases
        for place in places {
            let row = try XCTUnwrap(SettingsCatalog.baseRows.first { $0.id == place.id })
            XCTAssertEqual(row.group, .multiplayer)
            var settings = AppSettings()
            XCTAssertFalse(row.isChanged(settings))
            settings.onlinePlayersDisplay[place].toggle()
            XCTAssertTrue(row.isChanged(settings))
            for other in places where other != place {
                XCTAssertEqual(settings.onlinePlayersDisplay[other], AppSettings().onlinePlayersDisplay[other])
            }
        }
    }

    func testNoCountForNoTitleNobodyOnlineOrAnUnknownTitle() {
        for title in [nil, "BB", "cc"] {
            XCTAssertNil(OnlinePlayersDisplay([.tile]).count(for: title, in: ["bb": 0], at: .tile))
        }
    }
}
