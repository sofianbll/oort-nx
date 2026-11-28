import ImageIO
import OortLibrary
import UniformTypeIdentifiers
import XCTest

/// The core's `ImageHeader` against ImageIO, which it replaced: the same size for every whole file, and on a file cut
/// anywhere, never a size where ImageIO has none. Files: what ImageIO writes (PNG, JPEG baseline, progressive and
/// rotated by EXIF, GIF still and animated, ICO with several entries) and every PNG and WebP of the repository.
final class ImageHeaderAgainstImageIOTests: XCTestCase {
    private func imageIO(_ data: Data) -> [Int]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
        return [width, height]
    }

    private func header(_ data: Data) -> [Int]? { ImageHeader.pixelSize(of: data).map { [$0.width, $0.height] } }

    private func image(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.7))
        context.fill(CGRect(x: 0, y: 0, width: width / 2 + 1, height: height))
        return context.makeImage()!
    }

    private func written(_ type: UTType, _ frames: [(CGImage, [CFString: Any])]) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, frames.count, nil)!
        for (image, properties) in frames { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func corpus() throws -> [(String, Data)] {
        var files: [(String, Data)] = []
        for (width, height) in [(1, 1), (7, 300), (460, 215), (1920, 620), (513, 512)] {
            let name = "\(width)x\(height)"
            files.append(("png \(name)", written(.png, [(image(width, height), [:])])))
            files.append(("jpeg \(name)", written(.jpeg, [(image(width, height), [kCGImageDestinationLossyCompressionQuality: 0.8])])))
            files.append(("progressive \(name)", written(.jpeg, [(image(width, height),
                [kCGImagePropertyJFIFDictionary: [kCGImagePropertyJFIFIsProgressive: true]])])))
            files.append(("rotated \(name)", written(.jpeg, [(image(width, height), [kCGImagePropertyOrientation: 6])])))
            files.append(("gif \(name)", written(.gif, [(image(width, height), [:])])))
        }
        files.append(("animated gif", written(.gif, [(image(64, 48), [:]), (image(20, 10), [:])])))
        files.append(("ico 16, 256, 48", written(.ico, [(image(16, 16), [:]), (image(256, 256), [:]), (image(48, 48), [:])])))
        files.append(("ico 256, 32", written(.ico, [(image(256, 256), [:]), (image(32, 32), [:])])))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../..").standardized
        let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent("docs"), includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard ["png", "webp"].contains(url.pathExtension.lowercased()) else { continue }
            files.append((url.lastPathComponent, try Data(contentsOf: url)))
        }
        XCTAssertGreaterThan(files.filter { $0.0.hasSuffix(".webp") }.count, 100, "the repository's WebP files")
        return files
    }

    func testTheSameSizeAsImageIOAndNeverOneImageIOLacks() throws {
        for (name, data) in try corpus() {
            XCTAssertNotNil(imageIO(data), name)
            XCTAssertEqual(header(data), imageIO(data), name)
            guard data.count < 20_000 else { continue }
            for length in stride(from: 0, to: data.count, by: max(1, data.count / 200)) {
                let cut = data.prefix(length)
                if let size = header(cut) { XCTAssertEqual(size, imageIO(cut), "\(name) cut at \(length)") }
            }
        }
    }
}
