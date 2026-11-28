import XCTest
@testable import OortMac

/// The verifier the app gives the rclone installer accepts a program Apple signed and refuses any other bytes.
final class MacCodeSignatureVerifierTests: XCTestCase {
    func testASignedSystemProgramPassesAndUnsignedBytesDoNot() throws {
        let verifier = MacCodeSignatureVerifier()
        XCTAssertTrue(verifier.hasValidSignature(URL(fileURLWithPath: "/usr/bin/true")))
        let unsigned = FileManager.default.temporaryDirectory.appendingPathComponent("unsigned-\(UUID().uuidString)")
        try Data("not a signed executable".utf8).write(to: unsigned)
        defer { try? FileManager.default.removeItem(at: unsigned) }
        XCTAssertFalse(verifier.hasValidSignature(unsigned))
    }
}
