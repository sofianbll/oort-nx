import Foundation
import OortCore

/// Coordinates and radii are in local tile points; drift time is on the shared clock.
public enum DownloadCloudMotion {
    public enum Intensity: String, CaseIterable { case fine, present }
    public enum Scene: Equatable {
        case drift(Double?)
        case settle(Double?)
        case completion
        case fade

        public var duration: Double {
            switch self {
            case .drift: 6.4
            case .settle: 0.55
            case .completion: 1.20
            case .fade: 0.48
            }
        }

        public var repeats: Bool { if case .drift = self { true } else { false } }
    }

    public struct Mote: Equatable {
        public enum Kind { case ink, accent, sun, star, crest }
        public let center: CGPoint
        public let radius: Double
        public let opacity: Double
        public let kind: Kind
    }

    public struct Frame {
        public let dots: [Mote]
        public let bandY: Double
        public let bandOpacity: Double
        public let centreOpacity: Double
    }

    public static func frame(_ scene: Scene, seed: UInt64, at time: Double, intensity: Intensity,
                             size: CGSize, sourceLevel: Double? = 1) -> Frame {
        let empty = Frame(dots: [], bandY: 0, bandOpacity: 0, centreOpacity: 0)
        guard time.isFinite, size.width > 0, size.height > 0 else { return empty }
        let t = scene.repeats ? time / scene.duration - floor(time / scene.duration) : limit(time / scene.duration)
        guard scene.repeats || (time >= 0 && t < 1) else { return empty }
        let w = size.width, h = size.height
        let scale = min(w, h) / 170
        let present = intensity == .present
        let destination = CGPoint(x: w * 0.5, y: h * 0.46)
        var random = SplitMix(seed: seed)

        func bandY(_ level: Double?) -> Double {
            level.map { max(6 * scale, h * edgeY($0)) } ?? h * 0.56
        }

        switch scene {
        case .drift(let fraction), .settle(let fraction):
            let level = fraction.flatMap { $0.isFinite ? limit($0) : nil }
            let y = bandY(level)
            let settling = !scene.repeats
            let settle = settling ? smooth(t) : 0
            let width = level == nil ? 0.74 : 0.88
            let columns = present ? 19 : 16
            let reach = min(1, y / (24 * scale))
            let activity = 1 - settle
            var dots = [Mote]()
            var crest = [Mote]()
            for row in 0..<3 {
                for column in 0..<columns {
                    let phase = 2 * .pi * random.unit()
                    let spacing = w * width / Double(columns)
                    let sway = 2 * .pi * t + phase
                    let crossing = level == nil ? 9 * scale * sin(2 * .pi * t) * activity : 0
                    let x = w * (1 - width) / 2 + crossing + (Double(column) + 0.45 + Double(row % 2) * 0.46
                        + (random.unit() - 0.5) * 0.42 + 0.48 * sin(sway) * activity) * spacing
                    let depth = ([6.9, 12.0, 19.0][row] + 3.0 * random.unit() + (level == nil ? 1.1 : 0)) * scale
                    let wave = level == nil ? 3.1 * scale * sin(2 * .pi * (t + x / w)) : 0
                    let py = y - (depth * (1 - 0.62 * settle) - wave - 1.4 * scale * cos(sway) * activity) * reach
                    let density = [0.82, 0.62, 0.49][row] + (level ?? 0.20) * 0.55
                    let fill = limit((density - random.unit()) * 3.8)
                    let radius = ([1.44, 1.02, 0.64][row] + 0.27 * random.unit()) * scale * (present ? 1.09 : 1)
                    let shimmer = 0.93 + 0.07 * sin(sway)
                    let brightness = [1.0, 0.92, 0.71][row] * (level == nil ? 0.83 : 1)
                    if row == 0, column.isMultiple(of: 2), let level, level > 0, level < 1 {
                        let fade = smooth(min(x, w - x) / (w * 0.24))
                        let ripple = 1.4 * (scale * (8.4 + cos(sway) * activity) - depth)
                        crest.append(Mote(center: CGPoint(x: x, y: y + ripple), radius: scale,
                                          opacity: 0.15 * fade * fill * activity * shimmer, kind: .crest))
                    }
                    dots.append(Mote(center: CGPoint(x: x, y: py), radius: radius,
                                     opacity: fill * activity * shimmer * brightness,
                                     kind: column.isMultiple(of: 3) ? .accent : .ink))
                }
            }
            return Frame(dots: crest + dots, bandY: y, bandOpacity: activity * (level == nil ? 0.96 : 1), centreOpacity: 0)

        case .completion, .fade:
            let still = scene == .fade
            let gather = still ? 1 : smooth(t / 0.48)
            let reveal = smooth(t / (still ? 0.13 : 0.18))
            let dissolve = 1 - smooth((t - (still ? 0.18 : 0.70)) / (still ? 0.82 : 0.30))
            let flash = still ? 0 : pulse(t, at: 0.58, width: 0.13)
            let glint = still ? 0 : pulse(t, at: 0.64, width: 0.12)
            let origin = bandY(sourceLevel.flatMap { $0.isFinite ? limit($0) : nil })
            let mark = present ? presentMark : fineMark
            let r = min(w, h) * 0.28
            let dots = mark.map { point in
                let x = w * 0.5 + (point.x * 0.36 + (random.unit() - 0.5) * 0.15) * w
                let y = max(2 * scale, origin - (3 + random.unit() * 20) * scale)
                let target = CGPoint(x: destination.x + point.x * r, y: destination.y + point.y * r)
                let bloom = point.kind == .star ? glint * 0.5 : point.kind == .accent ? flash * 0.18 : 0
                let radius = point.radius * scale * (0.76 + 0.24 * gather + bloom)
                let light = point.kind == .star ? 0.87 + 0.13 * glint
                    : min(1, point.light + (point.kind == .accent ? 0.28 * flash : 0))
                return Mote(center: CGPoint(x: x + (target.x - x) * gather, y: y + (target.y - y) * gather),
                            radius: radius, opacity: reveal * dissolve * light * (0.40 + 0.60 * gather),
                            kind: point.kind == .star && still ? .sun : point.kind)
            }
            return Frame(dots: dots, bandY: origin, bandOpacity: still ? 0 : reveal * (1 - gather),
                         centreOpacity: reveal * dissolve * (0.35 + 0.65 * gather))
        }
    }

    public static func edgeY(_ fraction: Double) -> Double { 1 - limit(fraction) }

    private struct MarkPoint {
        let x, y, radius, light: Double
        let kind: Mote.Kind
    }

    private static let fineMark = mark(present: false)
    private static let presentMark = mark(present: true)

    /// Sparse sampling of scripts/brand_icons.py: RIM = .86, cut_x(y) = .55 √(1 − y²),
    /// and trumpet(x) = .012 + .2 (|x| / end)^2.4. Keep the two fans empty at the sun.
    private static func mark(present: Bool) -> [MarkPoint] {
        let count = present ? 41 : 35
        var points: [MarkPoint] = (0..<count).compactMap { i in
            let a = 2 * .pi * (Double(i) + 0.5) / Double(count)
            if abs(cos(a)) < 0.07 { return nil } // the cut's tip already joins the rim here
            return MarkPoint(x: 0.95 * cos(a), y: 0.95 * sin(a),
                             radius: 0.94 + 0.54 * max(0, -cos(a)), light: 0.88, kind: .ink)
        }
        let cuts = present ? 28 : 24
        for i in 0..<cuts {
            let a = .pi * ((Double(i) + 0.5) / Double(cuts) - 0.5)
            let x = cos(a), y = sin(a)
            points.append(MarkPoint(x: 0.55 * x, y: y, radius: 0.78 + 0.79 * x, light: 0.78, kind: .accent))
            if i.isMultiple(of: 2) {
                points.append(MarkPoint(x: 0.72 * x, y: y * 0.92, radius: 0.55 + 0.70 * x, light: 0.69, kind: .accent))
            }
        }
        for end in [-0.86, 0.55] {
            let columns = end < 0 ? 6 : 5
            for i in 0..<columns {
                let distance = (Double(i) + 1) / Double(columns + 1)
                let x = end * distance
                let spread = 0.012 + 0.2 * pow(distance, 2.4)
                for row in (i < 2 ? 0...0 : -1...1) {
                    points.append(MarkPoint(x: x, y: spread * Double(row), radius: 0.62 + distance * 0.80,
                                            light: row == 0 ? 1 : 0.86, kind: .ink))
                }
            }
        }
        points.append(MarkPoint(x: 0, y: 0, radius: 2.20, light: 1, kind: .star))
        return points
    }

    private static func limit(_ x: Double) -> Double { min(max(x, 0), 1) }
    private static func smooth(_ x: Double) -> Double { let p = limit(x); return p * p * (3 - 2 * p) }
    private static func pulse(_ x: Double, at: Double, width: Double) -> Double { smooth(1 - abs(x - at) / width) }
}
