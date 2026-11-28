import AVFoundation
import XCTest
import OortLibrary

/// The Arcane tier's crystal, read with AVFoundation as the Mac plays it. The core checks that only Arcane has a
/// video (`AchievementTierTests.testOnlyArcaneHasALoopingAlphaVideo`).
final class AchievementVideoTests: XCTestCase {
    func testArcaneVideoIsALoopingAlphaHEVC() async throws {
        let url = try XCTUnwrap(AchievementTier.arcane.videoURL)
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let formats = try await track.load(.formatDescriptions)
        let format = try XCTUnwrap(formats.first)
        XCTAssertEqual(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel) as? Bool, true)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_HEVC) // hvc1: decoded by the media engine
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 384, height: 384))
        let seconds = try await asset.load(.duration).seconds
        XCTAssertGreaterThanOrEqual(seconds, 7); XCTAssertLessThanOrEqual(seconds, 8)
    }
}
