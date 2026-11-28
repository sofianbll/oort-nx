import Foundation
import XCTest
@testable import OortLibrary

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

    func testCloudLevelIsBoundedAndGlidesThroughIrregularUpdates() {
        typealias Motion = DownloadCloudMotion
        for updates: [(Double, Motion.Scene)] in [
            [(0.5, .drift(1))],
            [(0.51, .drift(0.1)), (0.52, .drift(0.28)), (0.52, .drift(0.46)), (0.81, .drift(0.50)),
             (1.4, .settle(0.5)), (6.4, .drift(0.55)), (6.57, .drift(0.7)),
             (6.63, .verify(1)), (6.80, .completion)],
            [(0.1, .drift(0.01)), (0.4, .drift(0.22)), (5.4, .drift(0.85)), (5.6, .settle(0.85)),
             (5.9, .drift(0.92)), (6.2, .drift(1))],
        ] {
            var track = Motion.Track(.drift(0), at: 0)
            var next = 0, cap = 0.0, last = 0.0, speed = 0.0
            for i in 0...720 {
                let t = Double(i) / 60
                while next < updates.count && updates[next].0 <= t {
                    let (time, scene) = updates[next]
                    let before = track
                    track.receive(scene, at: time)
                    for offset in [-0.0001, 0, 0.0001] {
                        let a = before.sample(at: time + offset), b = track.sample(at: time + offset)
                        XCTAssertEqual(a.surface.level!, b.surface.level!, accuracy: 1e-10)
                        XCTAssertEqual(a.surface.energy, b.surface.energy, accuracy: 1e-10)
                    }
                    cap = scene.level ?? cap
                    next += 1
                }
                let sample = track.sample(at: t)
                let level = sample.surface.level!
                let step = level - last
                XCTAssertLessThanOrEqual(level, cap + 1e-10)
                XCTAssertGreaterThanOrEqual(step, -1e-10)
                XCTAssertLessThanOrEqual(step, 0.012)
                XCTAssertLessThanOrEqual(abs(step * 60 - speed), 0.032)
                if sample.celebration != nil { XCTAssertEqual(level, 1, accuracy: 1e-10) }
                last = level
                speed = step * 60
            }
            XCTAssertEqual(last, cap, accuracy: 1e-10)
            XCTAssertEqual(track.sample(at: 12).surface.energy, 0, accuracy: 1e-10)
        }
    }

    func testCloudRestartDissolvesAndReducedMotionFadesOnlyEarnedBands() {
        typealias Motion = DownloadCloudMotion
        var track = Motion.Track(.drift(0.8), at: 0)
        XCTAssertEqual(track.sample(at: 0).surface.level, 0.8)
        XCTAssertEqual(track.sample(at: 0).opacity, 0)
        track.receive(.drift(0.06), at: 1, restart: true)
        track.receive(.drift(0.16), at: 1.3)
        XCTAssertEqual(track.sample(at: 1).opacity, 1)
        var last = 1.0
        for i in 0...120 {
            let sample = track.sample(at: 1 + Double(i) / 60)
            XCTAssertLessThan(abs(sample.opacity - last), 0.055)
            if sample.surface.level == 0.8 { XCTAssertLessThanOrEqual(sample.opacity, last + 1e-10) }
            last = sample.opacity
        }
        XCTAssertEqual(track.sample(at: 5).surface.level!, 0.16, accuracy: 1e-10)
        track.receive(.drift(0.10), at: 5) // A revised total, not a new request.
        XCTAssertEqual(track.sample(at: 5).surface.level!, 0.16, accuracy: 1e-10)
        XCTAssertEqual(track.sample(at: 5.8).opacity, 0)
        XCTAssertEqual(track.sample(at: 7).surface.level!, 0.10, accuracy: 1e-10)

        var still = Motion.Track(.drift(nil), at: 0, reduced: true)
        XCTAssertNil(still.sample(at: 0.4).surface.level)
        still.receive(.drift(0.45), at: 1)
        still.receive(.drift(0.6), at: 1.12)
        let bands = still.sample(at: 1.2).bands
        XCTAssertEqual(bands.map(\.level), [0.45, 0.6])
        XCTAssertGreaterThan(bands[0].opacity, bands[1].opacity)
        XCTAssertGreaterThan(bands[1].opacity, 0)
        XCTAssertEqual(still.sample(at: 1.2).surface.energy, 0)
        XCTAssertEqual(still.sample(at: 2).bands.map(\.opacity), [1])
    }
}
