import Foundation
import OortCore
import OortLibrary

/// Images made in plain Swift, the same bytes on every system: tests need files of a given size, not pictures.
/// A copy of the core tests' `TestImages.swift`: test targets cannot share a file.
enum TestImages {
    /// A real PNG, black, one bit of grey per pixel so a large one stays small; ImageIO decodes it.
    static func png(width: Int, height: Int) -> Data {
        let row = 1 + (width + 7) / 8 // a filter byte (none), then the bits
        let raw = Data(count: row * height)
        var header = Data()
        header.append(big32(width)); header.append(big32(height))
        header.append(contentsOf: [1, 0, 0, 0, 0]) // bit depth 1, greyscale, deflate, no filter, no interlace
        var file = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        file.append(chunk("IHDR", header))
        file.append(chunk("IDAT", zlibStored(raw)))
        file.append(chunk("IEND", Data()))
        return file
    }

    /// The header of a baseline JPEG up to the start of its scan: `ImageHeader` reads its size, nothing decodes it.
    static func jpegHeader(width: Int, height: Int) -> Data {
        var file = Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08])
        file.append(big16(height)); file.append(big16(width))
        file.append(contentsOf: [0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01])
        file.append(contentsOf: [0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00])
        file.append(contentsOf: [0x00, 0x00, 0xFF, 0xD9])
        return file
    }

    /// Longer side as `ImageHeader` reads it.
    static func longerSide(_ data: Data) -> Int? {
        ImageHeader.pixelSize(of: data).map { max($0.width, $0.height) }
    }

    /// zlib framing around stored DEFLATE blocks: valid compressed data without a compressor.
    private static func zlibStored(_ raw: Data) -> Data {
        var out = Data([0x78, 0x01])
        let bytes = [UInt8](raw)
        var start = 0
        repeat {
            let end = min(start + 65_535, bytes.count)
            let length = UInt16(end - start)
            out.append(end == bytes.count ? 1 : 0)
            out.append(contentsOf: [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)])
            out.append(contentsOf: bytes[start..<end])
            start = end
        } while start < bytes.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes { a = (a + UInt32(byte)) % 65_521; b = (b + a) % 65_521 }
        out.append(big32(Int(b << 16 | a)))
        return out
    }

    private static func chunk(_ type: String, _ body: Data) -> Data {
        let typed = Data(type.utf8) + body
        return big32(body.count) + typed + big32(Int(CRC32.checksum(typed)))
    }

    private static func big32(_ value: Int) -> Data {
        Data([UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
    private static func big16(_ value: Int) -> Data { Data([UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]) }
}

/// A resizer that decodes nothing: the size `ImageHeader` reads, scaled down to `maxPixelSize` on its longer side as
/// ImageIO's thumbnail does (never up), written as a `TestImages` PNG or JPEG header. Not an image: nil, as on a Mac.
/// The real one is checked on a Mac (`ImageIOResizerTests`).
struct FakeImageResizer: ImageResizer {
    func resized(_ data: Data, maxPixelSize: CGFloat, png: Bool) -> Data? {
        guard let (width, height) = ImageHeader.pixelSize(of: data) else { return nil }
        let scale = min(1, Double(maxPixelSize) / Double(max(width, height)))
        let w = max(1, Int((Double(width) * scale).rounded())), h = max(1, Int((Double(height) * scale).rounded()))
        return png ? TestImages.png(width: w, height: h) : TestImages.jpegHeader(width: w, height: h)
    }
}
