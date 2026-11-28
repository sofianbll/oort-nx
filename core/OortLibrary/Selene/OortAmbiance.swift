import Foundation
import OortCore

/// The three house moods of the interface: the same notes and the same timing as the other Oort voices,
/// with their own tone, click and room.
extension OortSynth {
    /// Saved ids and the catalog keys of their names, in the order Settings offers them.
    public static let ambiances = [(id: "frost", name: "Frost"), (id: "mist", name: "Mist"), (id: "nucleus", name: "Nucleus")]

    struct Mood: Sendable {
        /// One level per partial of the voice.
        let levels: [Double]
        let attack: Double
        /// Strength and pitch of the clicks, against the other voices'; and the faint one under a move.
        let click, clickPitch, moveClick: Double
        /// Seconds of the room, and how bright it is.
        let room, tone: Double
        /// How much of the room is heard.
        let wet: Float
        /// Seconds a sound may last, the Sun aside.
        let span: Double
        /// The Sun's second and third tones, against the other voices'.
        let overtones: Double
    }

    // Each is tuned on a C, so Compose names the notes it plays.
    static let moods: [String: Voice] = [
        // Lively and crisp: struck glass, a bright click, a small room.
        "frost": Voice(wave: .sine, frequency: 523.25, decay: 0.095, cutoff: 11_000, partials: [1, 2.76, 5.4],
                       mood: Mood(levels: [1, 0.5, 0.22], attack: 0.0015, click: 1.35, clickPitch: 2, moveClick: 0.05,
                                  room: 0.16, tone: 9_000, wet: 0.09, span: 1.0, overtones: 1.8)),
        // Wide and soft: two sines a hair apart, no click, a long dim room.
        "mist": Voice(wave: .sine, frequency: 261.63, decay: 0.36, cutoff: 3_200, partials: [1, 1.006, 2, 3, 4],
                      mood: Mood(levels: [0.55, 0.35, 0.42, 0.2, 0.09], attack: 0.012, click: 0, clickPitch: 1, moveClick: 0,
                                 room: 1.1, tone: 3_600, wet: 0.34, span: 1.9, overtones: 1)),
        // Low and clean: a deep body whose harmonics small speakers still carry, a short knock, almost dry.
        "nucleus": Voice(wave: .sine, frequency: 130.81, decay: 0.13, cutoff: 2_400, partials: [1, 2, 3, 4, 6],
                         mood: Mood(levels: [0.6, 0.62, 0.45, 0.34, 0.18], attack: 0.0025, click: 1.4, clickPitch: 0.75, moveClick: 0.06,
                                    room: 0.12, tone: 2_400, wet: 0.05, span: 1.2, overtones: 2.2)),
    ]

    /// The loudest 400 ms of each sound of the "oort" voice, in LUFS (the eight moves averaged).
    /// A test measures both and fails when they drift apart.
    static let loudness: [SoundPackEvent: Double] = [
        .move: -47.97, .select: -43.05, .confirm: -38.6, .back: -40.39, .deny: -37.41, .open: -37.76, .close: -40.39,
        .play: -35.09, .resume: -29.51, .success: -30.1, .notification: -32.97, .boot: -29.23,
    ]

    /// A thin room, 1 600 echoes a second instead of one per sample: it renders in milliseconds.
    static func echoes(_ dry: [Float], mood: Mood, seed start: UInt32) -> [Float] {
        let length = dry.count, spacing = Int(rate) / 1_600
        var seed = start
        func random() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed) / Float(UInt32.max)
        }
        let taps = (0..<Int(mood.room * 1_600)).map { k -> (delay: Int, level: Float) in
            // The first echo comes after 2 ms, so the sound itself stays in front.
            let delay = 96 + k * spacing + Int(random() * Float(spacing - 1))
            let level = pow(max(0, 1 - Float(delay) / Float(mood.room * rate)), 3)
            return (delay, random() < 0.5 ? -level : level)
        }
        // The level of the other voices' room: unit energy.
        let scale = 1 / max(0.0001, taps.reduce(0) { $0 + $1.level * $1.level }.squareRoot())
        // One pass per echo over the part that sounds. Plain `while` loops over raw pointers: a Debug build (the
        // tests) does not specialise `for … in` ranges; a Release build vectorises this loop.
        let sounding = (dry.lastIndex { $0 != 0 } ?? 0) + 1
        var wet = [Float](repeating: 0, count: length)
        dry.withUnsafeBufferPointer { source in
            wet.withUnsafeMutableBufferPointer { out in
                let source = source.baseAddress!
                for tap in taps where tap.delay < length {
                    let level = tap.level * scale
                    let count = min(sounding, length - tap.delay), at = out.baseAddress! + tap.delay
                    var n = 0
                    while n < count { at[n] += source[n] * level; n += 1 }
                }
            }
        }
        var filter = LowPass(cutoff: mood.tone, rate: rate)
        return wet.map { Float(filter.run(Double($0))) }
    }

    /// Takes out what lies under 20 Hz (a short low note would push the speaker to one side), then sets the
    /// loudest 400 ms (ITU-R BS.1770 K weighting) to `target`, never above -6 dBFS.
    static func finish(_ sides: inout [[Float]], to target: Double) {
        let keep = Float(1 - 2 * Double.pi * 20 / rate)
        for index in sides.indices {
            var before: Float = 0, out: Float = 0
            sides[index] = sides[index].map { value in
                out = value - before + keep * out
                before = value
                return out
            }
        }
        let window = Int(rate * 0.4)
        var power = [Double](repeating: 0, count: sides[0].count)
        for side in sides {
            var shelf = Weighting(b: (1.53512485958697, -2.69169618940638, 1.19839281085285), a: (-1.69065929318241, 0.73248077421585))
            var high = Weighting(b: (1, -2, 1), a: (-1.99004745483398, 0.99007225036621))
            for (n, value) in side.enumerated() {
                let weighted = high.run(shelf.run(Double(value)))
                power[n] += weighted * weighted
            }
        }
        var sum = 0.0, best = 0.0
        for n in power.indices {
            sum += power[n]
            if n >= window { sum -= power[n - window] }
            best = max(best, sum)
        }
        let peak = sides.flatMap { $0 }.reduce(Float(0)) { max($0, abs($1)) }
        guard best > 0, peak > 0 else { return }
        let loudness = -0.691 + 10 * log10(best / Double(window))
        let gain = min(Float(pow(10, (target - loudness) / 20)), 0.5 / peak)
        for index in sides.indices { sides[index] = sides[index].map { $0 * gain } }
    }

    private struct Weighting {
        let b: (Double, Double, Double), a: (Double, Double)
        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        init(b: (Double, Double, Double), a: (Double, Double)) { self.b = b; self.a = a }
        mutating func run(_ x: Double) -> Double {
            let y = b.0 * x + b.1 * x1 + b.2 * x2 - a.0 * y1 - a.1 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }
}
