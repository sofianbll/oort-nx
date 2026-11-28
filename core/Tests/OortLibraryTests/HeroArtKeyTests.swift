import XCTest
@testable import OortLibrary

final class HeroArtKeyTests: XCTestCase {
    func testArtIsRecognisedWhateverItsSource() {
        let id = UUID(), other = UUID()
        for source in ["hero|\(id)|https://www.nintendo.com/eu/media/images/a.jpg|3", "s4", ""] {
            let key = HeroArtKey.make(id, source) + "123"
            XCTAssertTrue(HeroArtKey.belongs(key, to: id), source)
            XCTAssertFalse(HeroArtKey.belongs(key, to: other), source)
        }
        XCTAssertFalse(HeroArtKey.belongs("none", to: id))
        XCTAssertFalse(HeroArtKey.belongs("hero|\(id)|", to: id))
    }
}
