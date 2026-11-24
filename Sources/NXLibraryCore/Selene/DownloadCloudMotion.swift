import Foundation

/// Coordinates and radii are in local tile points; drift time is on the shared clock.
public enum DownloadCloudMotion {
    public enum Intensity: String, CaseIterable { case fine, present }
    public enum WaveHeight: String, CaseIterable {
        case calm, lively

        public static let selected: Self = .calm
        var amplitude: Double { self == .calm ? 5.4 : 7.8 }
    }

    public struct Surface {
        public let level: Double?
        public let energy: Double
        public let activity: Double
        public let phase: Double
        public let height: WaveHeight

        public func y(at x: Double, in size: CGSize) -> Double {
            let y = size.height * (1 - (level ?? 0.50))
            let u = x / size.width - 0.5
            let scale = min(size.width, size.height) / 170
            let room = min(1, min(y, size.height - y) / (16 * scale))
            let a = 2 * Double.pi * (u * 1.10 - phase / 5.6) + 0.3
            let b = 2 * Double.pi * (u * 1.93 + phase / 8.7) - 0.5
            // Subtract each wave's mean across the glass: height still measures the bytes.
            let ripple = 0.77 * (sin(a) - sin(a - 2 * .pi * u * 1.10) * sin(.pi * 1.10) / (.pi * 1.10))
                + 0.23 * (sin(b) - sin(b - 2 * .pi * u * 1.93) * sin(.pi * 1.93) / (.pi * 1.93))
            return y + scale * room * height.amplitude * energy * ripple
        }
    }

    /// The live track ends by itself if progress stops. Reduced motion never schedules a track.
    public static let quietAfter = 3.6

    public static func surface(_ scene: Scene, at phase: Double, elapsed: Double? = nil,
                               from previous: Surface? = nil, reduced: Bool = false,
                               height: WaveHeight = .selected) -> Surface? {
        let level: Double?, energy: Double, activity: Double
        switch scene {
        case .drift(let fraction):
            let target = fraction.flatMap { $0.isFinite ? limit($0) : nil }
            let t = max(0, elapsed ?? 0)
            let climb = 1 - pow(1 - limit(t / 0.38), 3)
            let from = previous?.level ?? target
            level = target.map { (from ?? $0) + ($0 - (from ?? $0)) * (reduced ? 1 : climb) }
            let rest = 1 - smooth((t - 2.55) / (quietAfter - 2.55))
            let momentum = min(0.25, abs((target ?? 0) - (from ?? 0)) * 0.70)
            let swell = momentum * pulse(t, at: 0.32, width: 0.32)
            let base = target == nil ? 0.58 : 1
            let wake = elapsed == nil ? 1 : smooth(t / 0.32)
            energy = reduced ? 0.24 : rest * ((previous?.energy ?? 0) * (1 - wake) + base * wake + swell)
            activity = reduced ? 0.80 : rest * ((previous?.activity ?? 0) * (1 - wake) + wake)
        case .settle(let fraction):
            let p = smooth(max(0, elapsed ?? phase) / scene.duration)
            level = fraction.map { target in
                let from = previous?.level ?? target
                return from + (target - from) * (reduced ? 1 : p)
            }
            energy = reduced ? 0 : (previous?.energy ?? 1) * (1 - p)
            activity = reduced ? 0 : (previous?.activity ?? 1) * (1 - p)
        case .completion, .fade: return nil
        }
        return Surface(level: level, energy: energy, activity: activity, phase: reduced ? 0 : phase, height: height)
    }

    public enum Scene: Equatable {
        case drift(Double?)
        case settle(Double?)
        case completion
        case fade

        public var duration: Double {
            switch self {
            case .drift: DownloadCloudMotion.quietAfter
            case .settle: 0.55
            case .completion: 1.20
            case .fade: 0.48
            }
        }

        public var isDrift: Bool { if case .drift = self { true } else { false } }
    }

    public struct Mote: Equatable {
        public enum Kind { case ink, accent, bubble, sun, star }
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
                             size: CGSize, sourceLevel: Double? = 1, surface live: Surface? = nil) -> Frame {
        let empty = Frame(dots: [], bandY: 0, bandOpacity: 0, centreOpacity: 0)
        guard time.isFinite, size.width > 0, size.height > 0 else { return empty }
        let t = limit(time / scene.duration)
        guard scene.isDrift || (time >= 0 && t < 1) else { return empty }
        let w = size.width, h = size.height
        let scale = min(w, h) / 170
        let present = intensity == .present
        let destination = CGPoint(x: w * 0.5, y: h * 0.46)
        var random = SplitMix(seed: seed)

        func bandY(_ level: Double?) -> Double {
            level.map { max(6 * scale, h * edgeY($0)) } ?? h * 0.56
        }

        switch scene {
        case .drift, .settle:
            guard let surface = live ?? surface(scene, at: time) else { return empty }
            let level = surface.level
            let y = surface.y(at: w / 2, in: size)
            let width = level == nil ? 0.74 : 0.88
            let columns = present ? 19 : 16
            let activity = surface.activity
            let clock = surface.phase / 5.6
            var dots = [Mote]()
            for row in 0..<2 {
                for column in 0..<columns {
                    let phase = 2 * .pi * random.unit()
                    let spacing = w * width / Double(columns)
                    let sway = 2 * .pi * clock + phase
                    let jitter = (random.unit() - 0.5) * 0.83 + 0.23 * sin(sway) * activity
                    let cycles = clock * 1.7 + phase / (2 * .pi)
                    let bubble = cycles - floor(cycles)
                    let x = w * (1 - width) / 2 + (Double(column) + 0.45 + jitter) * spacing
                    let crest = surface.y(at: x, in: size)
                    let depth = row == 0 ? 3.0 + 2.0 * random.unit() : 4 + 18 * bubble
                    let py = max(2.5 * scale, crest - depth * scale)
                    let radius = (row == 0 ? 0.98 + 0.51 * random.unit() : 0.62) * scale * (present ? 1.09 : 1)
                    let shimmer = row == 0 ? 0.967 + 0.033 * sin(sway) : 0.64 * sin(.pi * bubble)
                    let visible = row == 0 || column.isMultiple(of: 3)
                    let reach = row == 0 ? 1 : smooth(crest / (17 * scale))
                    dots.append(Mote(center: CGPoint(x: x, y: py), radius: radius,
                                     opacity: visible ? reach * activity * shimmer : 0,
                                     kind: row == 0 ? (column.isMultiple(of: 3) ? .accent : .ink) : .bubble))
                }
            }
            return Frame(dots: dots, bandY: y, bandOpacity: activity, centreOpacity: 0)

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
