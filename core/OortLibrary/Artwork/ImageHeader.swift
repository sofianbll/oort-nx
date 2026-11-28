import Foundation

/// The pixel size an image file declares, read from its header in plain Swift: the formats artwork sources serve
/// (PNG, JPEG, WebP, GIF and the ICO icons of SteamGridDB). Nothing is decoded; resizing is `ImageResizer`'s.
/// A size is given only when the file reaches its image data (PNG IDAT, JPEG scan begun, first GIF frame, whole WebP), so a
/// download cut after its header is refused. On a Mac it gives ImageIO's `kCGImagePropertyPixelWidth` and `…Height`
/// of the first image, and never a size where ImageIO has none (`ImageHeaderAgainstImageIOTests`).
public enum ImageHeader {
    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data)
        let size: (Int, Int)?
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { size = png(bytes) }
        else if bytes.starts(with: [0xFF, 0xD8]) { size = jpeg(bytes) }
        else if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) { size = gif(bytes) }
        else if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8..<12]) == Array("WEBP".utf8) {
            size = webp(bytes)
        } else if bytes.starts(with: [0, 0, 1, 0]) { size = ico(bytes) }
        else { size = nil }
        guard let size, size.0 > 0, size.1 > 0 else { return nil }
        return (size.0, size.1)
    }

    private static func big32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }
    private static func big16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
    private static func little16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    private static func little24(_ b: [UInt8], _ i: Int) -> Int { little16(b, i) | Int(b[i + 2]) << 16 }

    /// The first chunk is IHDR: width and height, big-endian. Then chunks up to the first IDAT.
    private static func png(_ b: [UInt8]) -> (Int, Int)? {
        guard b.count >= 33, Array(b[12..<16]) == Array("IHDR".utf8), big32(b, 8) == 13 else { return nil }
        var i = 33
        while i + 8 <= b.count {
            if Array(b[(i + 4)..<(i + 8)]) == Array("IDAT".utf8) { return (big32(b, 16), big32(b, 20)) }
            i += 12 + big32(b, i)
        }
        return nil
    }

    /// The first start-of-frame segment, then segments up to the scan; the whole file may be needed (large EXIF).
    private static func jpeg(_ b: [UInt8]) -> (Int, Int)? {
        let frames: Set<UInt8> = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]
        var i = 2
        var size: (Int, Int)?
        while i + 3 < b.count {
            guard b[i] == 0xFF else { return nil }
            let marker = b[i + 1]
            if marker == 0xFF { i += 1; continue }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            if marker == 0xD9 { return nil }
            // The scan header, whole, and the first two bytes of the scan: where ImageIO starts to give a size.
            if marker == 0xDA { return i + 4 + big16(b, i + 2) <= b.count ? size : nil }
            let length = big16(b, i + 2)
            guard length >= 2 else { return nil }
            if frames.contains(marker), size == nil {
                guard i + 8 < b.count else { return nil }
                size = (big16(b, i + 7), big16(b, i + 5))
            }
            i += 2 + length
        }
        return nil
    }

    /// The logical screen, the canvas every frame is drawn on; the file must hold its whole first frame.
    private static func gif(_ b: [UInt8]) -> (Int, Int)? {
        guard b.count >= 13 else { return nil }
        var i = 13 + (b[10] & 0x80 != 0 ? 3 << (Int(b[10] & 0x07) + 1) : 0)
        while i < b.count {
            switch b[i] {
            case 0x2C:
                // The first frame, whole: its descriptor, its own colours, then its data sub-blocks to the empty one.
                guard i + 10 <= b.count else { return nil }
                i += 10 + (b[i + 9] & 0x80 != 0 ? 3 << (Int(b[i + 9] & 0x07) + 1) : 0) + 1
                while i < b.count, b[i] != 0 { i += 1 + Int(b[i]) }
                return i < b.count ? (little16(b, 6), little16(b, 8)) : nil
            case 0x21:
                // An extension: its label, then sub-blocks until an empty one.
                i += 2
                while i < b.count, b[i] != 0 { i += 1 + Int(b[i]) }
                i += 1
            default: return nil
            }
        }
        return nil
    }

    /// The canvas of an extended file (VP8X), or the frame of a simple lossy (VP8) or lossless (VP8L) one.
    private static func webp(_ b: [UInt8]) -> (Int, Int)? {
        // ImageIO reads a WebP only whole: the RIFF size must be there.
        guard b.count >= 30, Int(b[4]) | Int(b[5]) << 8 | Int(b[6]) << 16 | Int(b[7]) << 24 <= b.count - 8 else { return nil }
        switch String(decoding: b[12..<16], as: UTF8.self) {
        case "VP8X":
            return (little24(b, 24) + 1, little24(b, 27) + 1)
        case "VP8 ":
            guard b[23] == 0x9D, b[24] == 0x01, b[25] == 0x2A else { return nil }
            return (little16(b, 26) & 0x3FFF, little16(b, 28) & 0x3FFF)
        case "VP8L":
            guard b[20] == 0x2F else { return nil }
            let bits = Int(b[21]) | Int(b[22]) << 8 | Int(b[23]) << 16 | Int(b[24]) << 24
            return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
        default:
            return nil
        }
    }

    /// The first entry of the directory, whose bytes must all be there; 0 means 256. An entry may hold a PNG, whose
    /// own header then decides.
    private static func ico(_ b: [UInt8]) -> (Int, Int)? {
        guard b.count >= 22, little16(b, 4) >= 1 else { return nil }
        let width = b[6] == 0 ? 256 : Int(b[6]), height = b[7] == 0 ? 256 : Int(b[7])
        let size = little16(b, 14) | little16(b, 16) << 16, offset = little16(b, 18) | little16(b, 20) << 16
        guard offset >= 22, size > 0, offset + size <= b.count else { return nil }
        let image = Array(b[offset..<(offset + size)])
        if image.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return png(image) }
        return (width, height)
    }
}
