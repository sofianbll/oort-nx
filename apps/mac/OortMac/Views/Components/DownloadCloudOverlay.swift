import AppKit
import NxnativeAdapter
import OortLibrary
import SwiftUI

/// Keeps the phase and the real success event that the cover's numeric look cannot carry.
enum DownloadCloudTileState: Equatable {
    case idle, waiting(CloudLibraryItem, complete: Bool = false), running(CloudLibraryItem, Double?)
    case verifying(CloudLibraryItem, Double?), completed(CloudLibraryItem)
    case interrupted(CloudLibraryItem), holding(CloudLibraryItem, Double?)

    init(_ state: CloudLibraryState?, buildLook: PortingTileLook) {
        self = .idle
        guard buildLook.isAtRest, let state else { return }
        if let issue = state.issue, issue.failed { self = .interrupted(issue.item); return }
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
        case .readyToInstall: self = .waiting(item, complete: state.progress?.downloadComplete == true)
        case .preparing, nil: self = .waiting(item)
        case .uploading: break
        }
    }

    var item: CloudLibraryItem? {
        switch self {
        case .running(let item, _), .verifying(let item, _), .holding(let item, _),
             .completed(let item), .waiting(let item, _), .interrupted(let item): item
        case .idle: nil
        }
    }

    func completes(_ previous: Self?) -> Bool {
        guard case .completed(let item) = self else { return false }
        switch previous {
        case .running(item, _), .verifying(item, _), .waiting(item, _), .holding(item, _): return true
        default: return false
        }
    }

    var fillScene: DownloadCloudMotion.Scene? {
        switch self {
        case .running(_, let fraction): .drift(fraction)
        case .holding(_, let fraction): .settle(fraction)
        case .verifying(_, let fraction): .verify(fraction)
        default: nil
        }
    }

    func hold(after previous: Self?) -> Self? {
        guard let item else { return nil }
        switch previous {
        case .running(item, let fraction), .verifying(item, let fraction), .holding(item, let fraction):
            switch self {
            case .waiting(_, complete: true): return .holding(item, 1)
            case .waiting, .interrupted: return .holding(item, fraction)
            case .verifying(_, nil): return .verifying(item, fraction)
            default: return nil
            }
        default: return nil
        }
    }
}

/// The same phase projection and particle sprites in the real tiles and the headless renderer.
struct DownloadCloudCapture {
    let seed: UInt64
    let time: Double
    var previous: DownloadCloudTileState?
    var before = false
    var scrimsOnly = false
    var artOnly = false
    var sample: DownloadCloudMotion.Sample? = nil
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

/// The loading view owns the art. Only an active download puts a second, masked copy over its grey face.
struct DownloadCloudTileStyle {
    let state: CloudLibraryState?
    let buildLook: PortingTileLook
    let cornerRadius: CGFloat
    var backplateRadius: CGFloat? = nil
}

struct DownloadCloudArtRevision: Equatable {
    let images: [NSImage?]
    var title: String? = nil
    var glass: UInt32 = 0
}

struct DownloadCloudArt<Art: View>: View {
    let art: Art
    let style: DownloadCloudTileStyle
    let id: UUID
    let revision: DownloadCloudArtRevision

    @Environment(\.downloadCloudCapture) private var capture
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var lastPhase: DownloadCloudTileState?
    @State private var completedHere = false

    var body: some View {
        let current = DownloadCloudTileState(style.state, buildLook: style.buildLook)
        let phase = current.hold(after: capture?.previous ?? lastPhase) ?? current
        let completing = phase.completes(capture?.previous ?? lastPhase) || (phase == lastPhase && completedHere)
        let scene = phase.fillScene ?? (completing ? (reduceMotion ? .fade : .completion) : nil)
        let look = scene != nil && capture?.before != true
            ? PortingTileLook.transfer(0) : (style.state?.coverLook(style.buildLook) ?? style.buildLook)
        ZStack {
            if let radius = style.backplateRadius {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(SeleneTheme.ink15)
            }
            art.portingLook(look, cornerRadius: style.cornerRadius)
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
            .drawingGroup()
            .oortShadow(.tile)
            .overlayPreferenceValue(BoxArtTitleBounds.self) { anchor in
                if let scene, capture?.before != true {
                    GeometryReader { proxy in
                        DownloadCloudOverlay(scene: scene, item: phase.item, id: id, cornerRadius: style.cornerRadius,
                                             title: anchor.map { proxy[$0] },
                                             art: AnyView(art), revision: revision,
                                             bytes: style.state?.progress?.transfer?.bytesTransferred,
                                             onSettled: { completedHere = false })
                    }
                }
            }
            .onChange(of: current, initial: true) { old, new in
                let previous = lastPhase ?? old
                completedHere = new.completes(previous)
                lastPhase = new.hold(after: previous) ?? new
            }
    }
}

/// Lives above the flattened artwork and below the badge. No animation view is mounted at rest.
struct DownloadCloudOverlay: View {
    let scene: DownloadCloudMotion.Scene
    let item: CloudLibraryItem?
    let id: UUID
    let cornerRadius: CGFloat
    var title: CGRect? = nil
    let art: AnyView
    var revision: DownloadCloudArtRevision
    let bytes: Int64?
    let onSettled: () -> Void

    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.seleneBackdropStyle) private var backdrop
    @Environment(\.downloadCloudCapture) private var capture

    var body: some View {
        let colors = DownloadCloudColors(backdrop.palette)
        let revision = DownloadCloudArtRevision(images: revision.images, title: revision.title,
                                                glass: backdrop.palette.glass)
        Group {
            if let capture {
                let sample = capture.sample ?? DownloadCloudMotion.preview(scene, at: capture.time, reduced: reduceMotion)
                snapshot(sample, seed: capture.seed, scrimsOnly: capture.scrimsOnly, artOnly: capture.artOnly)
            } else {
                DownloadCloudLive(
                    input: .init(scene: scene, colors: colors, seed: seed,
                                 title: title, item: item, bytes: bytes, reduced: reduceMotion),
                    art: art, revision: revision, onSettled: onSettled)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var seed: UInt64 {
        withUnsafeBytes(of: id.uuid) { $0.prefix(8).reduce(0) { ($0 << 8) | UInt64($1) } }
    }

    private func snapshot(_ sample: DownloadCloudMotion.Sample, seed: UInt64,
                          scrimsOnly: Bool, artOnly: Bool) -> some View {
        ZStack {
            if sample.surface.level != nil {
                art.mask {
                    Canvas { context, size in
                        if sample.bands.isEmpty {
                            context.fill(Path(DownloadCloudFront.path(sample.surface, size, fill: true)), with: .color(.white))
                        } else {
                            var bottom = 1.0
                            for band in sample.bands {
                                let top = 1 - band.level
                                let rect = CGRect(x: 0, y: top * size.height, width: size.width,
                                                  height: (bottom - top) * size.height)
                                context.fill(Path(rect), with: .color(SeleneTheme.artInk.opacity(band.opacity)))
                                bottom = top
                            }
                        }
                    }
                }
            }
            light(sample, seed: seed, scrimsOnly: scrimsOnly, artOnly: artOnly)
        }
        .opacity(sample.opacity)
    }

    private func light(_ sample: DownloadCloudMotion.Sample, seed: UInt64, scrimsOnly: Bool, artOnly: Bool) -> some View {
        let sprites = DownloadCloudSprites(.init(backdrop.palette))
        return Canvas { context, size in
            let surface = sample.surface
            context.withCGContext { cg in
                guard !artOnly else { return }
                if let title {
                    cg.addPath(DownloadCloudSprites.titleMask(size, title))
                    cg.clip(using: .evenOdd)
                }
                func draw(_ frame: DownloadCloudMotion.Frame, completion: Bool) {
                    for (image, rect, opacity) in sprites.scrims(frame, size, completion: completion) where opacity > 0 {
                        // Canvas draws CGImage Y-down; Core Animation draws it upright.
                        cg.saveGState()
                        cg.setAlpha(opacity)
                        cg.translateBy(x: 0, y: 2 * rect.midY)
                        cg.scaleBy(x: 1, y: -1)
                        cg.draw(image, in: rect)
                        cg.restoreGState()
                    }
                    for mote in frame.dots where mote.opacity > 0 {
                        let rect = DownloadCloudSprites.rect(mote)
                        cg.setAlpha(mote.opacity)
                        if !completion, mote.kind != .bubble { cg.draw(DownloadCloudSprites.underpoint, in: rect) }
                        if !scrimsOnly { cg.draw(sprites.image(mote), in: rect) }
                    }
                    cg.setAlpha(1)
                }
                if surface.activity > 0 {
                    DownloadCloudFront.draw(surface, size, in: cg)
                    draw(DownloadCloudMotion.frame(.drift(surface.level), seed: seed, at: surface.phase,
                                                   size: size, surface: surface), completion: false)
                }
                if let time = sample.celebration {
                    draw(DownloadCloudMotion.frame(reduceMotion ? .fade : .completion, seed: seed, at: time,
                                                   size: size), completion: true)
                }
            }
        }
    }

}

private struct DownloadCloudLive: View {
    let input: DownloadCloudLayerView.Input
    let art: AnyView
    let revision: DownloadCloudArtRevision
    let onSettled: () -> Void
    @Environment(\.seleneCanvas) private var canvas
    @State private var visible = false

    var body: some View {
        Group {
            if visible {
                DownloadCloudLayers(input: input, art: art, revision: revision, onSettled: onSettled)
            } else if input.scene.duration > 0 {
                art
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
    let art: AnyView
    let revision: DownloadCloudArtRevision
    let onSettled: () -> Void
    func makeNSView(context: Context) -> DownloadCloudLayerView { DownloadCloudLayerView() }
    func updateNSView(_ view: DownloadCloudLayerView, context: Context) {
        view.setArt(art, revision: revision)
        view.onSettled = onSettled
        view.input = input
    }
    static func dismantleNSView(_ view: DownloadCloudLayerView, coordinator: ()) {
        view.input = nil
        view.onSettled = nil
        view.clear()
    }
}

struct DownloadCloudColors: Equatable {
    let ink, accent: UInt32
    init(_ palette: SelenePalette) {
        ink = palette.ink
        accent = palette.mode == .light ? palette.focus : palette.glyph
    }
}

/// The compositor and raster probe share the same path geometry and optical treatment.
enum DownloadCloudFront {
    static let stops: [CGFloat] = [0, 0.17, 0.36, 0.64, 0.83, 1]
    static let fade: [Double] = [0, 0.65, 1, 1, 0.65, 0]
    // The crest stays sharp; the dark support is softer and predominantly above it.
    static let bands: [(width: Double, alpha: Double)] = [
        (19, 0.018), (17, 0.022), (15, 0.029), (13, 0.038),
        (11, 0.048), (9, 0.052), (7, 0.055), (5, 0.047),
    ]
    static let shadeOffset = -4.3

    static func path(_ surface: DownloadCloudMotion.Surface, _ size: CGSize, fill: Bool = false) -> CGPath {
        let path = CGMutablePath()
        let dx = size.width / 16
        func y(_ x: Double) -> Double { surface.y(at: x, in: size) }
        func tangent(_ x: Double) -> Double { (y(x + dx / 8) - y(x - dx / 8)) * 4 / 3 }
        var y0 = y(0), m0 = tangent(0)
        path.move(to: CGPoint(x: 0, y: y0))
        for i in 1...16 {
            let b = Double(i) * dx, a = b - dx
            let y1 = y(b), m1 = tangent(b)
            path.addCurve(to: CGPoint(x: b, y: y1), control1: CGPoint(x: a + dx / 3, y: y0 + m0),
                          control2: CGPoint(x: b - dx / 3, y: y1 - m1))
            (y0, m0) = (y1, m1)
        }
        return fill ? filled(path, size) : path
    }

    static func filled(_ curve: CGPath, _ size: CGSize) -> CGPath {
        let path = curve.mutableCopy()!
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    static func lineOpacity(_ surface: DownloadCloudMotion.Surface) -> Double {
        guard let level = surface.level else { return 0 }
        let edge = min(1, min(level, 1 - level) * 40)
        return edge * edge * (3 - 2 * edge) * 0.71 * surface.activity
    }

    static func shadeOpacity(_ surface: DownloadCloudMotion.Surface) -> Double {
        surface.activity * (surface.level == nil ? 0.76 : 1)
    }

    static func draw(_ surface: DownloadCloudMotion.Surface, _ size: CGSize, in cg: CGContext) {
        let scale = min(size.width, size.height) / 170
        let curve = path(surface, size)
        func stroke(_ offset: Double, _ width: Double, _ alpha: Double, white: CGFloat) {
            guard alpha > 0 else { return }
            cg.saveGState()
            cg.translateBy(x: 0, y: offset * scale)
            cg.addPath(curve)
            cg.setLineWidth(width * scale)
            cg.replacePathWithStrokedPath()
            cg.clip()
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let colors = fade.map { CGColor(srgbRed: white, green: white, blue: white, alpha: $0 * alpha) }
            let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops)!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            cg.restoreGState()
        }
        for band in bands { stroke(shadeOffset, band.width, band.alpha * shadeOpacity(surface), white: 0) }
        stroke(0, 1.55, lineOpacity(surface) * 0.28, white: 0)
        stroke(0, 0.9, lineOpacity(surface), white: 1)
    }
}

struct DownloadCloudSprites {
    let ink, accent, sun, star: CGImage
    private static let band = makeBand()
    static let underpoint = raster(64) { cg, size in
        radial(cg, size, rgb: [0, 0, 0, 0], alpha: [0.47, 0.47, 0.25, 0],
               locations: [0, 0.40, 0.53, 1])
    }
    private static let centre = raster(128) { cg, size in
        radial(cg, size, rgb: [0, 0, 0, 0], alpha: [0.53, 0.52, 0.32, 0],
               locations: [0, 0.54, 0.75, 1])
    }

    init(_ colors: DownloadCloudColors) {
        ink = Self.sprite(halo: Self.luminous(colors.ink))
        accent = Self.sprite(halo: Self.luminous(colors.accent))
        sun = Self.sprite(halo: SeleneTokens.Art.sun, warm: true)
        star = Self.sprite(halo: SeleneTokens.Art.sun, warm: true, rays: true)
    }

    func image(_ mote: DownloadCloudMotion.Mote) -> CGImage {
        switch mote.kind {
        case .ink: ink
        case .accent, .bubble: accent
        case .sun: sun
        case .star: star
        }
    }

    static func rect(_ mote: DownloadCloudMotion.Mote) -> CGRect {
        let extent = mote.radius * 2.8
        return CGRect(x: mote.center.x - extent, y: mote.center.y - extent,
                      width: extent * 2, height: extent * 2)
    }

    func scrims(_ frame: DownloadCloudMotion.Frame, _ size: CGSize, completion: Bool) -> [(CGImage, CGRect, Double)] {
        guard completion else { return [] }
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
            let core: UInt32 = warm ? SeleneTokens.Art.sunCore : SeleneTokens.Art.starCore
            radial(cg, size, rgb: [SeleneTokens.Art.ink, core, halo, halo], alpha: [1, 1, warm ? 0.30 : 0.23, 0],
                   locations: warm ? [0, 0.22, 0.49, 1] : [0, 0.37, 0.61, 1])
            guard rays else { return }
            let m = size / 2
            for reach in [m * 0.96, m * 0.82] {
                cg.beginPath()
                cg.move(to: CGPoint(x: m - reach, y: m))
                cg.addLines(between: [CGPoint(x: m - reach, y: m), CGPoint(x: m, y: m - 1.65),
                                      CGPoint(x: m + reach, y: m), CGPoint(x: m, y: m + 1.65)])
                cg.closePath()
                cg.setFillColor(color(SeleneTokens.Art.sunRay, 0.86))
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
        let colors: DownloadCloudColors
        let seed: UInt64
        var title: CGRect? = nil
        var item: CloudLibraryItem? = nil
        var bytes: Int64? = nil
        var reduced = false
    }

    var input: Input? { didSet { if oldValue != input { needsLayout = true } } }
    var onSettled: (() -> Void)?
    let field = CALayer()
    let coat = CALayer()
    private let fillMask = CAShapeLayer()
    private var applied: Input?
    private var appliedSize: CGSize = .zero
    private var track: DownloadCloudMotion.Track?
    private var lastBytes: Int64?
    private var generation = 0
    private var sprites: DownloadCloudSprites?
    private var spriteColors: DownloadCloudColors?
    private var art: AnyView?
    private var artRevision: DownloadCloudArtRevision?
    private var renderedSize: CGSize = .zero
    private var renderedScale: CGFloat = 0

    override init() {
        super.init()
        coat.mask = fillMask
        coat.contentsGravity = .resize
        root.addSublayer(coat)
        root.addSublayer(field)
    }

    required init?(coder: NSCoder) { nil }

    func setArt(_ art: AnyView?, revision: DownloadCloudArtRevision) {
        let next = art == nil ? nil : revision
        guard artRevision != next else { return }
        self.art = art
        artRevision = next
        renderedSize = .zero
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { clear() }
    }

    func clear() {
        removeTracks()
        Self.withoutActions { coat.contents = nil }
        renderedSize = .zero
        applied = nil
        track = nil
        lastBytes = nil
    }

    private func removeTracks() {
        generation &+= 1
        Self.withoutActions {
            for dot in field.sublayers ?? [] {
                dot.removeAllAnimations()
                dot.removeFromSuperlayer()
            }
            field.removeAllAnimations()
            field.mask = nil
            coat.removeAllAnimations()
            fillMask.removeAllAnimations()
            fillMask.sublayers = nil
            fillMask.path = nil
        }
    }

    override func arrange(scale: CGFloat) {
        guard let input, window != nil, !bounds.isEmpty else { clear(); return }
        if let art {
            if renderedSize != bounds.size || renderedScale != scale {
                let renderer = ImageRenderer(content: art.frame(width: bounds.width, height: bounds.height))
                renderer.scale = scale
                coat.contents = renderer.cgImage
                renderedSize = bounds.size
                renderedScale = scale
            }
        } else if coat.contents != nil {
            coat.contents = nil
            renderedSize = .zero
        }
        apply(input, size: bounds.size, now: CACurrentMediaTime())
    }

    /// Kept independent of the window so the same scheduling can be exercised headlessly.
    func apply(_ input: Input, size: CGSize, now: Double) {
        guard applied != input || appliedSize != size else { return }
        let scene = input.scene
        if let last = applied {
            if last.reduced != input.reduced {
                track = .init(.settle(track?.sample(at: now).surface.level), at: now,
                              reduced: input.reduced, appear: false)
            }
            if last.scene != scene || last.bytes != input.bytes || last.item != input.item || last.reduced != input.reduced {
                let previous = lastBytes
                let restart = scene.isDrift && (last.item != input.item || last.scene.duration > 0
                    || input.bytes.map { $0 < (previous ?? $0) } == true)
                let advanced = input.bytes.map { $0 > (previous ?? -1) } == true
                track?.receive(scene, at: now, restart: restart, advanced: advanced)
            }
        } else {
            // A success seen for the first time (scrolling back in) must not replay its cue.
            track = .init(scene.duration > 0 ? .settle(1) : scene, at: now, reduced: input.reduced,
                          appear: scene.duration == 0)
        }
        if let bytes = input.bytes { lastBytes = bytes }
        else if input.item != applied?.item { lastBytes = nil }
        applied = input
        appliedSize = size
        guard let track else { return }
        if spriteColors != input.colors || sprites == nil {
            sprites = DownloadCloudSprites(input.colors)
            spriteColors = input.colors
        }
        let sprites = sprites!
        let remaining = max(0, track.end - now)
        let steps = Int(ceil(remaining * 30))
        let times = (0...steps).map { steps == 0 ? 0 : Double($0) / Double(steps) }
        let samples = times.map { track.sample(at: now + $0 * remaining) }
        let surfaces = samples.map(\.surface)
        func keyframes(_ key: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values
            animation.keyTimes = times.map { NSNumber(value: $0) }
            animation.duration = remaining
            return animation
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        removeTracks()
        if scene.duration > 0 {
            let generation = generation
            CATransaction.setCompletionBlock { [weak self] in
                guard self?.generation == generation else { return }
                self?.onSettled?()
            }
        }
        let rect = CGRect(origin: .zero, size: size)
        coat.frame = rect
        fillMask.frame = rect
        field.frame = rect
        field.masksToBounds = true
        if let title = input.title {
            let mask = CAShapeLayer()
            mask.frame = rect
            mask.path = DownloadCloudSprites.titleMask(size, title)
            mask.fillRule = .evenOdd
            field.mask = mask
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
            guard remaining > 0 else { return }
            let animation = CAAnimationGroup()
            animation.animations = tracks
            animation.beginTime = layer.convertTime(now, from: nil)
            animation.duration = remaining
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            layer.add(animation, forKey: "cloud")
        }
        func playOpacity(_ layer: CALayer, _ values: [Double]) {
            layer.opacity = Float(values.last!)
            if values.contains(where: { $0 != values.last! }) {
                animate(layer, [keyframes("opacity", values)])
            }
        }
        if input.reduced {
            let levels = Set(samples.flatMap { $0.bands.map(\.level) }).sorted()
            var below = 0.0
            for level in levels {
                let band = CALayer()
                band.backgroundColor = SeleneTheme.nsArtInk.cgColor
                band.frame = CGRect(x: 0, y: (1 - level) * size.height, width: size.width,
                                    height: (level - below) * size.height)
                fillMask.addSublayer(band)
                let midpoint = (level + below) / 2
                playOpacity(band, samples.map { $0.bands.first { $0.level >= midpoint }?.opacity ?? 0 })
                below = level
            }
        } else if surfaces.contains(where: { $0.level != nil || $0.activity > 0 }) {
            let curves = surfaces.map { DownloadCloudFront.path($0, size) }
            if surfaces.contains(where: { $0.level != nil }) {
                let paths = curves.map { DownloadCloudFront.filled($0, size) }
                fillMask.path = paths.last
                if paths.contains(where: { $0 != paths.last! }) {
                    animate(fillMask, [keyframes("path", paths)])
                }
            }
            playOpacity(fillMask, surfaces.map { $0.level == nil ? 0 : 1 })
            if surfaces.contains(where: { $0.activity > 0 }) {
                let fades = CAGradientLayer()
                fades.frame = rect
                fades.startPoint = CGPoint(x: 0, y: 0.5)
                fades.endPoint = CGPoint(x: 1, y: 0.5)
                fades.colors = DownloadCloudFront.fade.map { SeleneTheme.nsArtInk.withAlphaComponent($0).cgColor }
                fades.locations = DownloadCloudFront.stops.map { NSNumber(value: Double($0)) }
                let strokes = CALayer()
                strokes.frame = rect
                strokes.mask = fades
                field.addSublayer(strokes)
                func stroke(_ offset: Double, _ width: Double, _ color: CGColor, _ opacity: [Double]) {
                    guard opacity.contains(where: { $0 > 0 }) else { return }
                    let layer = CAShapeLayer()
                    layer.frame = rect
                    layer.fillColor = nil
                    layer.strokeColor = color
                    let scale = min(size.width, size.height) / 170
                    layer.position.y += offset * scale
                    layer.lineWidth = width * scale
                    layer.path = curves.last
                    layer.opacity = Float(opacity.last!)
                    strokes.addSublayer(layer)
                    animate(layer, [keyframes("path", curves), keyframes("opacity", opacity)])
                }
                for band in DownloadCloudFront.bands {
                    stroke(DownloadCloudFront.shadeOffset, band.width, SeleneTheme.nsArtShade.cgColor,
                           surfaces.map { band.alpha * DownloadCloudFront.shadeOpacity($0) })
                }
                stroke(0, 1.55, SeleneTheme.nsArtShade.cgColor, surfaces.map { DownloadCloudFront.lineOpacity($0) * 0.28 })
                stroke(0, 0.9, SeleneTheme.nsArtInk.cgColor, surfaces.map(DownloadCloudFront.lineOpacity))
            }
        }
        if input.reduced { fillMask.opacity = 1 }
        playOpacity(coat, samples.map(\.opacity))
        playOpacity(field, samples.map(\.opacity))

        func draw(_ frames: [DownloadCloudMotion.Frame], gathering: Bool) {
            let scrims = frames.map { sprites.scrims($0, size, completion: gathering) }
            for (index, (image, rect, _)) in scrims[0].enumerated() {
                playOpacity(sprite(image, rect), scrims.map { $0[index].2 })
            }
            for (index, mote) in frames[0].dots.enumerated() {
                let samples = frames.map { $0.dots[index] }
                guard samples.contains(where: { $0.opacity > 0 }) else { continue }
                let rect = DownloadCloudSprites.rect(mote)
                var tracks = [keyframes("opacity", samples.map(\.opacity))]
                if scene != .fade || !gathering {
                    tracks.append(keyframes("position", samples.map { NSValue(point: $0.center) }))
                }
                if gathering && scene == .completion {
                    tracks.append(keyframes("transform.scale", samples.map { $0.radius / mote.radius }))
                }
                if !gathering, mote.kind != .bubble {
                    animate(sprite(DownloadCloudSprites.underpoint, rect), tracks)
                }
                animate(sprite(sprites.image(mote), rect), tracks)
            }
        }
        if surfaces.contains(where: { $0.activity > 0 }) {
            draw(surfaces.map { DownloadCloudMotion.frame(.drift($0.level), seed: input.seed, at: $0.phase,
                                                         size: size, surface: $0) }, gathering: false)
        }
        if samples.contains(where: { $0.celebration != nil }) {
            let unlit = DownloadCloudMotion.frame(scene, seed: input.seed, at: 0, size: size)
            draw(samples.map {
                guard let time = $0.celebration else { return unlit }
                return DownloadCloudMotion.frame(scene, seed: input.seed, at: time, size: size)
            }, gathering: true)
        }
        CATransaction.commit()
    }
}
