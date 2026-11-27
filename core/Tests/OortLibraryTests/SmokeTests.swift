import XCTest
@testable import OortLibrary

final class SmokeTests: XCTestCase {
    func testCoreVersion() {
        XCTAssertEqual(OortLibrary.version, "0.1.0")
    }
}
