import Foundation
import OortCore

/// Coordinates and radii are in local tile points; drift time is on the shared clock.
public enum DownloadCloudMotion {
    public struct Surface {
        public let level: Double?
        public let energy: Double
        public let activity: Double
        public let phase: Double

        public func y(at x: Double, in size: CGSize) -> Double {
            let y = size.height * (1 - (level ?? 0.50))
            let u = x / size.width - 0.5
            let scale = min(size.width, size.height) / 170
            let room = ease(min(y, size.height - y) / (16 * scale))
            let a = 2 * Double.pi * (u * 1.10 - phase / 5.6) + 0.3
            let b = 2 * Double.pi * (u * 1.93 + phase / 8.7) - 0.5
            // Subtract each wave's mean across the glass: height still measures the bytes.
            let ripple = 0.77 * (sin(a) - sin(a - 2 * .pi * u * 1.10) * sin(.pi * 1.10) / (.pi * 1.10))
                + 0.23 * (sin(b) - sin(b - 2 * .pi * u * 1.93) * sin(.pi * 1.93) / (.pi * 1.93))
            return y + scale * room * 5.4 * energy * ripple
        }
    }

    public enum Scene: Equatable {
        case drift(Double?)
        case settle(Double?)
        case verify(Double?)
        case completion
        case fade

        public var level: Double? {
            switch self {
            case .drift(let level), .settle(let level), .verify(let level):
                level.flatMap { $0.isFinite ? limit($0) : nil }
            case .completion, .fade: 1
            }
        }

        public var duration: Double {
            switch self {
            case .completion: 1.20
            case .fade: 0.48
            default: 0
            }
        }

        public var isDrift: Bool { if case .drift = self { true } else { false } }
        var isSuccess: Bool { self == .completion || self == .fade }
    }

    public struct Band {
        public let level: Double
        public let opacity: Double
    }

    public struct Sample {
        public let surface: Surface
        public let opacity: Double
        public let bands: [Band]
        public let celebration: Double?
    }

    /// Finite critical damping: three identical real poles, with the last tail eased to exactly zero.
    /// Each earned increment owns its response; another report adds a zero-position/speed/acceleration
    /// term instead of restarting the moving front. The sum never spends unreported bytes.
    public struct Track {
        private static let lift = 3.2, stillFade = 0.52, waveEase = 2.0, silence = 1.4, restartFade = 0.8
        private var levels: Levels
        private var retiring: (levels: Levels, appeared: Double, fade: Double, at: Double)?
        private var appeared: Double
        private var appearanceDuration = 0.38
        private var wave = Ramp()
        private var sleep: Double?
        private var success: Double?
        private var scene: Scene
        private let reduced: Bool

        public init(_ scene: Scene, at time: Double, reduced: Bool = false, appear: Bool = true) {
            self.scene = scene
            self.reduced = reduced
            appeared = appear ? time : -.infinity
            levels = Levels(base: scene.level)
            if scene.isSuccess { success = time }
            if scene.isDrift && !reduced {
                wave.set(1, at: time, duration: Self.waveEase)
                sleep = time + Self.silence
            }
        }

        public mutating func receive(_ scene: Scene, at time: Double, restart: Bool = false, advanced: Bool = false) {
            let duration = reduced ? Self.stillFade : Self.lift
            if let old = retiring, time >= old.at + Self.restartFade { retiring = nil }
            // A revised total can also invalidate the old fraction without a byte-counter reset.
            let rewind = restart || (scene.isDrift && scene.level.map { $0 < (levels.target ?? $0) } == true)
            let resolved = !reduced && levels.base == nil && levels.steps.isEmpty && scene.level != nil
            if rewind || resolved {
                if retiring == nil {
                    retiring = (levels, appeared, appearanceDuration, time)
                    appeared = time + Self.restartFade
                    appearanceDuration = Self.restartFade
                }
                levels = Levels(base: rewind ? scene.level : 0)
            }
            if let level = scene.level { levels.add(level, at: max(time, appeared), duration: duration) }
            if !reduced {
                if let sleep, sleep <= time {
                    wave.set(0, at: sleep, duration: Self.waveEase)
                    self.sleep = nil
                }
                switch scene {
                case .drift:
                    if advanced || scene != self.scene || rewind {
                        wave.set(1, at: time, duration: Self.waveEase)
                        sleep = time + Self.silence
                    }
                case .verify where self.scene.isDrift && wave.target == 1:
                    sleep = max(time, levels.end(duration))
                case .settle where scene != self.scene:
                    wave.set(0, at: time, duration: Self.waveEase)
                    sleep = nil
                default: break
                }
            }
            if scene.isSuccess {
                if success == nil { success = max(time, levels.end(duration), appeared + appearanceDuration) }
                if wave.target == 1 { sleep = success }
            } else {
                success = nil
            }
            self.scene = scene
        }

        public var end: Double {
            max(appeared + appearanceDuration, levels.end(reduced ? Self.stillFade : Self.lift),
                wave.end(Self.waveEase), (sleep ?? -.infinity) + Self.waveEase,
                (success ?? -.infinity) + scene.duration)
        }

        public func sample(at time: Double) -> Sample {
            let duration = reduced ? Self.stillFade : Self.lift
            let beforeSwap = retiring.map { time < $0.at + Self.restartFade } ?? false
            let levelTrack = beforeSwap ? retiring!.levels : levels
            let opacity = beforeSwap
                ? ease((time - retiring!.appeared) / retiring!.fade) * (1 - ease((time - retiring!.at) / Self.restartFade))
                : ease((time - appeared) / appearanceDuration)
            let level = levelTrack.value(at: time, duration: duration, reduced: reduced)
            // A pending sleep is evaluated like a real event so a late update can wake mid-fade.
            var energy = wave.value(at: time, duration: Self.waveEase)
            if let sleep { energy -= ease((time - sleep) / Self.waveEase) }
            let cue = success.map { time - $0 }
            let activity = limit(energy) * (1 - ease((cue ?? 0) / 0.38))
            let surface = Surface(level: level, energy: limit(energy), activity: activity, phase: reduced ? 0 : time)
            return Sample(surface: surface, opacity: opacity,
                          bands: reduced ? levelTrack.bands(at: time, duration: duration) : [],
                          celebration: cue.flatMap { $0 >= 0 && $0 < scene.duration ? $0 : nil })
        }
    }

    private struct Ramp {
        var base = 0.0
        var target = 0.0
        var steps: [(at: Double, delta: Double)] = []

        mutating func set(_ target: Double, at time: Double, duration: Double) {
            guard target != self.target else { return }
            while let first = steps.first, time - first.at >= duration { base += steps.removeFirst().delta }
            steps.append((time, target - self.target))
            self.target = target
        }

        func end(_ duration: Double) -> Double { (steps.last?.at ?? -.infinity) + duration }
        func value(at time: Double, duration: Double) -> Double {
            steps.reduce(base) { $0 + $1.delta * ease((time - $1.at) / duration) }
        }
    }

    private struct Levels {
        var base: Double?
        var steps: [(at: Double, level: Double)] = []
        var target: Double? { steps.last?.level ?? base }

        mutating func add(_ level: Double, at time: Double, duration: Double) {
            guard level > (target ?? -1) else { return }
            while let first = steps.first, time - first.at >= duration { base = steps.removeFirst().level }
            if steps.last?.at == time { steps.removeLast() }
            steps.append((time, level))
        }

        func end(_ duration: Double) -> Double { (steps.last?.at ?? -.infinity) + duration }

        func value(at time: Double, duration: Double, reduced: Bool) -> Double? {
            guard base != nil || !steps.isEmpty else { return nil }
            var previous = base ?? 0, level = previous
            for step in steps {
                let t = max(0, time - step.at)
                let u = 2.05 * t
                let response = reduced ? ease(t / duration)
                    : t >= duration ? 1 : 1 - exp(-u) * (1 + u + u * u / 2) * (1 - ease((t - 1.8) / (duration - 1.8)))
                level += (step.level - previous) * response
                previous = step.level
            }
            return min(max(0, level), previous)
        }

        func bands(at time: Double, duration: Double) -> [Band] {
            var result = base.flatMap { $0 > 0 ? [Band(level: $0, opacity: 1)] : nil } ?? []
            for step in steps where step.level > 0 {
                let alpha = ease((time - step.at) / duration)
                if result.last?.opacity == alpha { result.removeLast() }
                result.append(Band(level: step.level, opacity: alpha))
            }
            return result
        }
    }

    public struct Mote: Equatable {
        public enum Kind: Sendable { case ink, accent, bubble, sun, star }
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

    public static func preview(_ scene: Scene, at time: Double, reduced: Bool = false) -> Sample {
        let moving = scene.isDrift && !reduced
        return Sample(surface: Surface(level: scene.level, energy: moving ? 1 : 0,
                                       activity: moving ? 1 : 0, phase: reduced ? 0 : time),
                      opacity: 1, bands: [], celebration: scene.isSuccess && time < scene.duration ? time : nil)
    }

    public static func frame(_ scene: Scene, seed: UInt64, at time: Double, size: CGSize, surface: Surface? = nil) -> Frame {
        let empty = Frame(dots: [], bandY: 0, bandOpacity: 0, centreOpacity: 0)
        guard time.isFinite, size.width > 0, size.height > 0 else { return empty }
        let w = size.width, h = size.height
        let scale = min(w, h) / 170
        let destination = CGPoint(x: w * 0.5, y: h * 0.46)
        var random = SplitMix(seed: seed)

        switch scene {
        case .drift, .settle, .verify:
            let surface = surface ?? preview(scene, at: time).surface
            let level = surface.level
            let y = surface.y(at: w / 2, in: size)
            let width = level == nil ? 0.74 : 0.88
            let columns = 16
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
                    let radius = (row == 0 ? 0.98 + 0.51 * random.unit() : 0.62) * scale
                    let shimmer = row == 0 ? 0.967 + 0.033 * sin(sway) : 0.64 * sin(.pi * bubble)
                    let visible = row == 0 || column.isMultiple(of: 3)
                    let reach = row == 0 ? 0.2 + 0.8 * ease(crest / (7 * scale)) : ease(crest / (17 * scale))
                    dots.append(Mote(center: CGPoint(x: x, y: py), radius: radius,
                                     opacity: visible ? reach * activity * shimmer : 0,
                                     kind: row == 0 ? (column.isMultiple(of: 3) ? .accent : .ink) : .bubble))
                }
            }
            return Frame(dots: dots, bandY: y, bandOpacity: activity, centreOpacity: 0)

        case .completion, .fade:
            guard time >= 0, time < scene.duration else { return empty }
            let t = time / scene.duration
            let still = scene == .fade
            let gather = still ? 1 : smooth(t / 0.48)
            let reveal = smooth(t / (still ? 0.13 : 0.18))
            let dissolve = 1 - smooth((t - (still ? 0.18 : 0.70)) / (still ? 0.82 : 0.30))
            let flash = still ? 0 : pulse(t, at: 0.58, width: 0.13)
            let glint = still ? 0 : pulse(t, at: 0.64, width: 0.12)
            let origin = 6 * scale
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

    private struct MarkPoint {
        let x, y, radius, light: Double
        let kind: Mote.Kind
    }

    /// Sparse sampling of scripts/brand_icons.py: RIM = .86, cut_x(y) = .55 √(1 − y²),
    /// and trumpet(x) = .012 + .2 (|x| / end)^2.4. Keep the two fans empty at the sun.
    private static let mark: [MarkPoint] = {
        let count = 35
        var points: [MarkPoint] = (0..<count).compactMap { i in
            let a = 2 * .pi * (Double(i) + 0.5) / Double(count)
            if abs(cos(a)) < 0.07 { return nil } // the cut's tip already joins the rim here
            return MarkPoint(x: 0.95 * cos(a), y: 0.95 * sin(a),
                             radius: 0.94 + 0.54 * max(0, -cos(a)), light: 0.88, kind: .ink)
        }
        let cuts = 24
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
    }()

    private static func limit(_ x: Double) -> Double { min(max(x, 0), 1) }
    private static func ease(_ x: Double) -> Double {
        let p = limit(x)
        return p * p * p * (10 + p * (-15 + 6 * p))
    }
    private static func smooth(_ x: Double) -> Double { let p = limit(x); return p * p * (3 - 2 * p) }
    private static func pulse(_ x: Double, at: Double, width: Double) -> Double { smooth(1 - abs(x - at) / width) }
}
