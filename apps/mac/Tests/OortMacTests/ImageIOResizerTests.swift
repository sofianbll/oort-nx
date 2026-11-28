import AppKit
import XCTest
@testable import OortLibrary
@testable import OortMac

/// The Mac's resizer decodes real pixels: the limits each artwork kind asks for, PNG transparency, JPEG for photos.
/// The core's tests check the same requests with a fake that reads only headers (`FakeImageResizer`).
final class ImageIOResizerTests: XCTestCase {
    override func invokeTest() {
        PlatformServices.$scoped.withValue(.init(imageResizer: ImageIOResizer())) { super.invokeTest() }
    }

    /// A red image, or for `half` red on its left half and transparent on the right.
    private func image(width: Int, height: Int, half: Bool = false, png: Bool = false) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: half ? width / 2 : width, height: height))
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        return png ? rep.representation(using: .png, properties: [:])!
                   : rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
    }

    private func rep(_ data: Data?) throws -> NSBitmapImageRep {
        try XCTUnwrap(data.flatMap(NSBitmapImageRep.init(data:)))
    }

    /// From `ArtworkStoreTests.testDownsampleLimitsHeroAndCover`, which read the files with NSImage.
    func testDownsampleLimitsHeroAndCover() throws {
        let photo = image(width: 4000, height: 3000)
        let hero = try rep(ArtworkStore.downsample(photo, maxPixelSize: ArtworkKind.hero.maxPixelSize))
        let cover = try rep(ArtworkStore.downsample(photo, maxPixelSize: ArtworkKind.boxart.maxPixelSize))
        XCTAssertEqual(max(hero.pixelsWide, hero.pixelsHigh), 2560)
        XCTAssertEqual(max(cover.pixelsWide, cover.pixelsHigh), 1400)
        XCTAssertEqual(hero.pixelsWide * 3, hero.pixelsHigh * 4, "the shape is kept")
    }

    /// From `ArtworkStoreTests.testSquareMaxPixelSize512`.
    func testSquareMaxPixelSize512() throws {
        let square = try rep(ArtworkStore.downsample(image(width: 1024, height: 1024),
                                                     maxPixelSize: ArtworkKind.square.maxPixelSize, png: true))
        XCTAssertEqual(max(square.pixelsWide, square.pixelsHigh), 512)
    }

    /// From `ArtworkStoreTests.testSquareKeepsAlpha`.
    func testSquareKeepsAlpha() throws {
        let png = ArtworkStore.downsample(image(width: 64, height: 64, half: true, png: true),
                                          maxPixelSize: ArtworkKind.square.maxPixelSize, png: true)
        XCTAssertEqual(png?.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
        let square = try rep(png)
        XCTAssertTrue(square.hasAlpha)
        XCTAssertEqual(square.colorAt(x: 60, y: 30)?.alphaComponent ?? 1, 0, accuracy: 0.01)
    }

    /// From `ArtworkStoreTests.testScreenshotCachePath`, which read the cached screenshot's pixels.
    func testScreenshotIsAJPEGOf1600Pixels() throws {
        let jpeg = ArtworkStore.downsample(image(width: 3200, height: 1800), maxPixelSize: 1600)
        XCTAssertEqual(jpeg?.prefix(2), Data([0xFF, 0xD8]))
        let shot = try rep(jpeg)
        XCTAssertEqual(max(shot.pixelsWide, shot.pixelsHigh), 1600)
    }

    /// Bytes that only look like an image are refused, as the fake refuses what `ImageHeader` cannot read.
    func testWhatIsNotAnImageIsRefused() {
        XCTAssertNil(ArtworkStore.downsample(Data("not an image".utf8), maxPixelSize: 512))
        XCTAssertNil(ArtworkStore.downsample(Data(image(width: 64, height: 64).prefix(20)), maxPixelSize: 512))
    }
}
