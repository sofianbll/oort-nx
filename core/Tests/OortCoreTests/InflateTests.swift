import XCTest
import OortCore

/// The ZIP decoder of sound packs (untrusted files): streams made by zlib, and every way a stream can lie.
final class InflateTests: XCTestCase {
    private func text() -> Data {
        var seed: UInt32 = 7
        let letters = Array("abcdefgh".utf8)
        var bytes = Array(String(repeating: "Oort NX plays the sound of the Sun. ", count: 40).utf8)
        for _ in 0..<3000 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes.append(letters[Int(seed >> 29)])
        }
        return Data(bytes)
    }

    /// zlib 9, raw: one dynamic Huffman block.
    private let dynamic = Data(base64Encoded: [
        "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",
    ].joined())!

    func testTheCRCOfTheStandardCheck() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }

    func testAFixedHuffmanStream() throws {
        let fixed = Data(base64Encoded: "y0jNyclXyECQAA==")!
        XCTAssertEqual(try Inflate.raw(fixed, size: 17), Data("hello hello hello".utf8))
    }

    func testADynamicHuffmanStream() throws {
        XCTAssertEqual(try Inflate.raw(dynamic, size: text().count), text())
    }

    func testAStoredBlock() throws {
        let body = Data((0..<300).map { UInt8($0 & 0xff) })
        var stream = Data([0x01, 0x2c, 0x01, 0xd3, 0xfe])
        stream.append(body)
        XCTAssertEqual(try Inflate.raw(stream, size: 300), body)
        stream[3] ^= 1
        XCTAssertThrowsError(try Inflate.raw(stream, size: 300)) { XCTAssertEqual($0 as? Inflate.Failure, .malformed) }
    }

    func testAStreamThatLiesIsRefused() {
        let size = text().count
        XCTAssertThrowsError(try Inflate.raw(dynamic.prefix(dynamic.count - 1), size: size)) {
            XCTAssertEqual($0 as? Inflate.Failure, .truncated)
        }
        XCTAssertThrowsError(try Inflate.raw(dynamic, size: size - 1)) { XCTAssertEqual($0 as? Inflate.Failure, .wrongSize) }
        XCTAssertThrowsError(try Inflate.raw(dynamic, size: size + 1)) { XCTAssertEqual($0 as? Inflate.Failure, .wrongSize) }
        XCTAssertThrowsError(try Inflate.raw(dynamic + Data([0]), size: size)) {
            XCTAssertEqual($0 as? Inflate.Failure, .trailingData)
        }
        XCTAssertThrowsError(try Inflate.raw(Data([0x07]), size: 1)) { XCTAssertEqual($0 as? Inflate.Failure, .malformed) }
        XCTAssertThrowsError(try Inflate.raw(Data(), size: 0)) { XCTAssertEqual($0 as? Inflate.Failure, .truncated) }
    }
}
