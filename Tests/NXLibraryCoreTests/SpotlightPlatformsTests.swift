import XCTest
@testable import NXLibraryCore

final class SpotlightPlatformsTests: XCTestCase {
    private let switchSource = CatalogIntegration(rawValue: "nxnative")
    private let later = CatalogIntegration(rawValue: "zeta")
    private let earlier = CatalogIntegration(rawValue: "alpha")

    func testChoicesAreCatalogCountsAndDoNotReorderTheQuery() {
        let z = game("Zelda", FixtureSwitch.self, favorite: true)
        let a = game("Adventure", FixtureSwitch.self, favorite: true)
        let steam = game("Steam", FixtureSteam.self, installed: false)
        let mac = game("Mac", FixtureMac.self, favorite: true)
        let hidden = game("Hidden", FixtureSwitch.self, favorite: true, hidden: true)
        let catalog = [z, steam, hidden, game("Zeta", FixtureZeta.self), mac, a, game("Alpha", FixtureAlpha.self)]
        let platforms = projection(catalog)
        XCTAssertEqual(platforms.cards.map(\.integration), [nil, switchSource, .steam, .macShortcut, earlier, later])
        XCTAssertEqual(platforms.cards.map(\.count), [6, 2, 1, 1, 1, 1])
        for (filter, cloud, expected): (LibraryFilter, Set<UUID>, [UUID]) in [
            (.favorites, [], [a.id, z.id]), (.cloud, [z.id, mac.id], [z.id]), (.installed, [], [a.id, z.id])
        ] {
            let queried = LibraryQuery(filter: filter, sort: .name).applyCatalog(to: catalog, history: NoPlayHistory(), cloudOnly: cloud)
            XCTAssertEqual(platforms.games(queried, on: switchSource).map(\.id), expected)
        }
        let installed = LibraryQuery(filter: .installed).applyCatalog(to: catalog, history: NoPlayHistory())
        XCTAssertTrue(platforms.games(installed, on: .steam).isEmpty)
        XCTAssertEqual(platforms.card(for: .steam).count, 1)
    }

    func testEmptySinglePlatformUnknownAndPickerSettling() {
        let empty = projection([])
        XCTAssertEqual(empty.cards, [.init(integration: nil, count: 0)])
        let mac = game("Mac", FixtureMac.self)
        let one = projection([mac])
        let unknown = CatalogIntegration(rawValue: "not-installed")
        XCTAssertNil(one.card(for: unknown).integration)
        XCTAssertEqual(one.games([mac], on: unknown), [mac])

        var picker = SpotlightPlatformPicker(unknown, in: one)
        XCTAssertFalse(picker.wantsCommit)
        XCTAssertFalse(picker.move(by: -1, in: one))
        XCTAssertTrue(picker.move(by: 1, in: one))
        XCTAssertEqual(picker.cursor, .macShortcut)
        XCTAssertTrue(picker.wantsCommit)
        XCTAssertNil(picker.settled)
        XCTAssertFalse(picker.move(by: 1, in: one))
        picker.settle()
        XCTAssertEqual(picker.settled, .macShortcut)
        picker.reconcile(in: empty)
        XCTAssertNil(picker.cursor)
        XCTAssertNil(picker.settled)
        XCTAssertFalse(picker.wantsCommit)
    }

    func testAnUnknownRecordIsPreservedButNeverGetsACard() throws {
        let unknown = game("Unknown", FixtureAlpha.self)
        let document = CatalogDocument(sources: [.init(integration: earlier, isEnabled: true)], games: [unknown])
        let decoded = try JSONDecoder().decode(CatalogDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.preservedGames.count, 1)
        XCTAssertTrue(decoded.games.isEmpty)
        XCTAssertEqual(projection(CatalogLibraryProjection.visible(games: decoded.games, sources: decoded.sources)).cards,
                       [.init(integration: nil, count: 0)])
    }

    func testRailHeadCannotBeLiftedOrDisplaced() {
        let game = SpotlightItem.game(UUID())
        let items: [SpotlightItem] = [.platform, game, .card(.addGame)]
        var state = SpotlightState()
        state.reconcile(with: items)
        XCTAssertEqual(state.selectedItem(in: items), game)
        XCTAssertTrue(state.move(by: -1, in: items))
        XCTAssertEqual(state.selectedItem(in: items), .platform)
        XCTAssertFalse(state.beginLift(in: items))
        XCTAssertEqual(SpotlightRow.moving(game, by: -1, in: items), items)
        XCTAssertEqual(SpotlightRow.moving(.platform, by: 1, in: items), items)
    }

    private func projection(_ games: [CatalogGame]) -> SpotlightPlatforms {
        SpotlightPlatforms(listedGames: games, preferredOrder: [switchSource, .steam, .macShortcut])
    }

    private func game<T: FixtureSource>(_ name: String, _ type: T.Type, favorite: Bool = false,
                                       hidden: Bool = false, installed: Bool = true) -> CatalogGame {
        CatalogGame(record: Fixture<T>(name: name, isFavorite: favorite, isHidden: hidden, isInstalledForLibrary: installed),
                    personalizationKey: name)
    }
}

private protocol FixtureSource {
    static var integration: CatalogIntegration { get }
}

private enum FixtureSwitch: FixtureSource { static let integration = CatalogIntegration(rawValue: "nxnative") }
private enum FixtureSteam: FixtureSource { static let integration = CatalogIntegration.steam }
private enum FixtureMac: FixtureSource { static let integration = CatalogIntegration.macShortcut }
private enum FixtureAlpha: FixtureSource { static let integration = CatalogIntegration(rawValue: "alpha") }
private enum FixtureZeta: FixtureSource { static let integration = CatalogIntegration(rawValue: "zeta") }

private struct Fixture<Source: FixtureSource>: CatalogSourceRecord {
    static var integration: CatalogIntegration { Source.integration }
    var id = UUID()
    let name: String
    var isFavorite: Bool
    var isHidden: Bool
    let isInstalledForLibrary: Bool
    var librarySearchTerms: [String] { [] }
    func validateRecord(personalizationKey: String) throws {}
    func presence(sourceEnabled: Bool) -> CatalogRecordPresence {
        .init(requiresReview: false, isDownloading: false, isListedNormally: sourceEnabled, launchTarget: nil, installations: [])
    }
}
