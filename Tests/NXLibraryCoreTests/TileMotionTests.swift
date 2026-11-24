import CoreGraphics
import XCTest
@testable import NXLibraryCore

final class TileMotionTests: XCTestCase {
    func testGlowPulsesBetweenItsLowAndHighOver3Point6Seconds() {
        XCTAssertEqual(TileMotion.glowOpacity(at: 0), 0.2, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.glowOpacity(at: 0.9), 0.375, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.glowOpacity(at: 1.8), 0.55, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.glowOpacity(at: 3.6), 0.2, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.glowOpacity(at: 100 + 0.9), TileMotion.glowOpacity(at: 0.9 + 100 - 3.6 * 27), accuracy: 1e-9)
    }

    /// The axis turns clockwise on screen (y grows downwards): left to right, then top to bottom.
    func testRingAxisTurnsOnceEveryFiveSeconds() {
        let start = TileMotion.ringAxis(at: 0)
        XCTAssertEqual(start.start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(start.start.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(start.end.x, 1, accuracy: 1e-9)
        XCTAssertEqual(start.end.y, 0.5, accuracy: 1e-9)
        let quarter = TileMotion.ringAxis(at: 1.25)
        XCTAssertEqual(quarter.start.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(quarter.start.y, 0, accuracy: 1e-9)
        XCTAssertEqual(quarter.end.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(quarter.end.y, 1, accuracy: 1e-9)
        let round = TileMotion.ringAxis(at: 5)
        XCTAssertEqual(round.start.x, start.start.x, accuracy: 1e-9)
        XCTAssertEqual(round.start.y, start.start.y, accuracy: 1e-9)
    }

    func testShineHoldsThenSweepsFromCornerToCornerThenWaits() {
        let w = TileMotion.shineHalfWidth
        XCTAssertEqual(TileMotion.shineCentre(at: 0), -w, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.shineCentre(at: 0.6), -w, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.shineCentre(at: 1.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.shineCentre(at: 2.4), 1 + w, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.shineCentre(at: 4.9), 1 + w, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.shineCentre(at: 5), -w, accuracy: 1e-9)
    }

    func testShineAxisRunsAlongTheTopLeftToBottomRightDiagonal() {
        let axis = TileMotion.shineAxis(at: 1.5)
        XCTAssertEqual(axis.start.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(axis.start.y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(axis.end.x, 0.8, accuracy: 1e-9)
        XCTAssertEqual(axis.end.y, 0.8, accuracy: 1e-9)
    }

    func testLoopSamplesCoverOnePeriodAndCloseOnTheFirstValue() {
        let loop = TileMotion.loop(period: 3.6, steps: 4) { TileMotion.glowOpacity(at: $0) }
        XCTAssertEqual(loop.keyTimes, [0, 0.25, 0.5, 0.75, 1])
        XCTAssertEqual(loop.values.count, 5)
        XCTAssertEqual(loop.values[2], 0.55, accuracy: 1e-9)
        XCTAssertEqual(loop.values.first!, loop.values.last!, accuracy: 1e-9)
    }

    /// Core Animation glides between neighbouring samples, so a jump between two of them is drawn: the shine
    /// would sweep back across the tile in a thirtieth of a second at the end of every cycle. The loop's last
    /// sample is the period's end as it is approached, and the jump back to the start happens as the loop
    /// repeats, at once.
    func testNoLoopGlidesThroughAJump() {
        let shine = TileMotion.loop(period: TileMotion.shinePeriod, steps: 150) { TileMotion.shineCentre(at: $0) }
        XCTAssertEqual(shine.values.last!, 1 + TileMotion.shineHalfWidth, accuracy: 1e-6)
        let ring = TileMotion.loop(period: TileMotion.ringPeriod, steps: 150) { Double(TileMotion.ringAxis(at: $0).start.x) }
        let glow = TileMotion.loop(period: TileMotion.glowPeriod, steps: 108) { TileMotion.glowOpacity(at: $0) }
        for values in [shine.values, ring.values, glow.values] {
            let largest = zip(values, values.dropFirst()).map { abs($1 - $0) }.max()!
            XCTAssertLessThan(largest, 0.1)
        }
    }

    /// A loop on the shared clock picks up where every other ring is, so moving between tiles keeps the beat.
    func testPhaseIsTheTimeIntoTheCurrentPeriod() {
        XCTAssertEqual(TileMotion.phase(period: 5, at: 812.5), 2.5, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.phase(period: 3.6, at: 7.2), 0, accuracy: 1e-9)
    }

    func testDownloadMarkPulsesSlowlyBetweenDimAndFull() {
        XCTAssertEqual(TileMotion.downloadPeriod, 2.8)
        XCTAssertEqual(TileMotion.downloadMarkOpacity(at: 0), 0.4, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.downloadMarkOpacity(at: 1.4), 1, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.downloadMarkOpacity(at: 2.8), 0.4, accuracy: 1e-9)
        XCTAssertEqual(TileMotion.downloadMarkOpacity(at: 0.7), 0.7, accuracy: 1e-9)
        let loop = TileMotion.loop(period: TileMotion.downloadPeriod, steps: 84) { TileMotion.downloadMarkOpacity(at: $0) }
        let largest = zip(loop.values, loop.values.dropFirst()).map { abs($1 - $0) }.max()!
        XCTAssertLessThan(largest, 0.05)
        XCTAssertEqual(loop.values.first!, loop.values.last!, accuracy: 1e-3)
    }

    func testCloudJumpStartsFromTheVisibleLevelAndSettlesAtTheNewOne() throws {
        let size = CGSize(width: 170, height: 170)
        let previous = try XCTUnwrap(DownloadCloudMotion.surface(.drift(0.2), at: 1.8))
        let first = try XCTUnwrap(DownloadCloudMotion.surface(.drift(0.6), at: 1.8, elapsed: 0, from: previous))
        XCTAssertEqual(first.y(at: 32, in: size), previous.y(at: 32, in: size), accuracy: 1e-9)
        let rising = try XCTUnwrap(DownloadCloudMotion.surface(.drift(0.6), at: 2.12, elapsed: 0.32, from: first))
        XCTAssertGreaterThan(rising.level ?? 0, 0.2)
        XCTAssertGreaterThan(rising.energy, first.energy)
        let quiet = try XCTUnwrap(DownloadCloudMotion.surface(.drift(0.6), at: 5.4, elapsed: 3.6, from: first))
        XCTAssertEqual(quiet.y(at: 32, in: size), 68, accuracy: 1e-9)
        XCTAssertEqual(quiet.y(at: 120, in: size), 68, accuracy: 1e-9)
        XCTAssertEqual(quiet.activity, 0)
    }

    func testCloudUnknownIsNotAColourLevelAndReducedMotionHasNoClock() throws {
        let size = CGSize(width: 170, height: 170)
        let unknown = try XCTUnwrap(DownloadCloudMotion.surface(.drift(nil), at: 3))
        XCTAssertNil(unknown.level)
        XCTAssertGreaterThan(unknown.energy, 0)
        let first = try XCTUnwrap(DownloadCloudMotion.surface(.drift(0.2), at: 3, reduced: true))
        let second = try XCTUnwrap(DownloadCloudMotion.surface(.drift(0.2), at: 19, reduced: true))
        XCTAssertEqual(first.y(at: 20, in: size), second.y(at: 20, in: size))
        XCTAssertNotEqual(first.y(at: 20, in: size), first.y(at: 90, in: size))
    }
}
