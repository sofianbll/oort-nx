import CryptoKit
import XCTest
@testable import NXLibraryCore

/// The portable SHA-256 must give the digests the Mac already stored for profile PINs.
final class PortableDigestTests: XCTestCase {
    func testMatchesCryptoKitForManyLengths() {
        var seed: UInt64 = 99
        for length in Array(0...140) + [1_000, 4_097] {
            let bytes = (0..<length).map { _ -> UInt8 in seed = seed &* 6_364_136_223_846_793_005 &+ 1; return UInt8(truncatingIfNeeded: seed >> 33) }
            XCTAssertEqual(PortableSHA256.hash(Data(bytes)), Data(SHA256.hash(data: Data(bytes))), "\(length) bytes")
        }
    }

    func testAStoredProfilePINStillMatches() throws {
        let look = LocalProfile.Look(AppSettings())
        var profile = LocalProfile(name: "A", look: look)
        XCTAssertTrue(profile.setPIN("2468"))
        // A document written by the CryptoKit build stores SHA-256 of "<uuid><pin>".
        let stored = Data(SHA256.hash(data: Data((profile.id.uuidString + "2468").utf8)))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        json["pinDigest"] = stored.base64EncodedString()
        let reread = try JSONDecoder().decode(LocalProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(reread.matchesPIN("2468"))
        XCTAssertFalse(reread.matchesPIN("2469"))
        XCTAssertEqual(reread, profile)
    }
}
