import XCTest
@testable import OortLibrary

/// The size an image declares, on every system: real files (ImageIO's PNG and GIF, cwebp's four kinds of WebP), a
/// JPEG and two icons written by hand, and the cut downloads and lies that must give no size.
/// `ImageHeaderAgainstImageIOTests` compares the same reading with ImageIO on a Mac.
final class ImageHeaderTests: XCTestCase {
    private static func file(_ base64: String) -> Data { Data(base64Encoded: base64)! }
    private let png = file([
        "iVBORw0KGgoAAAANSUhEUgAAAAcAAAEsCAYAAAAPTqmSAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAAB",
        "AAAAGgAAAAAAAqACAAQAAAABAAAAB6ADAAQAAAABAAABLAAAAACP0zDcAAAAfUlEQVRoBe3WUQmAMABFUWeclTCBUUxjFBOs",
        "hHkmjD38ECxw/FHx73EPs2znfS2vqx11n6/rfPi6+/isYgQjDBxKUIISxgJKUIISsgAOOCQG/wk44IBDFsABh8TgdMABBxyy",
        "AA44JAanAw444JAFcMAhMTgdcMABhyzwx6EDyz0GWEFPa5kAAAAASUVORK5CYII=",
    ].joined())
    /// Two frames, 64 × 48 then 20 × 10: the canvas counts.
    private let gif = file([
        "R0lGODdhQAAwAKIAAAAAAC6L0UCR1j+T1v///wAAAAAAAAAAACH5BAkAAAUALAAAAABAADAAAAOGOLrc/q3ISau9E+rtsP8U",
        "J25giY1oZ65Z6g5s/LoxO6f1eqO5uY+90k8UBA05xc+RlDwtIU3nUxWtTB9Vy5WalWwj3dZXERaPy94xGa1el9swdhtdgNPt",
        "cvV9nj/3v3t6f1uBfm98h4KJhmF4i4CDV4WQj4SRU5OWlZKXT5mcm5idS5+iZQkAIfkECQAABQAsAAAAACMAMAAAAyo4utz+",
        "MMpJq7046827/2AojmRpnmiqrmzrvnAsz3Rt33iu73zv/8DgKAEAOw==",
    ].joined())
    private let lossy = file([
        "UklGRlwAAABXRUJQVlA4IFAAAACQBACdASoHACwBPm02m0mkIyKhIagAgA2JQAXf+AITeJjWH5zGsPzmNYfnAAAA/vlMH/6a",
        "4/+0I/7NCP+13hUxyT+H/urANehjpmt8AAAAAA==",
    ].joined())
    private let lossless = file([
        "UklGRiYAAABXRUJQVlA4TBkAAAAvBsBKEA8wk/Mz1jMb8AAKBCF/62ZE/0MVAA==",
    ].joined())
    private let alpha = file([
        "UklGRtIAAABXRUJQVlA4WAoAAAAYAAAABgAAKwEAQUxQSBEAAAARDzCzERECKBCE/K2bEf0PVQBWUDggWgAAADAFAJ0BKgcA",
        "LAE+bTabSaQjIqEhqACADYliALwm9rQFX/7gAANyuta1rWta1rWta1AAAJv8jwBlfyYWtG/gKE5P970QSWPb37evugWZvGlu",
        "6t3Vu6t3QQAAAEVYSUY4AAAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAB6ADAAQAAAABAAABLAAA",
        "AAA=",
    ].joined())
    /// gif2webp of the GIF above: an extended, animated file.
    private let animated = file([
        "UklGRpAAAABXRUJQVlA4WAoAAAASAAAAPwAALwAAQU5JTQYAAAAAAAD/AQBBTk1GMAAAAAAAAAAAACAAAC8AAGQAAAJWUDhM",
        "FwAAAC8gwAsAB9DJ/tS6/wEgIfw/r0b0P3UBAEFOTUYsAAAAEAAAAAAAAgAALwAAZAAAAFZQOEwTAAAALwLACxAPMJPzM9bz",
        "H/CoQUT/AwA=",
    ].joined())

    /// SOI, an APP0, a baseline frame of 300 × 7, the scan header, two bytes of scan, EOI.
    private func jpeg(frame marker: UInt8 = 0xC0) -> Data {
        var bytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10] + Array("JFIF".utf8) + [0, 1, 1, 0, 0, 1, 0, 1, 0, 0]
        bytes += [0xFF, marker, 0x00, 0x11, 0x08, 0x00, 0x07, 0x01, 0x2C, 0x03, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]
        bytes += [0xFF, 0xDA, 0x00, 0x0C, 0x03, 1, 0, 2, 0x11, 3, 0x11, 0x00, 0x3F, 0x00, 0x12, 0x34, 0xFF, 0xD9]
        return Data(bytes)
    }

    /// A directory of one entry of `width` × `height` (0 means 256) holding `image`.
    private func ico(width: UInt8, height: UInt8, image: Data) -> Data {
        func le(_ value: Int, _ count: Int) -> [UInt8] { (0..<count).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
        return Data([0, 0, 1, 0, 1, 0, width, height, 0, 0, 1, 0, 32, 0] + le(image.count, 4) + le(22, 4)) + image
    }

    private func size(_ data: Data) -> [Int]? { ImageHeader.pixelSize(of: data).map { [$0.width, $0.height] } }

    func testEveryFormatGivesItsDeclaredSize() {
        XCTAssertEqual(size(png), [7, 300])
        XCTAssertEqual(size(gif), [64, 48])
        XCTAssertEqual(size(lossy), [7, 300])
        XCTAssertEqual(size(lossless), [7, 300])
        XCTAssertEqual(size(alpha), [7, 300])
        XCTAssertEqual(size(animated), [64, 48])
        XCTAssertEqual(size(jpeg()), [300, 7])
        XCTAssertEqual(size(jpeg(frame: 0xC2)), [300, 7], "progressive")
        XCTAssertEqual(size(ico(width: 0, height: 0, image: Data(repeating: 1, count: 40))), [256, 256])
        XCTAssertEqual(size(ico(width: 48, height: 32, image: Data(repeating: 1, count: 40))), [48, 32])
        XCTAssertEqual(size(ico(width: 0, height: 0, image: png)), [7, 300], "a PNG entry says its own size")
    }

    func testTheKindsOfWebPAreTheOnesCwebpWrites() {
        XCTAssertEqual(String(decoding: lossy[12..<16], as: UTF8.self), "VP8 ")
        XCTAssertEqual(String(decoding: lossless[12..<16], as: UTF8.self), "VP8L")
        XCTAssertEqual(String(decoding: alpha[12..<16], as: UTF8.self), "VP8X")
        XCTAssertEqual(String(decoding: animated[12..<16], as: UTF8.self), "VP8X")
    }

    /// A download cut before the image data gives no size: PNG before IDAT, JPEG before its scan has begun, GIF
    /// before the end of its first frame, WebP or an icon entry not whole.
    func testACutFileGivesNoSize() {
        let jpeg = jpeg()
        let idat = png.range(of: Data("IDAT".utf8))!.lowerBound
        let scan = jpeg.range(of: Data([0xFF, 0xDA]))!.lowerBound
        let cuts: [(String, Data, Int)] = [("PNG", png, idat + 3), ("JPEG", jpeg, scan + 15), ("GIF", gif, 191),
                                          ("WebP", lossy, lossy.count - 1), ("WebP", alpha, alpha.count - 1),
                                          ("ICO", ico(width: 16, height: 16, image: Data(repeating: 1, count: 40)), 61)]
        for (format, file, longest) in cuts {
            for length in 0...longest { XCTAssertNil(size(file.prefix(length)), "\(format) cut at \(length)") }
        }
        XCTAssertEqual(size(png.prefix(idat + 4)), [7, 300], "the IDAT chunk has begun")
        XCTAssertEqual(size(jpeg.prefix(scan + 16)), [300, 7], "the scan header and its first two bytes")
    }

    func testWhatIsNotAnImageOrSaysNothingGivesNoSize() {
        XCTAssertNil(size(Data()))
        XCTAssertNil(size(Data("<html>not found</html>".utf8)))
        var zero = png
        zero.replaceSubrange(16..<20, with: [0, 0, 0, 0])
        XCTAssertNil(size(zero), "a width of 0")
        var flat = jpeg()
        flat.replaceSubrange(25..<27, with: [0, 0])
        XCTAssertNil(size(flat), "a JPEG height of 0 (defined later by DNL)")
        XCTAssertNil(size(Data([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xD9])), "a scan before any frame")
        XCTAssertNil(size(ico(width: 16, height: 16, image: Data())), "an empty icon entry")
    }
}
