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

    var sourceLevel: Double? {
        switch self {
        case .running(_, let level): level
        case .verifying(_, let level): level ?? 1
        default: 1
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
    var scrimsOnly = false
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
    var title: CGRect? = nil
    private static let intensity: DownloadCloudMotion.Intensity = .fine

    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.seleneBackdropStyle) private var backdrop
    @Environment(\.downloadCloudCapture) private var capture
    @State private var cue: (scene: DownloadCloudMotion.Scene, start: Double, sourceLevel: Double?)?

    var body: some View {
        Group {
            if let capture {
                if !capture.before, let scene = stillFront ?? state.scene(after: capture.previous, reduceMotion: reduceMotion) {
                    snapshot(scene, at: stillFront == nil ? capture.time : 0, seed: capture.seed,
                             intensity: capture.intensity, sourceLevel: capture.previous.flatMap { $0.sourceLevel },
                             scrimsOnly: capture.scrimsOnly)
                }
            } else if let stillFront {
                snapshot(stillFront, at: 0, seed: seed, intensity: Self.intensity, sourceLevel: nil)
            } else if let cue = liveCue {
                DownloadCloudLive(
                    input: .init(scene: cue.scene, start: cue.start, colors: .init(backdrop.palette),
                                 seed: seed, intensity: Self.intensity, title: title, sourceLevel: cue.sourceLevel))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: state) { old, new in
            if case .verifying = old, case .verifying = new { return }
            cue = new.scene(after: old, reduceMotion: reduceMotion).flatMap {
                $0.repeats ? nil : ($0, CACurrentMediaTime(), old.sourceLevel)
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced, cue?.scene != .fade { cue = nil }
        }
        .onDisappear { cue = nil }
    }

    private var seed: UInt64 {
        withUnsafeBytes(of: id.uuid) { $0.prefix(8).reduce(0) { ($0 << 8) | UInt64($1) } }
    }

    private var stillFront: DownloadCloudMotion.Scene? {
        guard reduceMotion, case .running(_, let fraction?) = state else { return nil }
        return .drift(fraction)
    }

    private func snapshot(_ scene: DownloadCloudMotion.Scene, at time: Double, seed: UInt64,
                          intensity: DownloadCloudMotion.Intensity, sourceLevel: Double?,
                          scrimsOnly: Bool = false) -> some View {
        let sprites = DownloadCloudSprites(.init(backdrop.palette))
        return Canvas { context, size in
            let frame = DownloadCloudMotion.frame(scene, seed: seed, at: time, intensity: intensity, size: size,
                                                  sourceLevel: sourceLevel)
            context.withCGContext { cg in
                if let title {
                    cg.addPath(DownloadCloudSprites.titleMask(size, title))
                    cg.clip(using: .evenOdd)
                }
                for (image, rect, opacity) in sprites.scrims(frame, size) where opacity > 0 {
                    // Canvas draws CGImage in its y-down context; Core Animation draws its contents upright.
                    cg.saveGState()
                    cg.setAlpha(opacity)
                    cg.translateBy(x: 0, y: 2 * rect.midY)
                    cg.scaleBy(x: 1, y: -1)
                    cg.draw(image, in: rect)
                    cg.restoreGState()
                }
                for mote in frame.dots where mote.opacity > 0 && (!scrimsOnly || mote.kind == .crest) {
                    cg.setAlpha(mote.opacity)
                    cg.draw(sprites.image(mote), in: DownloadCloudSprites.rect(mote))
                }
            }
        }
    }

    private var liveCue: (scene: DownloadCloudMotion.Scene, start: Double, sourceLevel: Double?)? {
        if case .running = state {
            return state.scene(after: nil, reduceMotion: reduceMotion).map { ($0, 0, nil) }
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
    let ink, accent: UInt32
    init(_ palette: SelenePalette) {
        ink = palette.ink
        accent = palette.mode == .light ? palette.focus : palette.glyph
    }
}

/// The compositor and raster probe share the same luminous textures and local scrims.
struct DownloadCloudSprites {
    let ink, accent, sun, star: CGImage
    private static let band = makeBand()
    private static let crest = raster(64) { cg, size in
        radial(cg, size, rgb: [0xFFFFFF, 0xFFFFFF, 0xFFFFFF], alpha: [1, 0.55, 0],
               locations: [0, 0.42, 1])
    }
    private static let centre = raster(128) { cg, size in
        radial(cg, size, rgb: [0, 0, 0, 0], alpha: [0.53, 0.52, 0.32, 0],
               locations: [0, 0.54, 0.75, 1])
    }

    init(_ colors: DownloadCloudColors) {
        ink = Self.sprite(halo: Self.luminous(colors.ink))
        accent = Self.sprite(halo: Self.luminous(colors.accent))
        sun = Self.sprite(halo: 0xF4CE8E, warm: true)
        star = Self.sprite(halo: 0xF4CE8E, warm: true, rays: true)
    }

    func image(_ mote: DownloadCloudMotion.Mote) -> CGImage {
        switch mote.kind {
        case .ink: ink
        case .accent: accent
        case .sun: sun
        case .star: star
        case .crest: Self.crest
        }
    }

    static func rect(_ mote: DownloadCloudMotion.Mote) -> CGRect {
        if mote.kind == .crest {
            return CGRect(x: mote.center.x - 9 * mote.radius, y: mote.center.y - 4 * mote.radius,
                          width: 18 * mote.radius, height: 8 * mote.radius)
        }
        let extent = mote.radius * 2.8
        return CGRect(x: mote.center.x - extent, y: mote.center.y - extent,
                      width: extent * 2, height: extent * 2)
    }

    func scrims(_ frame: DownloadCloudMotion.Frame, _ size: CGSize) -> [(CGImage, CGRect, Double)] {
        let side = min(size.width, size.height)
        let extent = side * 0.49
        let bandHeight = side / 170 * 44
        return [
            (Self.band, CGRect(x: 0, y: frame.bandY - side / 170 * 34, width: size.width, height: bandHeight),
             frame.bandOpacity),
            (Self.centre, CGRect(x: size.width * 0.5 - extent, y: size.height * 0.46 - extent,
                                 width: extent * 2, height: extent * 2), frame.centreOpacity),
        ]
    }

    static func titleMask(_ size: CGSize, _ title: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: size))
        path.addRoundedRect(in: title.insetBy(dx: -4, dy: -3), cornerWidth: 3, cornerHeight: 3)
        return path
    }

    private static func sprite(halo: UInt32, warm: Bool = false, rays: Bool = false) -> CGImage {
        raster(64) { cg, size in
            let core: UInt32 = warm ? 0xFFF7E3 : 0xF9FCFF
            radial(cg, size, rgb: [0xFFFFFF, core, halo, halo], alpha: [1, 1, warm ? 0.30 : 0.23, 0],
                   locations: warm ? [0, 0.22, 0.49, 1] : [0, 0.37, 0.61, 1])
            guard rays else { return }
            let m = size / 2
            for reach in [m * 0.96, m * 0.82] {
                cg.beginPath()
                cg.move(to: CGPoint(x: m - reach, y: m))
                cg.addLines(between: [CGPoint(x: m - reach, y: m), CGPoint(x: m, y: m - 1.65),
                                      CGPoint(x: m + reach, y: m), CGPoint(x: m, y: m + 1.65)])
                cg.closePath()
                cg.setFillColor(color(0xFFF3DC, 0.86))
                cg.fillPath()
                cg.translateBy(x: m, y: m)
                cg.rotate(by: .pi / 2)
                cg.translateBy(x: -m, y: -m)
            }
        }
    }

    private static func makeBand() -> CGImage {
        raster(128) { cg, size in
            let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
            func gradient(_ alpha: [Double], _ loc: [CGFloat]) -> CGGradient {
                CGGradient(colorsSpace: rgb, colors: alpha.map { color(0, $0) } as CFArray, locations: loc)!
            }
            cg.drawLinearGradient(gradient([0, 0.05, 0.29, 0.62, 0.64, 0.56, 0.24, 0],
                                           [0, 0.16, 0.33, 0.51, 0.66, 0.73, 0.84, 1]),
                                  start: CGPoint(x: 0, y: size), end: .zero, options: [])
            cg.setBlendMode(.destinationIn)
            cg.drawLinearGradient(gradient([0, 0.20, 0.76, 1, 1, 0.76, 0.20, 0],
                                           [0, 0.03, 0.07, 0.14, 0.86, 0.93, 0.97, 1]),
                                  start: .zero, end: CGPoint(x: size, y: 0), options: [])
        }
    }

    private static func luminous(_ rgb: UInt32) -> UInt32 {
        [16, 8, 0].reduce(0) { $0 | ((3 * 255 + (rgb >> $1 & 255)) / 4) << $1 }
    }

    private static func radial(_ cg: CGContext, _ size: CGFloat, rgb: [UInt32], alpha: [Double],
                               locations: [CGFloat]) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = zip(rgb, alpha).map(color)
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
        let center = CGPoint(x: size / 2, y: size / 2)
        cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                              endRadius: size / 2, options: [])
    }

    private static func color(_ rgb: UInt32, _ alpha: Double) -> CGColor {
        CGColor(srgbRed: Double(rgb >> 16 & 255) / 255, green: Double(rgb >> 8 & 255) / 255,
                blue: Double(rgb & 255) / 255, alpha: alpha)
    }

    private static func raster(_ size: Int, _ draw: (CGContext, CGFloat) -> Void) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context, CGFloat(size))
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
        var title: CGRect? = nil
        var sourceLevel: Double? = nil
    }

    var input: Input? { didSet { if oldValue != input { needsLayout = true } } }
    private let field = CALayer()
    private var applied: Input?
    private var appliedSize: CGSize = .zero
    private var appliedBandY: Double = 0
    private var sprites: DownloadCloudSprites?
    private var spriteColors: DownloadCloudColors?
    private var generation = 0

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
        generation &+= 1
        Self.withoutActions {
            for dot in field.sublayers ?? [] {
                dot.removeAllAnimations()
                dot.removeFromSuperlayer()
            }
            field.removeAllAnimations()
            root.mask = nil
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
        let previousY = appliedBandY
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
        let steps = scene.repeats ? 20 : 32
        let times = (0...steps).map { Double($0) / Double(steps) }
        let frames = times.map {
            DownloadCloudMotion.frame(scene, seed: input.seed, at: min($0 * duration, duration.nextDown),
                                      intensity: input.intensity, size: size, sourceLevel: input.sourceLevel)
        }
        appliedBandY = frames[0].bandY
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
        if !scene.repeats {
            let generation = generation
            CATransaction.setCompletionBlock { [weak self] in
                // Install before adding animation tracks; a cancelled cue cannot clear the next transfer.
                guard self?.generation == generation else { return }
                self?.clear()
            }
        }
        if let title = input.title {
            let mask = CAShapeLayer()
            mask.frame = CGRect(origin: .zero, size: size)
            mask.path = DownloadCloudSprites.titleMask(size, title)
            mask.fillRule = .evenOdd
            root.mask = mask
        }
        func sprite(_ image: CGImage, _ rect: CGRect, _ opacity: Float = 0) -> CALayer {
            let layer = CALayer()
            layer.contents = image
            layer.frame = rect
            layer.opacity = opacity
            field.addSublayer(layer)
            return layer
        }
        func animate(_ layer: CALayer, _ tracks: [CAKeyframeAnimation]) {
            let animation = CAAnimationGroup()
            animation.animations = tracks
            animation.beginTime = start
            animation.duration = duration
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            if scene.repeats { animation.repeatCount = .infinity }
            layer.add(animation, forKey: "cloud")
        }
        let scrims = frames.map { sprites.scrims($0, size) }
        for (index, (image, rect, opacity)) in scrims[0].enumerated() {
            let alphas = scrims.map { $0[index].2 }
            guard alphas.contains(where: { $0 > 0 }) else { continue }
            let layer = sprite(image, rect, scene.repeats ? Float(opacity) : 0)
            if !scene.repeats { animate(layer, [keyframes("opacity", alphas.map { NSNumber(value: $0) })]) }
        }
        for (index, mote) in frames[0].dots.enumerated() {
            let samples = frames.map { $0.dots[index] }
            guard samples.contains(where: { $0.opacity > 0 }) else { continue }
            let first = DownloadCloudSprites.rect(mote)
            let dot = sprite(sprites.image(mote), first)
            var tracks = [keyframes("opacity", samples.map { NSNumber(value: $0.opacity) })]
            if scene != .fade {
                tracks.append(keyframes("position", samples.map { NSValue(point: $0.center) }))
            }
            if scene == .completion {
                tracks.append(keyframes("transform.scale", samples.map { NSNumber(value: $0.radius / mote.radius) }))
            }
            animate(dot, tracks)
        }
        if sameSize, case .drift(let old?) = previous?.scene, case .drift(let new?) = scene, old != new {
            // Follow the cover's existing quarter-second ease-out after a real byte update.
            let shift = CABasicAnimation(keyPath: "position.y")
            shift.fromValue = oldY + previousY - appliedBandY
            shift.toValue = 0
            shift.duration = 0.25
            shift.timingFunction = CAMediaTimingFunction(name: .easeOut)
            field.add(shift, forKey: "fill")
        }
        CATransaction.commit()
    }
}
