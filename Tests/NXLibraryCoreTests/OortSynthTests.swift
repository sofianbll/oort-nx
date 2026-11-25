import XCTest
@testable import NXLibraryCore

final class OortSynthTests: XCTestCase {
    private func samples(_ data: Data) -> [Int16] {
        data.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)).map(Int16.init(littleEndian:)) }
    }

    func testEveryPackMakesEveryInterfaceSoundWithoutClipping() throws {
        for pack in ["oort", "pollen", "umbra", "impulsion"] {
            let synth = try XCTUnwrap(OortSynth(pack: pack))
            for event in SoundPackEvent.allCases where event != .ambience {
                let data = try XCTUnwrap(synth.wav(event), "\(pack) \(event)")
                XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
                XCTAssertEqual(data.count, 44 + Int(data.dropFirst(40).prefix(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }))
                let values = samples(data), peak = values.map { abs(Int($0)) }.max() ?? 0
                XCTAssertGreaterThan(peak, 250, "\(pack) \(event) is silent")
                XCTAssertLessThan(peak, 24_000, "\(pack) \(event) is too loud")
                XCTAssertLessThan(values.suffix(2).map { abs(Int($0)) }.max() ?? 0, 4, "\(pack) \(event) ends with a click")
                XCTAssertLessThan(values.count / 2, 48_000 * 2)
            }
            XCTAssertNil(synth.wav(.ambience))
        }
        XCTAssertNil(OortSynth(pack: "selene")); XCTAssertNil(OortSynth(pack: "imported"))
    }

    func testMovesClimbAndStartAgain() throws {
        let synth = try XCTUnwrap(OortSynth(pack: "oort"))
        func crossings(_ step: Int) throws -> Int {
            let left = samples(try XCTUnwrap(synth.wav(.move, step: step))).enumerated().filter { $0.offset % 2 == 0 }.map(\.element).prefix(2_400)
            return zip(left, left.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        }
        XCTAssertGreaterThan(try crossings(7), try crossings(0))
        XCTAssertEqual(synth.wav(.move, step: 8), synth.wav(.move, step: 0))
        XCTAssertEqual(synth.wav(.move, step: -1), synth.wav(.move, step: 7))
        XCTAssertEqual(synth.wav(.success), synth.wav(.success))
    }
}
