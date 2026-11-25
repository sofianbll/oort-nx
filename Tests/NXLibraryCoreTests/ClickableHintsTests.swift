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

    func testTheViewersArrowsTakeAClickInBothHosts() throws {
        XCTAssertTrue(try Self.source("Components/ScreenshotViewer.swift").contains("leftInset: 18, press: onAction)"))
        for path in ["Spotlight/SpotlightView+Stage.swift", "Detail/GameDetailView.swift"] {
            XCTAssertTrue(try Self.source(path).contains("onClose: closeViewer, onAction: handleViewer)"), path)
        }
    }

    /// Moving a tile: the click layer covers the stage, so any click drops and none starts a game.
    func testAClickPutsALiftedTileDown() throws {
        let stage = try Self.source("Spotlight/SpotlightView+Stage.swift")
        let layer = try XCTUnwrap(stage.range(of: "if state.isLifted {\n                // A click anywhere"))
        let menu = try XCTUnwrap(stage.range(of: "if let menu = cardMenu {"))
        XCTAssertTrue(stage[layer.lowerBound..<menu.lowerBound].contains(".onTapGesture { handle(.confirm) }"))
        let hints = try Self.source("Spotlight/SpotlightView+Hints.swift")
        XCTAssertTrue(hints.contains("HintItem(.a, L10n.text(\"Drop\")), HintItem(.b, L10n.text(\"Cancel\"))"))
    }

    /// A right click on any tile or card opens what + opens for it.
    func testARightClickOpensTheOptionsOnBothHomeScreens() throws {
        for path in ["Spotlight/SpotlightView+Stage.swift", "Collection/CollectionView.swift"] {
            let body = try XCTUnwrap(try Self.source(path).components(separatedBy: "onOptions: {").last?.prefix(420))
            XCTAssertTrue(body.contains("handle(.contextAction)"), path)
        }
        XCTAssertTrue(try Self.source("OortUI/OortGameTile.swift").contains(".oortSecondaryClick(options)"))
    }

    func testSearchOpensFromAGamesPageToo() throws {
        XCTAssertTrue(try Self.source("Detail/GameDetailView+Input.swift").contains("case .browseSearch, .search:"))
        XCTAssertTrue(try Self.source("Shell/AppShellView+Input.swift").contains("isHomeRoute || router.route.isDetail"))
    }

    func testTheControlCenterSaysWhatBackDoesAndItsShortcutCloses() throws {
        XCTAssertTrue(try Self.source("Shell/MenuOverlayView.swift").contains("HintItem(.b, submenuOpen ? \"Back\" : \"Close\")"))
        XCTAssertTrue(try Self.source("Shell/AppShellView.swift").contains("if router.isMenuPresented { router.closeMenu() } else"))
    }
}
