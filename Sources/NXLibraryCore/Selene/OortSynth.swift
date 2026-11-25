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

    /// A rising figure of eight notes, in semitones. Quarter tones are allowed.
    public static let rise: [Double] = [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5]
    static let rate = 48_000.0
    private let voice: Voice

    public init?(pack: String) {
        guard let voice = Voice.all[pack] else { return nil }
        self.voice = voice
    }

    /// A 16-bit stereo WAV, or nil when the pack leaves this event silent. `step` climbs while the focus keeps moving.
    public func wav(_ event: SoundPackEvent, step: Int = 0) -> Data? {
        var mix = Mix(seconds: 1.6)
        switch event {
        case .move:
            let semitones = Self.rise[((step % 8) + 8) % 8]
            note(&mix, 1.5 * pow(2, semitones / 12), volume: 0.055, length: 0.45)
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
        case .boot:
            note(&mix, 0.5, volume: 0.16, length: 4)
            note(&mix, 1, at: 0.12, volume: 0.14, length: 4)
            note(&mix, 1.5, at: 0.3, volume: 0.12, length: 4)
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
