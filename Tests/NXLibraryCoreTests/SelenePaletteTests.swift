import XCTest
@testable import NXLibraryCore

final class SelenePaletteTests: XCTestCase {
    private var paletteURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Selene/palettes.json")
    }

    func testLoadsAll26Palettes() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        XCTAssertEqual(all.count, 26)
        let ids = Set(all.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["oort", "selene", "white", "catppuccin-latte"]))
    }

    /// The picker: Oort, the default, first; then the rest by name.
    func testPickerOrderPutsTheDefaultFirstThenAlphabetical() throws {
        let ordered = SelenePaletteCatalog.pickerOrder(try SelenePaletteCatalog.load(from: paletteURL))
        XCTAssertEqual(ordered.first?.id, SelenePaletteCatalog.defaultID)
        XCTAssertEqual(SelenePaletteCatalog.defaultID, "oort")
        let rest = ordered.dropFirst().map(\.name)
        XCTAssertEqual(rest, rest.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        XCTAssertEqual(Array(rest.prefix(4)), ["Arcane", "Arcane Crystal", "Arcane Flow", "Catppuccin"])
        XCTAssertEqual(ordered.count, 26)
    }

    func testOortPaletteValuesMatchTheBuiltInFallback() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        let p = try XCTUnwrap(all.first { $0.id == "oort" })
        XCTAssertEqual(p, SelenePalette.fallback)
        XCTAssertEqual(p.name, "Oort")
        XCTAssertEqual(p.mode, .dark)
        XCTAssertEqual(p.focus, 0xFFFFFF)
        XCTAssertEqual(p.onFocus, 0x000000)
        XCTAssertEqual(p.ink, 0xFFFFFF)
        XCTAssertEqual(p.scrim, 0x000000)
        XCTAssertEqual(p.glass, 0x0B0B0B)
        XCTAssertEqual(p.glyph, 0xFFC799)
        XCTAssertEqual(p.success, 0x99FFE4)
        XCTAssertEqual(p.surface, .classic)
        XCTAssertEqual(p.base.kind, .radial)
        XCTAssertEqual(p.base.stops, [.init(color: 0x121212, location: 0), .init(color: 0x000000, location: 1)])
    }

    func testSelenePaletteValues() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        let p = SelenePaletteCatalog.resolve("selene", in: all)
        XCTAssertEqual(p.name, AppIdentity.name)
        XCTAssertEqual(p.focus, 0xFFFFFF)
        XCTAssertEqual(p.onFocus, 0x111111)
        XCTAssertEqual(p.glass, 0x14181F)
        XCTAssertEqual(p.glyph, 0x9CCBFF)
        XCTAssertEqual(p.success, 0x3DDC84)
        XCTAssertEqual(p.base.kind, .radial)
        XCTAssertEqual(p.base.stops, [.init(color: 0x102A5C, location: 0), .init(color: 0x03081A, location: 1)])
    }

    func testBothArcaneSurfacesAreSelectableAndOldPalettesStayClassic() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        XCTAssertEqual(SelenePaletteCatalog.resolve("selene", in: all).surface, .classic)
        XCTAssertEqual(SelenePaletteCatalog.resolve("arcane-crystal", in: all).surface, .arcane)
        XCTAssertEqual(SelenePaletteCatalog.resolve("arcane-flow", in: all).surface, .flow)
        XCTAssertEqual(SelenePaletteCatalog.resolve("white", in: all).surface, .classic)
        var settings = AppSettings()
        settings.colorThemeID = "arcane-flow"
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).colorThemeID, "arcane-flow")
    }

    func testUnknownIdFallsBackToOort() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        XCTAssertEqual(SelenePaletteCatalog.resolve("nope", in: all).id, "oort")
    }

    func testMissingFileUsesFallback() {
        XCTAssertThrowsError(try SelenePaletteCatalog.load(from: URL(fileURLWithPath: "/nonexistent/palettes.json")))
        XCTAssertEqual(SelenePaletteCatalog.resolve("oort", in: []), .fallback)
    }

    func testSettingsDefaultToOortButKeepASavedClassicBlueSelection() throws {
        XCTAssertEqual(AppSettings().colorThemeID, "oort")
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.colorThemeID, "oort")
        let saved = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"colorThemeID":"selene"}"#.utf8))
        XCTAssertEqual(saved.colorThemeID, "selene")
        XCTAssertEqual(SelenePaletteCatalog.resolve(saved.colorThemeID, in: try SelenePaletteCatalog.load(from: paletteURL)).id, "selene")
    }
}
