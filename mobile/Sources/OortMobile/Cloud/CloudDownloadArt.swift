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
            art.saturation(0).opacity(SeleneTokens.Effect.panelVeil)
            art.mask { Canvas { context, size in fill(sample, size, &context) } }
            Canvas { context, size in
                if sample.surface.activity > 0 {
                    context.stroke(CloudFront.path(sample.surface, size), with: .color(Oort.focus.opacity(CloudFront.lineOpacity(sample.surface))), lineWidth: 1)
                    dots(DownloadCloudMotion.frame(.drift(sample.surface.level), seed: seed, at: sample.surface.phase, size: size, surface: sample.surface), &context)
                }
                if let time = sample.celebration {
                    dots(DownloadCloudMotion.frame(reduced ? .fade : .completion, seed: seed, at: time, size: size), &context)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(_ sample: DownloadCloudMotion.Sample, _ size: CGSize, _ context: inout GraphicsContext) {
        guard !sample.bands.isEmpty else { return context.fill(CloudFront.path(sample.surface, size, fill: true), with: .color(Oort.focus)) }
        var bottom = 1.0
        for band in sample.bands {
            let top = 1 - band.level
            context.fill(Path(CGRect(x: 0, y: top * size.height, width: size.width, height: (bottom - top) * size.height)), with: .color(Oort.focus.opacity(band.opacity)))
            bottom = top
        }
    }

    private func dots(_ frame: DownloadCloudMotion.Frame, _ context: inout GraphicsContext) {
        for mote in frame.dots where mote.opacity > 0 {
            let sun = mote.kind == .sun || mote.kind == .star
            let halo = sun ? Oort.sun : mote.kind == .ink ? Oort.ink : Oort.glyph
            let reach = mote.radius * CloudFront.spriteReach
            let rect = CGRect(x: mote.center.x - reach, y: mote.center.y - reach, width: reach * 2, height: reach * 2)
            context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [halo.opacity(SeleneTokens.Effect.panelVeil * mote.opacity), .clear]), center: mote.center, startRadius: 0, endRadius: reach))
            let core = mote.radius
            context.fill(Path(ellipseIn: CGRect(x: mote.center.x - core, y: mote.center.y - core, width: core * 2, height: core * 2)),
                         with: .color((sun ? Oort.sun : Oort.focus).opacity(mote.opacity)))
        }
    }
}

/// The Mac's front (`DownloadCloudFront`): the same curve through the same seventeen points.
enum CloudFront {
    /// A dot's light reaches this many radii (`DownloadCloudSprites.rect`).
    static let spriteReach = 2.8

    static func lineOpacity(_ surface: DownloadCloudMotion.Surface) -> Double {
        guard let level = surface.level else { return 0 }
        let edge = min(1, min(level, 1 - level) * 40)
        return edge * edge * (3 - 2 * edge) * 0.71 * surface.activity
    }

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
                    OortTileBadge(symbol: symbol)
                }
            }
            .modifier(OortTileChrome(shape: shape, ring: focused))
    }

    @ViewBuilder private var face: some View {
        if let artwork { artwork.view } else {
            // While it comes, what is here is lit: there is no picture to show it.
            OortLetter(title: game.build.name, side: side, lit: level != nil)
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
