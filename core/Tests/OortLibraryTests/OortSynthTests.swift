import XCTest
@testable import OortLibrary

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
                XCTAssertLessThan(values.count / 2, 48_000 * (event == .boot ? 3 : 2))
            }
            XCTAssertNil(synth.wav(.ambience))
        }
        XCTAssertNil(OortSynth(pack: "selene")); XCTAssertNil(OortSynth(pack: "imported"))
    }

    func testComposedNotesStayInRangeAndChangeTheMove() throws {
        let synth = try XCTUnwrap(OortSynth(pack: "oort"))
        for figure in OortSynth.Figure.allCases {
            XCTAssertEqual(figure.notes.count, 8)
            XCTAssertTrue(figure.notes.allSatisfy(OortSynth.range.contains), figure.rawValue)
        }
        XCTAssertEqual(OortSynth.notes(.custom, custom: [-9, 99, 0, 1, 2, 3, 4, 5]), [0, 24, 0, 1, 2, 3, 4, 5])
        for bad in [[], [1, 2], [0, 1, 2, 3, 4, 5, 6, Double.nan]] {
            XCTAssertEqual(OortSynth.notes(.custom, custom: bad), OortSynth.Figure.custom.notes)
        }
        XCTAssertEqual(OortSynth.notes(.minor, custom: [0, 0, 0, 0, 0, 0, 0, 0]), OortSynth.Figure.minor.notes)
        let major = OortSynth.Figure.major.notes
        XCTAssertNotEqual(synth.wav(.move, step: 7, notes: major), synth.wav(.move, step: 7))
        XCTAssertNotEqual(synth.wav(.move, step: 1, notes: major, octave: 1), synth.wav(.move, step: 1, notes: major))
        XCTAssertEqual(synth.wav(.move, notes: major, octave: 9), synth.wav(.move, notes: major, octave: 2))
        XCTAssertNil(synth.wav(.move, notes: []))
    }

    func testAPlaceFollowsEverywhereUntilItHasItsOwnMelody() throws {
        var settings = AppSettings()
        settings.noteFigure = .minor
        XCTAssertEqual(settings.melody(.games), settings.melody(nil))
        settings.setMelody(.init(figure: .custom, octave: 9, custom: [0, 1, 2, 3, 4, 5, 6, 7]), for: .ribbon)
        XCTAssertEqual(settings.melody(.ribbon).octave, 2)
        XCTAssertEqual(settings.melody(.ribbon).notes, [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(settings.melody(.lists).figure, .minor)
        settings.setMelody(.init(figure: .wave, octave: -1), for: nil)
        XCTAssertEqual(settings.melody(.players).figure, .wave)
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(saved.melody(.ribbon), settings.melody(.ribbon))
        XCTAssertEqual(saved.melody(.games), .init(figure: .wave, octave: -1))
        // Settings from 0.5.0-beta.1 have no places; a damaged one is not worth losing the rest for.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"noteFigure":"dream","noteOctave":1}"#.utf8))
        XCTAssertEqual(old.melody(.games), .init(figure: .dream, octave: 1))
        let odd = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"noteFigure":"dream","placeNotes":{"games":{"figure":"zzz","octave":"x"}}}"#.utf8))
        XCTAssertEqual(odd.noteFigure, .dream)
        XCTAssertEqual(odd.melody(.games), .init())
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
