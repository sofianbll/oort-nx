import XCTest
@testable import NXLibraryCore

final class DockProgressValueTests: XCTestCase {
    func testNothingKnownHidesTheBar() {
        XCTAssertNil(DockProgressValue.percent([]))
        XCTAssertNil(DockProgressValue.percent([nil, .nan]))
    }

    func testMeanOfKnownWorksInWholePercents() {
        XCTAssertEqual(DockProgressValue.percent([0.5, nil]), 50)
        XCTAssertEqual(DockProgressValue.percent([0, 1]), 50)
        XCTAssertEqual(DockProgressValue.percent([0.999]), 99)
        XCTAssertEqual(DockProgressValue.percent([-1, 2]), 50)
        XCTAssertEqual(DockProgressValue.percent([1]), 100)
    }
}
