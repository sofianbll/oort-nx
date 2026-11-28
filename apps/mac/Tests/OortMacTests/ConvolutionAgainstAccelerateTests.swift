import Accelerate
import OortCore
import XCTest

/// The core's FFT convolution against the Accelerate call it replaced, at the sizes of the app's sounds: a room of
/// 0.5 s over 1.6 s at 48 kHz. A WAV sample is 1/32768: the difference must stay well under one.
final class ConvolutionAgainstAccelerateTests: XCTestCase {
    func testTheRoomOfASoundMatchesVDSP() {
        var seed: UInt32 = 5
        func next() -> Float { seed = seed &* 1_664_525 &+ 1_013_904_223; return Float(seed) / Float(UInt32.max) * 2 - 1 }
        let length = 76_800, roomCount = 24_000
        let dry = (0..<length).map { n in n < 9_000 ? next() * 0.5 : 0 }
        let room = (0..<roomCount).map { n in next() * pow(1 - Float(n) / Float(roomCount), 3.2) / 40 }
        var expected = [Float](repeating: 0, count: length)
        let padded = [Float](repeating: 0, count: roomCount - 1) + dry
        room.withUnsafeBufferPointer { kernel in
            vDSP_conv(padded, 1, kernel.baseAddress! + roomCount - 1, -1, &expected, 1, vDSP_Length(length), vDSP_Length(roomCount))
        }
        let actual = Convolution.convolve(dry, room, count: length)
        let worst = zip(expected, actual).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(worst, 0.5 / 32_768, "largest difference \(worst)")
    }
}
