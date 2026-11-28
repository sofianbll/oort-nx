import OortLibrary
import XCTest

final class SeleneOverlayStyleTests: XCTestCase {
    func testOverlayStylesRetainDifferentVeilsAndBlur() {
        XCTAssertEqual(SeleneOverlayStyle.menu.veilOpacity, 0.55)
        XCTAssertEqual(SeleneOverlayStyle.deep.veilOpacity, 0.65)
        XCTAssertEqual(SeleneOverlayStyle.options.backdropBlur, 10)
        XCTAssertEqual(SeleneOverlayStyle.deep.backdropBlur, 40)
        XCTAssertEqual(SeleneOverlayStyle.search.backdropBlur, 0)
    }
}
