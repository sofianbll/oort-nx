import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class GameSettingCatalogTests: XCTestCase {
    private func settings(_ names: [String]) throws -> [LauncherSetting] {
        let list = names.map { #"{"env":"\#($0)","kind":"toggle","section":"Game","label":"\#($0)","on":"1","off":"0","default":"0"}"# }
        return try JSONDecoder().decode([LauncherSetting].self, from: Data("[\(list.joined(separator: ","))]".utf8))
    }

    func testSortsKnownSettingsInCatalogOrderAndLeavesNoneOut() throws {
        let build = try settings(["DM_RUMBLE", "DM_NEW_IN_THIS_ENGINE", "DM_FPS_TARGET", "DM_LANG", "DM_METAL_HUD"])
        let groups = GameSettingCatalog.load().groups(for: build)
        XCTAssertEqual(groups.map(\.id), ["general", "picture", "controls", "performance", "other"])
        XCTAssertEqual(groups.last?.settings.map(\.env), ["DM_NEW_IN_THIS_ENGINE"])
        XCTAssertEqual(Set(groups.flatMap { $0.settings.map(\.env) }), Set(build.map(\.env)))
    }

    func testEnvLinesWithoutASettingGoUnderOtherAndFirstLineWins() throws {
        let groups = GameSettingCatalog.load().groups(
            for: try settings(["DM_LANG"]), envText: "# note\r\nDM_LANG=fr\r\nDM_NET_TRACE = 1\nDM_NET_TRACE=2\n\nrubbish\n")
        XCTAssertEqual(groups.map(\.id), ["general", "other"])
        XCTAssertEqual(groups[1].fileLines, [.init(key: "DM_NET_TRACE", value: "1")])
    }

    func testNoOtherWithoutUnknownsAndEverythingOtherWithoutACatalog() throws {
        let build = try settings(["DM_LANG", "DM_LANG"])
        XCTAssertEqual(GameSettingCatalog.load().groups(for: build).map(\.id), ["general"])
        let bare = GameSettingCatalog.load(engine: "unknown").groups(for: build)
        XCTAssertEqual(bare.map(\.id), ["other"])
        XCTAssertEqual(bare[0].settings.count, 1)
        XCTAssertTrue(GameSettingCatalog.load().groups(for: []).isEmpty)
    }

    func testNoSettingIsListedTwiceAndEveryTitleIsTranslated() {
        let catalog = GameSettingCatalog.load()
        let all = catalog.categories.flatMap(\.settings)
        XCTAssertEqual(all.count, Set(all).count)
        XCTAssertFalse(catalog.categories.isEmpty)
        let french = AppLocale(language: .french, region: nil)
        for title in catalog.categories.map(\.title) + ["Other"] where title != "Mods" {
            XCTAssertNotEqual(L10n.text(title, context: french), title)
        }
    }
}
