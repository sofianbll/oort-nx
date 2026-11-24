import AppKit
import ArcanePorting
import NXLibraryCore
import SwiftUI

/// Keeps the phase and the real success event that the cover's numeric look cannot carry.
enum DownloadCloudTileState: Equatable {
    case idle, waiting(CloudLibraryItem), running(CloudLibraryItem, Double?)
    case verifying(CloudLibraryItem, Double?), completed(CloudLibraryItem)

    init(_ state: CloudLibraryState?, buildLook: PortingTileLook) {
        self = .idle
        guard buildLook.isAtRest, let state, state.issue?.failed != true else { return }
        guard let action = state.action else {
            if let item = state.completedItem { self = .completed(item) }
            return
        }
        switch action {
        case .restore, .restoreBuildCache, .downloadSources: break
        case .upload, .free, .uploadSources: return
        }
        let item = action.item(during: state.progress)
        guard !state.queued else { self = .waiting(item); return }
        let fraction = CloudTransferPresentation.fraction(state.progress)
        switch state.progress?.phase {
        case .downloading: self = .running(item, fraction)
        case .verifying, .restoring: self = .verifying(item, state.progress?.downloadComplete == true ? 1 : fraction)
        case .readyToInstall, .preparing, nil: self = .waiting(item)
        case .uploading: break
        }
    }

    func scene(after previous: Self?, reduceMotion: Bool) -> DownloadCloudMotion.Scene? {
        switch self {
        case .running(_, let fraction):
            return reduceMotion ? nil : .drift(fraction)
        case .verifying(let item, let fraction):
            guard !reduceMotion, case .running(item, let lastFraction) = previous else { return nil }
            return .settle(fraction ?? lastFraction)
        case .completed(let item):
            switch previous {
            case .running(item, _), .verifying(item, _), .waiting(item):
                return reduceMotion ? .fade : .completion
            default: return nil
            }
        case .idle, .waiting: return nil
        }
    }
}

/// The same phase projection and particle sprites in the real tiles and the headless renderer.
struct DownloadCloudCapture {
    let seed: UInt64
    let time: Double
    let intensity: DownloadCloudMotion.Intensity
    var previous: DownloadCloudTileState?
    var before = false
}

private struct DownloadCloudCaptureKey: EnvironmentKey {
    static let defaultValue: DownloadCloudCapture? = nil
}

extension EnvironmentValues {
    var downloadCloudCapture: DownloadCloudCapture? {
        get { self[DownloadCloudCaptureKey.self] }
        set { self[DownloadCloudCaptureKey.self] = newValue }
    }
}

/// Lives above the flattened artwork and below the badge. No animation view is mounted at rest.
struct DownloadCloudOverlay: View {
    let state: DownloadCloudTileState
    let id: UUID
    let cornerRadius: CGFloat
    private static let intensity: DownloadCloudMotion.Intensity = .fine

    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.seleneBackdropStyle) private var backdrop
    @Environment(\.downloadCloudCapture) private var capture
    @State private var cue: (scene: DownloadCloudMotion.Scene, start: Double)?

    var body: some View {
        Group {
            if let capture {
                if !capture.before, let scene = state.scene(after: capture.previous, reduceMotion: reduceMotion) {
                    let colors = DownloadCloudColors(backdrop.palette)
                    let frame = DownloadCloudMotion.frame(scene, seed: capture.seed, at: capture.time,
                                                           intensity: capture.intensity)
                    Canvas { context, size in
                        let sprites = DownloadCloudSprites(colors)
                        context.withCGContext { cg in
                            for mote in frame where mote.opacity > 0 {
                                cg.setAlpha(mote.opacity)
                                cg.draw(sprites.image(mote), in: DownloadCloudSprites.rect(mote, size, scene))
                            }
                        }
                    }
                }
            } else if let cue = liveCue {
                DownloadCloudLive(
                    input: .init(scene: cue.scene, start: cue.start, colors: .init(backdrop.palette),
                                 seed: withUnsafeBytes(of: id.uuid) { $0.prefix(8).reduce(0) { ($0 << 8) | UInt64($1) } },
                                 intensity: Self.intensity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: state) { old, new in
            if case .verifying = old, case .verifying = new { return }
            cue = new.scene(after: old, reduceMotion: reduceMotion).flatMap {
                $0.repeats ? nil : ($0, CACurrentMediaTime())
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced, cue?.scene != .fade { cue = nil }
        }
        .onDisappear { cue = nil }
    }

    private var liveCue: (scene: DownloadCloudMotion.Scene, start: Double)? {
        if case .running = state {
            return state.scene(after: nil, reduceMotion: reduceMotion).map { ($0, 0) }
        }
        return cue
    }
}

private struct DownloadCloudLive: View {
    let input: DownloadCloudLayerView.Input
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.controlActiveState) private var windowState
    @State private var visible = false

    var body: some View {
        Group {
            if visible && windowState != .inactive {
                DownloadCloudLayers(input: input)
            } else {
                Color.clear
            }
        }
        .transition(.identity)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .global).intersects(CGRect(origin: .zero, size: canvas.size))
        } action: { visible = $0 }
    }
}

private struct DownloadCloudLayers: NSViewRepresentable {
    let input: DownloadCloudLayerView.Input
    func makeNSView(context: Context) -> DownloadCloudLayerView { DownloadCloudLayerView() }
    func updateNSView(_ view: DownloadCloudLayerView, context: Context) { view.input = input }
    static func dismantleNSView(_ view: DownloadCloudLayerView, coordinator: ()) { view.clear() }
}

struct DownloadCloudColors: Equatable {
    let ink, accent, halo: UInt32
    init(_ palette: SelenePalette) {
        ink = palette.mode == .light ? palette.glyph : palette.ink
        accent = palette.mode == .light ? palette.focus : palette.glyph
        halo = palette.mode == .light ? palette.ink : palette.scrim
    }
}

/// Small, mostly sharp Moonlight-style cores with a soft contrasting tail, not a blur of the art.
private struct DownloadCloudSprites {
    let ink, accent: CGImage
    init(_ colors: DownloadCloudColors) {
        ink = Self.sprite(colors.ink, halo: colors.halo)
        accent = Self.sprite(colors.accent, halo: colors.halo)
    }

    func image(_ mote: DownloadCloudMotion.Mote) -> CGImage { mote.accent ? accent : ink }

    static func rect(_ mote: DownloadCloudMotion.Mote, _ size: CGSize, _ scene: DownloadCloudMotion.Scene) -> CGRect {
        let side = min(size.width, size.height)
        let mark = scene == .completion || scene == .fade
        let x = mark ? size.width * 0.5 + side * (mote.center.x - 0.5) : size.width * mote.center.x
        let y = mark ? size.height * 0.48 + side * (mote.center.y - 0.48) : size.height * mote.center.y
        let radius = side * mote.radius * 2.5
        return CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)
    }

    private static func sprite(_ ink: UInt32, halo: UInt32) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func color(_ rgb: UInt32, _ alpha: Double) -> CGColor {
            CGColor(srgbRed: Double(rgb >> 16 & 255) / 255, green: Double(rgb >> 8 & 255) / 255,
                    blue: Double(rgb & 255) / 255, alpha: alpha)
        }
        let colors = [color(ink, 1), color(ink, 0.86), color(halo, 0.32), color(halo, 0)]
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.34, 0.54, 1])!
        let center = CGPoint(x: 16, y: 16)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: 16, options: [])
        return context.makeImage()!
    }
}

/// Keyframes are only resampled on a real progress/phase or size change; nothing wakes SwiftUI each frame.
final class DownloadCloudLayerView: TileMotionLayerView {
    struct Input: Equatable {
        let scene: DownloadCloudMotion.Scene
        let start: Double
        let colors: DownloadCloudColors
        let seed: UInt64
        let intensity: DownloadCloudMotion.Intensity
    }

    var input: Input? { didSet { if oldValue != input { needsLayout = true } } }
    private let field = CALayer()
    private var applied: Input?
    private var appliedSize: CGSize = .zero
    private var sprites: DownloadCloudSprites?
    private var spriteColors: DownloadCloudColors?

    override init() {
        super.init()
        field.anchorPoint = .zero
        root.addSublayer(field)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { clear() }
    }

    func clear() {
        Self.withoutActions {
            for dot in field.sublayers ?? [] {
                dot.removeAllAnimations()
                dot.removeFromSuperlayer()
            }
            field.removeAllAnimations()
        }
        applied = nil
    }

    override func arrange(scale: CGFloat) {
        guard let input, window != nil, !bounds.isEmpty else { clear(); return }
        apply(input, size: bounds.size, now: CACurrentMediaTime())
    }

    /// Kept independent of the window so the same scheduling can be exercised headlessly.
    func apply(_ input: Input, size: CGSize, now: Double) {
        guard applied != input || appliedSize != size else { return }
        let previous = applied
        let oldY = field.presentation()?.position.y ?? 0
        clear()
        applied = input
        let sameSize = size == appliedSize
        appliedSize = size
        let scene = input.scene
        let duration = scene.duration
        let elapsed = scene.repeats ? now.truncatingRemainder(dividingBy: duration) : max(0, now - input.start)
        guard elapsed < duration else { return }
        if spriteColors != input.colors || sprites == nil {
            sprites = DownloadCloudSprites(input.colors)
            spriteColors = input.colors
        }
        let sprites = sprites!
        let steps = scene.repeats ? 48 : 24
        let times = (0...steps).map { Double($0) / Double(steps) }
        let frames = times.map {
            DownloadCloudMotion.frame(scene, seed: input.seed, at: min($0 * duration, duration.nextDown),
                                      intensity: input.intensity)
        }
        let start = field.convertTime(now, from: nil) - elapsed
        func keyframes(_ key: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values
            animation.keyTimes = times.map { NSNumber(value: $0) }
            animation.duration = duration
            return animation
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, mote) in frames[0].enumerated() {
            guard frames.contains(where: { $0[index].opacity > 0 }) else { continue }
            let dot = CALayer()
            dot.contents = sprites.image(mote)
            dot.bounds.size = DownloadCloudSprites.rect(mote, size, scene).size
            dot.opacity = 0
            let samples = frames.map { $0[index] }
            var tracks = [keyframes("opacity", samples.map { NSNumber(value: $0.opacity) })]
            let path = samples.map { DownloadCloudSprites.rect($0, size, scene) }
            dot.position = CGPoint(x: path[0].midX, y: path[0].midY)
            if scene != .fade {
                tracks.append(keyframes("position", path.map { NSValue(point: CGPoint(x: $0.midX, y: $0.midY)) }))
            }
            field.addSublayer(dot)
            let animation = CAAnimationGroup()
            animation.animations = tracks
            animation.beginTime = start
            animation.duration = duration
            if scene.repeats { animation.repeatCount = .infinity }
            dot.add(animation, forKey: "cloud")
        }
        if sameSize, case .drift(let old?) = previous?.scene, case .drift(let new?) = scene, old != new {
            // Follow the cover's existing quarter-second ease-out after a real byte update.
            let shift = CABasicAnimation(keyPath: "position.y")
            shift.fromValue = oldY + size.height * (DownloadCloudMotion.edgeY(old) - DownloadCloudMotion.edgeY(new))
            shift.toValue = 0
            shift.duration = 0.25
            shift.timingFunction = CAMediaTimingFunction(name: .easeOut)
            field.add(shift, forKey: "fill")
        }
        if !scene.repeats, let first = field.sublayers?.first {
            CATransaction.setCompletionBlock { [weak self, weak first] in
                // A cancelled cue must not clear the particles of the next transfer.
                guard let first, self?.field.sublayers?.first === first else { return }
                self?.clear()
            }
        }
        CATransaction.commit()
    }
}
