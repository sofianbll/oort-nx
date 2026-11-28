import XCTest
@testable import OortCore

final class ConvolutionTests: XCTestCase {
    private func direct(_ x: [Float], _ h: [Float], count: Int) -> [Float] {
        (0..<count).map { n in
            var sum = 0.0
            for q in 0..<h.count where n - q >= 0 && n - q < x.count { sum += Double(x[n - q]) * Double(h[q]) }
            return Float(sum)
        }
    }

    func testMatchesTheDirectSumOnOddSizes() {
        var seed: UInt32 = 7
        func next() -> Float { seed = seed &* 1_664_525 &+ 1_013_904_223; return Float(seed) / Float(UInt32.max) * 2 - 1 }
        for (a, b) in [(1, 1), (5, 3), (37, 64), (200, 129), (3, 500)] {
            let x = (0..<a).map { _ in next() }, h = (0..<b).map { _ in next() }
            for count in [a, a + b - 1, a + b + 9] {
                let fast = Convolution.convolve(x, h, count: count), slow = direct(x, h, count: count)
                XCTAssertEqual(fast.count, count)
                XCTAssertLessThan(zip(fast, slow).map { abs($0 - $1) }.max() ?? 0, 1e-5, "\(a)x\(b) \(count)")
            }
        }
    }

    func testEmptyInputsGiveSilence() {
        XCTAssertEqual(Convolution.convolve([], [1], count: 3), [0, 0, 0])
        XCTAssertEqual(Convolution.convolve([1], [], count: 2), [0, 0])
        XCTAssertEqual(Convolution.convolve([1], [1], count: 0), [])
    }
}
