import Crypto
import XCTest

/// The digests the core writes and checks (downloads, checkpoints, PIN) are the same on every system: NIST vectors.
final class SHA256DigestTests: XCTestCase {
    private func hex(_ data: some Sequence<UInt8>) -> String { data.map { String(format: "%02x", $0) }.joined() }

    func testNISTShortMessages() {
        XCTAssertEqual(hex(SHA256.hash(data: Data())), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(hex(SHA256.hash(data: Data("abc".utf8))),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(hex(SHA256.hash(data: Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testIncrementalHashingOfAMillionAs() {
        var hasher = SHA256()
        let chunk = Data(repeating: UInt8(ascii: "a"), count: 1000)
        for _ in 0..<1000 { hasher.update(data: chunk) }
        XCTAssertEqual(hex(hasher.finalize()), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}
