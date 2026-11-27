import XCTest
@testable import OortLibrary

/// Every palette Oort offers keeps its text and its focus readable.
final class PaletteContrastTests: XCTestCase {
    private func ratio(_ a: UInt32, _ b: UInt32) -> Double { SelenePalette.contrast(a, b) }

    func testEveryPaletteKeepsTextAndFocusReadable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let palettes = try SelenePaletteCatalog.load(from: root.appendingPathComponent("design/Selene/palettes.json"))
        XCTAssertGreaterThan(palettes.count, 20)
        for palette in palettes {
            XCTAssertGreaterThanOrEqual(ratio(palette.ink, palette.glass), 4.5, "\(palette.id) ink on glass")
            XCTAssertGreaterThanOrEqual(ratio(palette.ink, palette.scrim), 4.5, "\(palette.id) ink on scrim")
            XCTAssertGreaterThanOrEqual(ratio(palette.onFocus, palette.focus), 4.5, "\(palette.id) text on focus")
            XCTAssertGreaterThanOrEqual(ratio(palette.focus, palette.glass), 3, "\(palette.id) focus on glass")
            XCTAssertGreaterThanOrEqual(ratio(palette.glyph, palette.glass), 3, "\(palette.id) glyph on glass")
        }
    }

    func testAReadablePaletteIsLeftAsItIs() {
        XCTAssertEqual(SelenePalette.fallback.readable, SelenePalette.fallback)
        XCTAssertEqual(SelenePalette.contrast(0, 0xFFFFFF), 21, accuracy: 0.01)
        var low = SelenePalette.fallback
        low.onFocus = 0xDDDDDD
        XCTAssertGreaterThanOrEqual(SelenePalette.contrast(low.readable.onFocus, low.readable.focus), 4.5)
        XCTAssertEqual(low.readable.ink, low.ink)
    }
}
