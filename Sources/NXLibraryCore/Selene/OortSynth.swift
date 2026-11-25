import Accelerate
import Foundation

/// The interface sounds of the Oort packs, made here: rounded notes, soft clicks and one small room. No audio file.
public struct OortSynth: Sendable {
    public struct Voice: Sendable {
        enum Wave: Sendable { case sine, triangle, square }
        let wave: Wave
        let frequency, decay, cutoff: Double
        let partials: [Double]

        static let all: [String: Voice] = [
            "oort": Voice(wave: .sine, frequency: 523, decay: 0.16, cutoff: 5200, partials: [1, 2.01]),
            "pollen": Voice(wave: .sine, frequency: 659, decay: 0.28, cutoff: 6500, partials: [1, 3.9]),
            "umbra": Voice(wave: .triangle, frequency: 262, decay: 0.24, cutoff: 1500, partials: [1, 1.5]),
            "impulsion": Voice(wave: .square, frequency: 392, decay: 0.07, cutoff: 2600, partials: [1]),
        ]
    }

    /// Eight notes, in semitones above the voice's fifth, played one per step of the focus.
    public enum Figure: String, CaseIterable, Codable, Sendable {
        case rise, major, pentatonic, minor, arpeggio, dream, moonlit, wave, descent, custom

        public var notes: [Double] {
            switch self {
            case .rise: [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5]
            case .major: [0, 2, 4, 5, 7, 9, 11, 12]
            case .pentatonic: [0, 2, 4, 7, 9, 12, 14, 16]
            case .minor: [0, 2, 3, 5, 7, 8, 10, 12]
            case .arpeggio: [0, 4, 7, 12, 16, 19, 16, 12]
            case .dream: [0, 2, 4, 6, 8, 10, 12, 14]
            case .moonlit: [0, 2, 3, 7, 8, 12, 14, 15]
            case .wave: [0, 4, 7, 9, 12, 9, 7, 4]
            case .descent: [12, 11, 9, 7, 5, 4, 2, 0]
            case .custom: [0, 2, 4, 5, 7, 9, 11, 12]
            }
        }
    }

    /// Where the focus moves. Each place may have its own sequence; the others follow the common one.
    public enum Place: String, CaseIterable, Codable, Sendable { case games, ribbon, players, lists }

    public struct Melody: Codable, Equatable, Sendable {
        public var figure: Figure
        public var octave: Int
        public var custom: [Double]

        public init(figure: Figure = .rise, octave: Int = 0, custom: [Double] = []) {
            self.figure = figure
            self.octave = min(OortSynth.octaves.upperBound, max(OortSynth.octaves.lowerBound, octave))
            self.custom = custom
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(figure: (try? c.decode(Figure.self, forKey: .figure)) ?? .rise, octave: (try? c.decode(Int.self, forKey: .octave)) ?? 0,
                      custom: (try? c.decode([Double].self, forKey: .custom)) ?? [])
        }

        public var notes: [Double] { OortSynth.notes(figure, custom: custom) }
    }

    public static let octaves = -2...2
    public static let range = 0.0...24.0
    /// Eight notes inside the range, or the figure's own when the stored ones are not usable.
    public static func notes(_ figure: Figure, custom: [Double]) -> [Double] {
        guard figure == .custom, custom.count == 8, custom.allSatisfy(\.isFinite) else { return figure.notes }
        return custom.map { min(range.upperBound, max(range.lowerBound, $0)) }
    }
    static let rate = 48_000.0
    private let voice: Voice

    public init?(pack: String) {
        guard let voice = Voice.all[pack] else { return nil }
        self.voice = voice
    }

    /// A 16-bit stereo WAV, or nil when the pack leaves this event silent. `step` climbs while the focus keeps moving.
    public func wav(_ event: SoundPackEvent, step: Int = 0, notes: [Double] = Figure.rise.notes, octave: Int = 0) -> Data? {
        var mix = Mix(seconds: event == .boot ? 2.8 : 1.6)
        switch event {
        case .move:
            guard !notes.isEmpty else { return nil }
            let semitones = notes[((step % notes.count) + notes.count) % notes.count]
            let shift = Double(min(Self.octaves.upperBound, max(Self.octaves.lowerBound, octave)))
            note(&mix, 1.5 * pow(2, semitones / 12 + shift), volume: 0.055, length: 0.45)
        case .select:
            click(&mix, 0.22, 1500)
            note(&mix, 0.5, volume: 0.1, length: 0.5)
        case .confirm:
            click(&mix, 0.16, 2600)
            note(&mix, 1.335, at: 0.012, volume: 0.12)
        case .open:
            click(&mix, 0.2, 1700)
            note(&mix, 1, volume: 0.1)
            note(&mix, 1.5, at: 0.06, volume: 0.09)
        case .close, .back: note(&mix, 0.75, volume: 0.1)
        case .deny:
            note(&mix, 0.75, volume: 0.1)
            note(&mix, 0.707, at: 0.08, volume: 0.1)
        case .play:
            click(&mix, 0.26, 1100)
            note(&mix, 0.75, volume: 0.13)
            note(&mix, 1.125, at: 0.07, volume: 0.13)
        case .success:
            note(&mix, 1, volume: 0.15)
            note(&mix, 1.5, at: 0.09, volume: 0.15)
            note(&mix, 2, at: 0.2, volume: 0.16, length: 2.2)
        case .notification:
            note(&mix, 1, volume: 0.14, length: 1.6)
            note(&mix, 1.5, at: 0.1, volume: 0.12, length: 2)
        case .resume:
            note(&mix, 1, volume: 0.18, length: 1.4)
            note(&mix, 1.5, at: 0.11, volume: 0.16, length: 1.8)
            note(&mix, 1.25, at: 0.3, volume: 0.14, length: 2.4)
        case .boot: sun(&mix)
        case .ambience: return nil
        }
        return mix.wav()
    }

    private func note(_ mix: inout Mix, _ ratio: Double, at start: Double = 0, volume: Double, length: Double = 1) {
        for (index, partial) in voice.partials.enumerated() {
            let level = volume / (1 + Double(index) * 2.6) * (voice.wave == .square ? 0.35 : 1)
            let release = voice.decay * length / (1 + Double(index) * 0.6)
            let count = Int((voice.decay * length + 0.05) * Self.rate)
            let step = voice.frequency * ratio * partial / Self.rate
            var filter = LowPass(cutoff: voice.cutoff, rate: Self.rate)
            var samples = [Float](repeating: 0, count: count)
            for n in 0..<count {
                let time = Double(n) / Self.rate, phase = (Double(n) * step).truncatingRemainder(dividingBy: 1)
                let shape: Double = switch voice.wave {
                case .sine: sin(2 * .pi * phase)
                case .triangle: 4 * abs((phase + 0.75).truncatingRemainder(dividingBy: 1) - 0.5) - 1
                case .square: phase < 0.5 ? 1 : -1
                }
                // 4 ms up, then an exponential fall to -80 dB.
                let envelope = time < 0.004 ? level * time / 0.004
                    : level * pow(0.0001 / max(level, 0.0001), min(1, (time - 0.004) / max(0.001, release - 0.004)))
                let tail = min(1, Double(count - n) / (0.004 * Self.rate))
                samples[n] = Float(filter.run(shape) * envelope * tail)
            }
            mix.add(samples, at: start)
        }
    }

    /// The Sun: three pure tones in tune with the voice, then the cloud answering on both sides. Nothing else.
    private func sun(_ mix: inout Mix) {
        var root = voice.frequency
        while root > 172 { root /= 2 }
        if root < 118 { root *= 1.5 }
        let length = 2.4, count = Int(length * Self.rate)
        func bell(_ u: Double, _ rise: Double, _ fall: Double) -> Double {
            u <= 0 ? 0 : u < rise ? 0.5 - 0.5 * cos(.pi * u / rise) : exp(-(u - rise) / fall)
        }
        let parts: [(ratio: Double, level: Double, envelope: (Double) -> Double)] = [
            (1, 1, { bell($0, 0.13, 0.19) + 0.26 * bell($0 - 0.36, 0.15, 0.2) }),
            (2, 0.17, { bell($0, 0.10, 0.14) + 0.2 * bell($0 - 0.36, 0.13, 0.16) }),
            (3, 0.03, { bell($0, 0.09, 0.12) }),
            (1, 0.22, { bell($0 - 0.1, 0.34, 0.42) }),
        ]
        for part in parts {
            var phase = 0.0
            mix.add((0..<count).map { n in
                let time = Double(n) / Self.rate
                // The pitch settles once, gently.
                phase += root * part.ratio * (1 - 0.045 * exp(-time / 0.06)) / Self.rate
                let close = time > length - 0.5 ? 0.5 + 0.5 * cos(.pi * (time - length + 0.5) / 0.5) : 1
                return Float(sin(2 * .pi * phase) * part.envelope(time) * part.level * close * 0.11)
            }, at: 0)
        }
    }

    private func click(_ mix: inout Mix, _ volume: Double, _ frequency: Double) {
        let count = Int(0.018 * Self.rate)
        var band = BandPass(center: frequency, q: 1.1, rate: Self.rate)
        var seed: UInt32 = 0x6f6f7274
        let samples = (0..<count).map { n -> Float in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            return Float(band.run(noise * pow(1 - Double(n) / Double(count), 6)) * volume)
        }
        mix.add(samples, at: 0)
    }

    private struct LowPass {
        private var b0, b1, b2, a1, a2: Double
        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        init(cutoff: Double, rate: Double) {
            let w = 2 * Double.pi * min(cutoff, rate * 0.45) / rate, alpha = sin(w) / (2 * 0.8912), a0 = 1 + alpha
            b0 = (1 - cos(w)) / 2 / a0; b1 = (1 - cos(w)) / a0; b2 = b0
            a1 = -2 * cos(w) / a0; a2 = (1 - alpha) / a0
        }
        mutating func run(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    private struct BandPass {
        private var b0, a1, a2: Double
        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        init(center: Double, q: Double, rate: Double) {
            let w = 2 * Double.pi * center / rate, alpha = sin(w) / (2 * q), a0 = 1 + alpha
            b0 = alpha / a0; a1 = -2 * cos(w) / a0; a2 = (1 - alpha) / a0
        }
        mutating func run(_ x: Double) -> Double {
            let y = b0 * x - b0 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    private struct Mix {
        private var dry: [Float]
        init(seconds: Double) { dry = [Float](repeating: 0, count: Int(seconds * OortSynth.rate)) }

        mutating func add(_ samples: [Float], at start: Double) {
            let offset = Int(start * OortSynth.rate)
            for (index, value) in samples.enumerated() where offset + index < dry.count { dry[offset + index] += value }
        }

        /// Two decorrelated short rooms, then a soft ceiling: nothing can clip.
        func wav() -> Data {
            let length = dry.count
            let sides = [UInt32(5), 11].map { seed -> [Float] in
                let room = Self.room(seed)
                var wet = [Float](repeating: 0, count: length)
                let padded = [Float](repeating: 0, count: room.count - 1) + dry
                room.withUnsafeBufferPointer { kernel in
                    vDSP_conv(padded, 1, kernel.baseAddress! + room.count - 1, -1, &wet, 1, vDSP_Length(length), vDSP_Length(room.count))
                }
                return zip(dry, wet).map { tanh(0.55 * ($0 + 0.12 * $1) * 1.4) / 1.4 }
            }
            // Silence at the end is not worth keeping in memory.
            let last = (sides.compactMap { side in side.lastIndex { abs($0) > 0.00003 } }.max() ?? 0) + 480
            let frames = min(length, last)
            var data = Data()
            func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
            let bytes = UInt32(frames * 4)
            data.append(contentsOf: Array("RIFF".utf8)); put(36 + bytes); data.append(contentsOf: Array("WAVEfmt ".utf8))
            put(UInt32(16)); put(UInt16(1)); put(UInt16(2)); put(UInt32(OortSynth.rate)); put(UInt32(OortSynth.rate) * 4)
            put(UInt16(4)); put(UInt16(16)); data.append(contentsOf: Array("data".utf8)); put(bytes)
            for n in 0..<frames {
                let fade = min(1, Float(frames - n) / 240)
                for side in sides { put(Int16(max(-1, min(1, side[n] * fade)) * 32_767)) }
            }
            return data
        }

        private static func room(_ start: UInt32) -> [Float] {
            var seed = start
            let count = Int(OortSynth.rate * 0.5)
            var room = (0..<count).map { n -> Float in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return (Float(seed) / Float(UInt32.max) * 2 - 1) * pow(1 - Float(n) / Float(count), 3.2)
            }
            // The level WebAudio gives a convolution: unit energy.
            var energy: Float = 0
            vDSP_svesq(room, 1, &energy, vDSP_Length(count))
            var scale = 1 / max(0.0001, energy.squareRoot())
            vDSP_vsmul(room, 1, &scale, &room, 1, vDSP_Length(count))
            return room
        }
    }
}
