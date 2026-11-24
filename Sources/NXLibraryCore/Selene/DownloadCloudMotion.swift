import Foundation

/// Normalized tile coordinates; time is the shared clock for drift and elapsed seconds for a cue.
public enum DownloadCloudMotion {
    public enum Intensity: String, CaseIterable { case fine, present }
    public enum Scene: Equatable {
        case drift(Double?)
        case settle(Double?)
        case completion
        case fade

        public var duration: Double {
            switch self {
            case .drift: 4.8
            case .settle: 0.55
            case .completion: 1.10
            case .fade: 0.48
            }
        }

        public var repeats: Bool { if case .drift = self { true } else { false } }
    }

    public struct Mote: Equatable {
        public let center: CGPoint
        public let radius: Double
        public let opacity: Double
        public let accent: Bool
    }

    public static func frame(_ scene: Scene, seed: UInt64, at time: Double, intensity: Intensity) -> [Mote] {
        guard time.isFinite else { return [] }
        let t = scene.repeats ? wrap(time / scene.duration) : limit(time / scene.duration)
        guard scene.repeats || (time >= 0 && t < 1) else { return [] }
        var random = SplitMix(seed: seed)
        let fine = intensity == .fine
        switch scene {
        case .drift(let fraction), .settle(let fraction):
            let fraction = fraction.flatMap { $0.isFinite ? limit($0) : nil }
            let maxCount = fine ? 11 : 17
            let density = fraction.map { 3 + (Double(maxCount) - 3) * $0 } ?? (fine ? 5 : 8)
            let settling = !scene.repeats
            return (0..<maxCount).map { i in
                let x = 0.15 + 0.70 * random.unit()
                let rhythm = random.unit()
                let distance = 0.038 + 0.082 * random.unit()
                let p = settling ? 0.45 + 0.55 * smooth(t) : wrap(t + rhythm)
                let y: Double
                if let fraction {
                    let edge = edgeY(fraction)
                    let direction: Double = rhythm < 0.75 ? -1 : 1
                    // At the very start/end, use the side of the edge that has room.
                    let lane = direction * distance * limit((direction < 0 ? edge - 0.05 : 0.95 - edge) / 0.13)
                    y = edge + lane * (1 - p)
                } else {
                    // A loose cluster, not a line that could be read as a measured level.
                    y = 0.57 + (rhythm - 0.5) * 0.23
                        + sin(2 * .pi * (t + rhythm)) * 0.018 * (settling ? 1 - smooth(t) : 1)
                }
                let visibility = settling ? (1 - smooth(t)) * 0.78 : sin(.pi * p) * sin(.pi * p)
                let opacity = visibility * limit(density - Double(i)) * (fine ? 0.70 : 0.90)
                return mote(x: x + (rhythm - 0.5) * 0.048 * (1 - p), y: y,
                            opacity: opacity, fine: fine, random: &random)
            }
        case .completion, .fade:
            let fadeOnly = scene == .fade
            let gathered = fadeOnly ? 1 : smooth(t / 0.56)
            let glow = smooth(t / (fadeOnly ? 0.16 : 0.26))
                * (1 - smooth((t - (fadeOnly ? 0.18 : 0.63)) / (fadeOnly ? 0.82 : 0.37)))
            let rim = fine ? 21 : 27, cut = fine ? 15 : 21, belt = fine ? 10 : 16
            return (0..<(rim + cut + belt + 1)).map { i in
                let angle: Double
                let target: CGPoint
                let r = 0.255
                // The mark's cross-section: thin outer rim, elliptical cut on the right,
                // two equatorial funnels with empty space around the single sun.
                if i < rim {
                    angle = 2 * .pi * Double(i) / Double(rim)
                    target = CGPoint(x: r * cos(angle), y: r * sin(angle))
                } else if i < rim + cut {
                    angle = .pi * (Double(i - rim) + 0.5) / Double(cut) - .pi / 2
                    target = CGPoint(x: r * 0.55 * cos(angle), y: r * sin(angle))
                } else if i < rim + cut + belt {
                    let p = Double(i - rim - cut) / Double(belt - 1)
                    let x = (p < 0.5 ? -1.0 : 1.0) * (0.055 + 0.185 * pow(abs(2 * p - 1), 0.85))
                    target = CGPoint(x: x, y: (random.unit() - 0.5) * 1.7 * x * x)
                } else {
                    target = .zero
                }
                let scatter = 1 - gathered
                let x = 0.5 + target.x * (1 + 0.48 * scatter) + (random.unit() - 0.5) * 0.19 * scatter
                let y = 0.48 + target.y * (1 + 0.36 * scatter) + (random.unit() - 0.39) * 0.23 * scatter
                let sun = i == rim + cut + belt
                let opacity = glow * (fine ? 0.72 : 0.91) * (i < rim ? 0.86 : 1)
                return mote(x: x, y: y, opacity: opacity, fine: fine, sun: sun, random: &random)
            }
        }
    }

    public static func edgeY(_ fraction: Double) -> Double { min(0.95, max(0.05, 1 - fraction)) }

    private static func mote(x: Double, y: Double, opacity: Double, fine: Bool, sun: Bool = false,
                             random: inout SplitMix) -> Mote {
        let size = Double(MoonlightField.size.lowerBound)
            + Double(MoonlightField.size.upperBound - MoonlightField.size.lowerBound) * pow(random.unit(), 2)
        let tint = random.unit()
        return Mote(center: CGPoint(x: x, y: y),
                    radius: sun ? 0.010 : 0.004 + (fine ? 1.1 : 1.45) * size,
                    opacity: opacity * (sun ? 1 : 0.60 + 0.40 * random.unit()),
                    accent: sun || tint >= MoonlightField.inkShare)
    }

    private static func limit(_ x: Double) -> Double { min(max(x, 0), 1) }
    private static func wrap(_ x: Double) -> Double { x - floor(x) }
    private static func smooth(_ x: Double) -> Double { let p = limit(x); return p * p * (3 - 2 * p) }
}
