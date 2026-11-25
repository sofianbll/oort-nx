import Metal
import QuartzCore
import SwiftUI

/// The Oort cloud, drawn with the Mac app's own points and shaders (`OortCloudPoint`, `MoonlightShaders`).
final class OortCloudEngine: @unchecked Sendable {
    static let shared = OortCloudEngine()
    /// The moment and the breath of a still frame.
    static let stillTime: Float = 24
    private struct Uniforms { var size, accent, ink, look, tintTop, tintMid, tintBottom: SIMD4<Float> }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let light, dots: MTLRenderPipelineState
    private let points: MTLBuffer
    private let count: Int

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: MoonlightShaders.source, options: nil) else { return nil }
        func pipeline(_ vertex: String, _ fragment: String) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            let color = d.colorAttachments[0]!
            color.pixelFormat = .bgra8Unorm
            color.isBlendingEnabled = true
            (color.sourceRGBBlendFactor, color.sourceAlphaBlendFactor) = (.one, .one)
            (color.destinationRGBBlendFactor, color.destinationAlphaBlendFactor) = (.one, .one)
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        let field = OortCloudPoint.field()
        guard let light = pipeline("moon_full_vertex", "moon_light_fragment"), let dots = pipeline("cloud_dot_vertex", "cloud_dot_fragment"),
              let points = field.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }) else { return nil }
        (self.device, self.queue, self.light, self.dots, self.points, count) = (device, queue, light, dots, points, field.count)
    }

    private func encode(into texture: MTLTexture, time: Float, buffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor()
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        func rgb(_ hex: UInt32) -> SIMD3<Float> { SIMD3(Float(hex >> 16 & 255), Float(hex >> 8 & 255), Float(hex & 255)) / 255 }
        let (w, h) = (Float(texture.width), Float(texture.height))
        var u = Uniforms(size: SIMD4(w, h, time, w / h), accent: SIMD4(rgb(SeleneTokens.Palette.light), 1),
                         ink: SIMD4(rgb(SeleneTokens.Palette.ink), 1), look: SIMD4(0.5 + 0.5 * sin(2 * .pi * time / 7), 1, 0, 0),
                         tintTop: .zero, tintMid: .zero, tintBottom: .zero)
        let length = MemoryLayout<Uniforms>.stride
        encoder.setRenderPipelineState(light)
        encoder.setFragmentBytes(&u, length: length, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.setRenderPipelineState(dots)
        encoder.setVertexBuffer(points, offset: 0, index: 0)
        encoder.setVertexBytes(&u, length: length, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        encoder.endEncoding()
    }

    func draw(_ drawable: CAMetalDrawable, time: Float) {
        guard let buffer = queue.makeCommandBuffer() else { return }
        encode(into: drawable.texture, time: time, buffer: buffer)
        buffer.present(drawable)
        buffer.commit()
    }

    /// One frame as an image: captures, and tests.
    func snapshot(width: Int, height: Int, time: Float = stillTime) -> CGImage? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: max(width, 1), height: max(height, 1), mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d), let buffer = queue.makeCommandBuffer() else { return nil }
        encode(into: texture, time: time, buffer: buffer)
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: d.width * d.height * 4)
        texture.getBytes(&bytes, bytesPerRow: d.width * 4, from: MTLRegionMake2D(0, 0, d.width, d.height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: d.width, height: d.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: d.width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// The page every screen stands on. The cloud moves only in the foreground, and is one still frame under Reduce Motion,
/// Low Power Mode and while a game runs.
struct OortBackdrop: View {
    var strength = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @Environment(\.oortStill) private var still
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // The cloud sits at 71% of a wide frame: a tall screen shows a frame as wide as it is tall, from the right.
            let width = max(size.width, min(size.height, size.width * 1.5))
            ZStack(alignment: .topTrailing) {
                Rectangle().fill(Oort.gradient)
                Group {
                    if let engine = OortCloudEngine.shared {
                        OortCloudLayer(engine: engine, moving: !reduceMotion && !lowPower && !still && phase == .active, still: still)
                    }
                }
                .frame(width: width, height: min(size.height, width))
                .offset(x: (width - size.width) * 0.46)
                .mask { LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom) }
                .opacity(strength)
            }
            .frame(width: size.width, height: size.height, alignment: .topTrailing)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

extension EnvironmentValues {
    /// A still picture of the cloud: captures, and a game on screen.
    @Entry var oortStill = false
}

private struct OortStillCloud: View {
    let engine: OortCloudEngine
    @Environment(\.displayScale) private var scale
    var body: some View {
        GeometryReader { geometry in
            if let image = engine.snapshot(width: Int(geometry.size.width * scale), height: Int(geometry.size.height * scale)) {
                Image(decorative: image, scale: scale).resizable()
            }
        }
    }
}

private struct OortCloudLayer: View {
    let engine: OortCloudEngine
    let moving: Bool
    let still: Bool
    var body: some View {
        #if canImport(UIKit)
        if still { OortStillCloud(engine: engine) } else { OortMetalCloud(engine: engine, moving: moving) }
        #else
        OortStillCloud(engine: engine)
        #endif
    }
}

#if canImport(UIKit)
private struct OortMetalCloud: UIViewRepresentable {
    let engine: OortCloudEngine
    let moving: Bool
    func makeUIView(context: Context) -> OortCloudUIView { OortCloudUIView(engine: engine) }
    func updateUIView(_ view: OortCloudUIView, context: Context) { view.moving = moving }
    static func dismantleUIView(_ view: OortCloudUIView, coordinator: ()) { view.moving = false }
}

/// Draws at 30 frames a second while moving, then one last frame. The clock stops with it, so nothing jumps on return.
final class OortCloudUIView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metal: CAMetalLayer { layer as! CAMetalLayer }
    private let engine: OortCloudEngine
    private var link: CADisplayLink?
    private var clock = Double(OortCloudEngine.stillTime)
    private var last: CFTimeInterval?
    var moving = false { didSet { if moving != oldValue { update() } } }

    init(engine: OortCloudEngine) {
        self.engine = engine
        super.init(frame: .zero)
        metal.device = engine.device
        metal.pixelFormat = .bgra8Unorm
        metal.isOpaque = false
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size.width >= 1, size.height >= 1, metal.drawableSize != size else { return }
        metal.contentsScale = scale
        metal.drawableSize = size
        draw()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        update()
    }

    private func update() {
        let run = moving && window != nil
        if run, link == nil {
            let link = CADisplayLink(target: OortLinkTarget(self), selector: #selector(OortLinkTarget.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            self.link = link
        } else if !run {
            link?.invalidate()
            (link, last) = (nil, nil)
            if window != nil { draw() }
        }
    }

    fileprivate func tick(_ now: CFTimeInterval) {
        if let last { clock += min(now - last, 0.1) }
        last = now
        draw()
    }

    private func draw() {
        guard metal.drawableSize.width >= 1, let drawable = metal.nextDrawable() else { return }
        engine.draw(drawable, time: Float(clock))
    }
}

/// A display link keeps its target: this one lets the view go.
private final class OortLinkTarget: NSObject {
    private weak var view: OortCloudUIView?
    init(_ view: OortCloudUIView) { self.view = view }
    @objc @MainActor func tick(_ link: CADisplayLink) {
        guard let view else { return link.invalidate() }
        view.tick(link.timestamp)
    }
}
#endif
