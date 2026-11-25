import XCTest

/// Screens whose hints were only told, never pressed: the mouse could not reach Details, Options or a card's menu.
final class ClickableHintsTests: XCTestCase {
    static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/NXLibrary/Views/" + path), encoding: .utf8)
    }

    func testTheHomeScreensPressTheirHints() throws {
        for path in ["Spotlight/SpotlightView.swift", "Collection/CollectionView.swift"] {
            XCTAssertTrue(try Self.source(path).contains("press: { handle($0) }"), path)
        }
        XCTAssertTrue(try Self.source("Components/SeleneHomeChrome.swift").contains("rightReserve: rightReserve, press: press)"))
    }
}
