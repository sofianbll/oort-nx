import XCTest
import OortCore

final class VersionNumberTests: XCTestCase {
    func testVersionCompareIsNumeric() {
        XCTAssertTrue(VersionNumber.isOlder("10.0.401", than: "10.0.403"))
        XCTAssertTrue(VersionNumber.isOlder("27.1", than: "27.10"))
        XCTAssertTrue(VersionNumber.isOlder("27", than: "27.0.1"))
        XCTAssertFalse(VersionNumber.isOlder("27.1", than: "27.1.0"))
        XCTAssertFalse(VersionNumber.isOlder("10.0.403", than: "10.0.401"))
        XCTAssertFalse(VersionNumber.isOlder("26.4", than: "26.4"))
        XCTAssertTrue(VersionNumber.isOlder("Xcode 27.1", than: "27.2"))
    }
}
