import XCTest
@testable import OortLibrary

/// The three house moods, measured on the sound they make. The current Oort voice is the reference.
final class OortAmbianceTests: XCTestCase {
    private let moods = ["frost", "mist", "nucleus"]
    private var events: [SoundPackEvent] { SoundPackEvent.allCases.filter { $0 != .ambience } }

    func testThreeMoodsAreOfferedByNameAndNoneIsChosenForThePlayer() throws {
        let library = SoundPackLibrary(root: URL(fileURLWithPath: "/private/tmp/oort-no-packs"), bundled: nil)
        XCTAssertEqual(library.choices().map(\.key), moods + ["selene"])
        XCTAssertEqual(library.choices().map(\.name), ["Frost", "Mist", "Nucleus", "Selene"])
        for mood in moods {
            let pack = try XCTUnwrap(library.load(mood), mood)
            XCTAssertEqual(pack.manifest.id, mood)
            XCTAssertNil(pack.audio(for: .select), "made by the app, no file")
            XCTAssertNotNil(OortSynth(pack: mood))
        }
        XCTAssertEqual(AppSettings().soundPackID, "oort")
        var chosen = AppSettings()
        chosen.soundPackID = "mist"
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(chosen)).soundPackID, "mist")
    }

    func testNamesAreWrittenInTheSevenLanguages() throws {
        let resources = try XCTUnwrap(L10n.resources())
        let expected: [AppLanguage: [String]] = [
            .english: ["Frost", "Mist", "Nucleus"], .french: ["Givre", "Brume", "Noyau"], .italian: ["Brina", "Foschia", "Nucleo"],
            .german: ["Raureif", "Nebel", "Kern"], .spanish: ["Escarcha", "Bruma", "Núcleo"],
            .portugueseBrazil: ["Geada", "Neblina", "Núcleo"], .chineseSimplified: ["霜晶", "薄雾", "彗核"],
        ]
        for (language, names) in expected {
            let locale = AppLocale(language: language, region: "US")
            XCTAssertEqual(["Frost", "Mist", "Nucleus"].map { L10n.text($0, context: locale, bundle: resources) }, names, "\(language)")
        }
    }

    func testEveryMoodAnswersEveryActionAsLoudAsTheCurrentVoice() throws {
        let reference = try XCTUnwrap(OortSynth(pack: "oort"))
        var wanted: [SoundPackEvent: Double] = [:]
        for event in events where event != .move { wanted[event] = Sound(try XCTUnwrap(reference.wav(event))).loudness }
        let moves = try (0..<8).map { Sound(try XCTUnwrap(reference.wav(.move, step: $0))).loudness }
        wanted[.move] = moves.reduce(0, +) / 8
        for mood in moods {
            let synth = try XCTUnwrap(OortSynth(pack: mood), mood)
            XCTAssertNil(synth.wav(.ambience), "Oort has no idle loop")
            for event in events {
                for step in event == .move ? Array(0..<8) : [0] {
                    let sound = Sound(try XCTUnwrap(synth.wav(event, step: step), "\(mood) \(event)"))
                    XCTAssertEqual(sound.loudness, try XCTUnwrap(wanted[event]), accuracy: 1, "\(mood) \(event) \(step)")
                    XCTAssertLessThanOrEqual(sound.peak, 0.501, "\(mood) \(event) is above -6 dBFS")
                }
            }
            // A composed sequence at either end of the range stays as loud, and under the same ceiling.
            for octave in [-2, 2] {
                let sound = Sound(try XCTUnwrap(synth.wav(.move, step: 7, notes: OortSynth.Figure.arpeggio.notes, octave: octave)))
                XCTAssertEqual(sound.loudness, try XCTUnwrap(wanted[.move]), accuracy: 1, "\(mood) octave \(octave)")
                XCTAssertLessThanOrEqual(sound.peak, 0.501, "\(mood) octave \(octave)")
            }
        }
    }

    func testNoClickNoOffsetAndAQuickStart() throws {
        for mood in moods {
            let synth = try XCTUnwrap(OortSynth(pack: mood), mood)
            for event in events {
                let sound = Sound(try XCTUnwrap(synth.wav(event))), name = "\(mood) \(event)"
                XCTAssertLessThan(abs(sound.left[0]), 0.01, "\(name) starts with a step")
                XCTAssertLessThan(abs(sound.right[0]), 0.01, "\(name) starts with a step")
                XCTAssertLessThan(max(abs(sound.left.last ?? 1), abs(sound.right.last ?? 1)), 0.0002, "\(name) ends with a step")
                // The tail has faded before the file stops: 20 ms before the end it is 40 dB under the peak.
                XCTAssertLessThan(sound.mono.suffix(960).map(abs).max() ?? 1, sound.peak * 0.01, "\(name) is cut short")
                XCTAssertLessThan(abs(sound.mono.reduce(0, +) / Double(sound.mono.count)), 0.001, "\(name) has an offset")
                if event != .boot { XCTAssertLessThan(sound.onset, 0.03, "\(name) answers late") }
                XCTAssertLessThan(sound.seconds, event == .boot ? 3 : 2, name)
                // Mono speakers keep the sound.
                XCTAssertGreaterThan(sound.monoShare, 0.6, "\(name) cancels in mono")
                XCTAssertEqual(synth.wav(event), synth.wav(event), "\(name) changes between two renders")
            }
        }
    }

    func testEachMoodHasItsOwnCharacter() throws {
        func sounds(_ pack: String) throws -> [Sound] {
            let synth = try XCTUnwrap(OortSynth(pack: pack), pack)
            return try events.filter { $0 != .boot }.map { Sound(try XCTUnwrap(synth.wav($0))) }
        }
        let oort = try sounds("oort"), frost = try sounds("frost"), mist = try sounds("mist"), nucleus = try sounds("nucleus")
        func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }
        // Lively and crisp: brighter, shorter, faster to speak.
        XCTAssertGreaterThan(mean(frost.map(\.brightness)), 1.6 * mean(oort.map(\.brightness)))
        XCTAssertLessThan(mean(frost.map(\.ring)), 0.7 * mean(oort.map(\.ring)))
        // Wide and soft: rings longer, starts gentler, wider.
        XCTAssertGreaterThan(mean(mist.map(\.ring)), 1.4 * mean(oort.map(\.ring)))
        XCTAssertGreaterThan(mean(mist.map(\.onset)), 2 * mean(frost.map(\.onset)))
        XCTAssertLessThan(mean(mist.map(\.correlation)), mean(nucleus.map(\.correlation)))
        // Low and clean: darker, tight, nearly dry.
        XCTAssertLessThan(mean(nucleus.map(\.brightness)), 0.8 * mean(oort.map(\.brightness)))
        XCTAssertLessThan(mean(nucleus.map(\.ring)), mean(oort.map(\.ring)))
    }

    func testMoodsPlayTheComposedNotes() throws {
        for mood in moods {
            let synth = try XCTUnwrap(OortSynth(pack: mood), mood)
            XCTAssertNotEqual(synth.wav(.move, step: 7, notes: OortSynth.Figure.major.notes), synth.wav(.move, step: 7), mood)
            XCTAssertNotEqual(synth.wav(.move, step: 1, octave: 1), synth.wav(.move, step: 1), mood)
            XCTAssertEqual(synth.wav(.move, step: 8), synth.wav(.move, step: 0), mood)
            XCTAssertNil(synth.wav(.move, notes: []), mood)
        }
    }

    /// A 48 kHz stereo WAV, and what can be measured on it without the synth's own code.
    private struct Sound {
        let left, right, mono: [Double]
        let peak: Double

        init(_ data: Data) {
            let values = data.dropFirst(44).withUnsafeBytes {
                Array($0.bindMemory(to: Int16.self)).map { Double(Int16(littleEndian: $0)) / 32_767 }
            }
            left = stride(from: 0, to: values.count, by: 2).map { values[$0] }
            right = stride(from: 1, to: values.count, by: 2).map { values[$0] }
            mono = zip(left, right).map { ($0 + $1) / 2 }
            peak = values.reduce(0) { max($0, abs($1)) }
        }

        var seconds: Double { Double(left.count) / 48_000 }

        /// ITU-R BS.1770 K weighting, loudest 400 ms: the "momentary" level of EBU R 128.
        var loudness: Double {
            func weighted(_ side: [Double]) -> [Double] {
                var out = side
                for (b, a) in [([1.53512485958697, -2.69169618940638, 1.19839281085285], [-1.69065929318241, 0.73248077421585]),
                               ([1.0, -2.0, 1.0], [-1.99004745483398, 0.99007225036621])] {
                    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
                    for n in out.indices {
                        let x = out[n], y = b[0] * x + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2
                        x2 = x1; x1 = x; y2 = y1; y1 = y; out[n] = y
                    }
                }
                return out
            }
            let power = zip(weighted(left), weighted(right)).map { $0 * $0 + $1 * $1 }
            var sum = 0.0, best = 0.0
            for n in power.indices {
                sum += power[n]
                if n >= 19_200 { sum -= power[n - 19_200] }
                best = max(best, sum)
            }
            return -0.691 + 10 * log10(best / 19_200)
        }

        /// Seconds before the sound reaches a fifth of its peak.
        var onset: Double { Double(mono.firstIndex { abs($0) >= peak * 0.2 } ?? mono.count) / 48_000 }
        /// Seconds until the last sample above 40 dB under the peak.
        var ring: Double { Double(mono.lastIndex { abs($0) >= peak * 0.01 } ?? 0) / 48_000 }
        /// Energy of the sample-to-sample change over the energy: rises with the share of high frequencies.
        var brightness: Double {
            let change = zip(mono.dropFirst(), mono).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
            return (change / max(1e-12, mono.reduce(0) { $0 + $1 * $1 })).squareRoot()
        }
        var correlation: Double {
            let cross = zip(left, right).reduce(0) { $0 + $1.0 * $1.1 }
            let energy = left.reduce(0) { $0 + $1 * $1 } * right.reduce(0) { $0 + $1 * $1 }
            return cross / max(1e-12, energy.squareRoot())
        }
        var monoShare: Double {
            let both = (left.reduce(0) { $0 + $1 * $1 } + right.reduce(0) { $0 + $1 * $1 }) / 2
            return mono.reduce(0) { $0 + $1 * $1 } / max(1e-12, both)
        }
    }
}
