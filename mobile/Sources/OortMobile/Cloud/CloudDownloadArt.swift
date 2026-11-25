import OortCore
import SwiftUI

/// A tile filling with the Oort cloud while its game comes: the Mac's own motion (`DownloadCloudMotion`), drawn for the phone.
struct CloudDownloadArt<Art: View>: View {
    let seed: UInt64
    /// Nil: nothing under way.
    let level: Double?
    let moving: Bool
    let done: Bool
    let art: Art
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.oortStill) private var still
    @Environment(\.scenePhase) private var phase
    @State private var track: DownloadCloudMotion.Track?
    @State private var until = Date.distantPast
    @State private var wasActive = false

    private var reduced: Bool { reduceMotion || still }
    private var scene: DownloadCloudMotion.Scene? {
        if done { return wasActive ? (reduced ? .fade : .completion) : nil }
        return level.map { moving ? .drift($0) : .settle($0) }
    }

    var body: some View {
        Group {
            if let scene, let track {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: phase != .active || (reduced ? until < .now : !moving && until < .now))) { time in
                    let now = time.date.timeIntervalSinceReferenceDate
                    picture(scene, track.sample(at: now))
                }
            } else { art }
        }
        .onChange(of: scene, initial: true) { _, next in follow(next) }
    }

    private func follow(_ next: DownloadCloudMotion.Scene?) {
        guard let next else { track = nil; return }
        let now = Date.now.timeIntervalSinceReferenceDate
        if level != nil { wasActive = true }
        if track == nil { track = .init(next, at: now, reduced: reduced) } else { track?.receive(next, at: now, advanced: true) }
        until = Date(timeIntervalSinceReferenceDate: track?.end ?? now)
    }

    private func picture(_ scene: DownloadCloudMotion.Scene, _ sample: DownloadCloudMotion.Sample) -> some View {
        ZStack {
            art.saturation(0).opacity(0.34)
            art.mask { Canvas { context, size in fill(sample, size, &context) } }
            Canvas { context, size in
                if sample.surface.activity > 0 {
                    context.stroke(CloudFront.path(sample.surface, size), with: .color(.white.opacity(0.71 * sample.surface.activity)), lineWidth: 1)
                    dots(DownloadCloudMotion.frame(.drift(sample.surface.level), seed: seed, at: sample.surface.phase, size: size, surface: sample.surface), &context)
                }
                if let time = sample.celebration {
                    dots(DownloadCloudMotion.frame(reduced ? .fade : .completion, seed: seed, at: time, size: size), &context)
                }
            }
        }
        .opacity(sample.celebration == nil ? 1 : max(sample.opacity, 0.999))
        .accessibilityHidden(true)
    }

    private func fill(_ sample: DownloadCloudMotion.Sample, _ size: CGSize, _ context: inout GraphicsContext) {
        guard !sample.bands.isEmpty else { return context.fill(CloudFront.path(sample.surface, size, fill: true), with: .color(.white)) }
        var bottom = 1.0
        for band in sample.bands {
            let top = 1 - band.level
            context.fill(Path(CGRect(x: 0, y: top * size.height, width: size.width, height: (bottom - top) * size.height)), with: .color(.white.opacity(band.opacity)))
            bottom = top
        }
    }

    private func dots(_ frame: DownloadCloudMotion.Frame, _ context: inout GraphicsContext) {
        for mote in frame.dots where mote.opacity > 0 {
            let sun = mote.kind == .sun || mote.kind == .star
            let halo = sun ? Oort.sun : mote.kind == .ink ? Oort.ink : Oort.glyph
            let reach = mote.radius * 2.4
            let rect = CGRect(x: mote.center.x - reach, y: mote.center.y - reach, width: reach * 2, height: reach * 2)
            context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [halo.opacity(0.45 * mote.opacity), .clear]), center: mote.center, startRadius: 0, endRadius: reach))
            let core = mote.radius
            context.fill(Path(ellipseIn: CGRect(x: mote.center.x - core, y: mote.center.y - core, width: core * 2, height: core * 2)),
                         with: .color((sun ? Oort.sun : .white).opacity(mote.opacity)))
        }
    }
}

/// The Mac's front (`DownloadCloudFront`): the same curve through the same seventeen points.
enum CloudFront {
    static func path(_ surface: DownloadCloudMotion.Surface, _ size: CGSize, fill: Bool = false) -> Path {
        let dx = size.width / 16
        func y(_ x: Double) -> Double { surface.y(at: x, in: size) }
        func tangent(_ x: Double) -> Double { (y(x + dx / 8) - y(x - dx / 8)) * 4 / 3 }
        return Path { path in
            var y0 = y(0), m0 = tangent(0)
            path.move(to: CGPoint(x: 0, y: y0))
            for i in 1...16 {
                let b = Double(i) * dx, a = b - dx, y1 = y(b), m1 = tangent(b)
                path.addCurve(to: CGPoint(x: b, y: y1), control1: CGPoint(x: a + dx / 3, y: y0 + m0), control2: CGPoint(x: b - dx / 3, y: y1 - m1))
                (y0, m0) = (y1, m1)
            }
            guard fill else { return }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
    }
}

/// A game of the cloud: the picture it has here, or its letter on the halftone, as in the library.
struct CloudTile: View {
    let game: CloudModel.Game
    let cloud: CloudModel
    let artwork: GameArt?
    let side: CGFloat
    var focused = false

    struct GameArt { let view: AnyView }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Oort.tile, style: .continuous)
        CloudDownloadArt(seed: seed, level: level, moving: game.job?.state == .running, done: game.job?.state == .ready, art: face)
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay(alignment: .topTrailing) {
                if let symbol {
                    Image(systemName: symbol).font(.caption.weight(.bold)).dynamicTypeSize(...DynamicTypeSize.xLarge).foregroundStyle(Oort.ink)
                        .frame(width: 24, height: 24).background(Oort.night.opacity(0.85), in: .circle).padding(5)
                }
            }
            .overlay { shape.inset(by: -4).strokeBorder(Oort.focus, lineWidth: SeleneTokens.Space.focusStroke).opacity(focused ? 1 : 0) }
            .shadow(color: Oort.night.opacity(0.5), radius: 8, y: 3)
            .contentShape(shape)
    }

    @ViewBuilder private var face: some View {
        if let artwork { artwork.view } else {
            ZStack {
                LinearGradient(colors: [Oort.panelRaised, Oort.panelLow], startPoint: .top, endPoint: .bottom)
                // While it comes, what is here is lit: there is no picture to show it.
                if level != nil { Oort.cloud.opacity(0.35) }
                OortDots(rise: 1, color: Oort.glyph.opacity(0.12))
                Text(String(game.build.name.prefix(1))).font(.system(size: side * 0.4, weight: .semibold)).foregroundStyle(Oort.ink)
            }
        }
    }

    private var level: Double? {
        guard let job = game.job, job.state != .ready else { return nil }
        return job.build.bytes > 0 ? Double(cloud.received(job)) / Double(job.build.bytes) : 0
    }

    private var symbol: String? {
        switch game.job?.state {
        case .running: "arrow.down"
        case .waiting: "hourglass"
        case .paused: "pause.fill"
        case .failed: "exclamationmark"
        case .ready: "square.and.arrow.down"
        case nil: game.isInstalled ? nil : game.installedVersion != nil ? "arrow.up" : "cloud"
        }
    }

    private var seed: UInt64 { UInt64(game.id, radix: 16) ?? 0 }
}
