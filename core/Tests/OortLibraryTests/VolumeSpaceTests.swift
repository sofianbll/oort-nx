import XCTest
@testable import NXLibraryCore

final class VolumeSpaceTests: XCTestCase {
    func testZeroImportantUsageFallsBackToThePlainFigure() {
        XCTAssertEqual(VolumeSpace.best(important: 0, plain: 41_791_488), 41_791_488)
        XCTAssertEqual(VolumeSpace.best(important: nil, plain: 5), 5)
        XCTAssertEqual(VolumeSpace.best(important: 64, plain: 43), 64, "APFS keeps counting what it can purge")
        XCTAssertEqual(VolumeSpace.best(important: 0, plain: 0), 0, "a full drive is full")
        XCTAssertNil(VolumeSpace.best(important: nil, plain: nil))
    }

    func testAFolderNotMadeYetIsOnItsParentsVolume() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID())/a/b")
        XCTAssertGreaterThan(try XCTUnwrap(VolumeSpace.free(at: missing)), 0)
    }

    /// OORT_EXFAT=<a mounted exFAT or FAT32 folder> checks a real drive.
    func testARealDriveThatIsNotAPFS() throws {
        guard let path = ProcessInfo.processInfo.environment["OORT_EXFAT"] else { throw XCTSkip("no drive given") }
        let url = URL(fileURLWithPath: path)
        XCTAssertEqual(try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, 0)
        XCTAssertGreaterThan(try XCTUnwrap(VolumeSpace.free(at: url)), 1_000_000)
    }
}
