import SwiftUI
import NXLibraryCore

/// The pad in the player's hands, in the cloud's dots: what is pressed lights up, the sticks lean.
struct OortControllerView: View {
    @ObservedObject var live = ControllerLive.shared
    var brand: GamepadBrand = .generic
    /// Canvas units.
    var width: CGFloat = 420
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !live.awake)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            Canvas { context, size in draw(context, size, now) }
        }
        .frame(width: canvas.u(width), height: canvas.u(width * 0.72))
        .accessibilityHidden(true)
    }

    /// Places are the site's: the middle of the pad is the origin, half its width is 1.
    private struct Part {
        let button: ControllerButton
        let x, y, radius: Double
    }

    private var parts: [Part] {
        let nintendo = brand == .nintendoSwitch
        let right: ControllerButton = nintendo ? .a : .b, bottom: ControllerButton = nintendo ? .b : .a
        let top: ControllerButton = nintendo ? .x : .y, left: ControllerButton = nintendo ? .y : .x
        return [
            .init(button: .l3, x: -0.43, y: -0.23, radius: 0.135), .init(button: .r3, x: 0.24, y: 0.05, radius: 0.125),
            .init(button: .up, x: -0.145, y: 0.025, radius: 0.045), .init(button: .down, x: -0.145, y: 0.175, radius: 0.045),
            .init(button: .left, x: -0.22, y: 0.1, radius: 0.045), .init(button: .right, x: -0.07, y: 0.1, radius: 0.045),
            .init(button: top, x: 0.467, y: -0.36, radius: 0.062), .init(button: left, x: 0.343, y: -0.24, radius: 0.062),
            .init(button: right, x: 0.59, y: -0.24, radius: 0.062), .init(button: bottom, x: 0.467, y: -0.115, radius: 0.062),
            .init(button: .view, x: -0.16, y: -0.3, radius: 0.038), .init(button: .menu, x: 0.16, y: -0.3, radius: 0.038),
            .init(button: .home, x: 0, y: -0.2, radius: 0.045),
        ]
    }

    /// Shoulders and triggers, as arcs of dots above the pad.
    private static let shoulders: [(ControllerButton, Double, Double)] = [(.l, -1, 0), (.zl, -1, 1), (.r, 1, 0), (.zr, 1, 1)]

    private static let cells: [CGPoint] = {
        var path = Path()
        path.move(to: CGPoint(x: 112, y: 52))
        path.addCurve(to: CGPoint(x: 308, y: 52), control1: CGPoint(x: 150, y: 44), control2: CGPoint(x: 270, y: 44))
        path.addCurve(to: CGPoint(x: 392, y: 190), control1: CGPoint(x: 352, y: 58), control2: CGPoint(x: 372, y: 110))
        path.addCurve(to: CGPoint(x: 352, y: 272), control1: CGPoint(x: 408, y: 254), control2: CGPoint(x: 384, y: 284))
        path.addCurve(to: CGPoint(x: 272, y: 206), control1: CGPoint(x: 318, y: 258), control2: CGPoint(x: 304, y: 214))
        path.addCurve(to: CGPoint(x: 148, y: 206), control1: CGPoint(x: 240, y: 200), control2: CGPoint(x: 180, y: 200))
        path.addCurve(to: CGPoint(x: 68, y: 272), control1: CGPoint(x: 116, y: 214), control2: CGPoint(x: 102, y: 258))
        path.addCurve(to: CGPoint(x: 28, y: 190), control1: CGPoint(x: 36, y: 284), control2: CGPoint(x: 12, y: 254))
        path.addCurve(to: CGPoint(x: 112, y: 52), control1: CGPoint(x: 48, y: 110), control2: CGPoint(x: 68, y: 58))
        let step = 8.2
        var cells: [CGPoint] = []
        for (row, y) in stride(from: 0.0, to: 300, by: step * 0.866).enumerated() {
            for x in stride(from: Double(row % 2) * step / 2, to: 420, by: step) where path.contains(CGPoint(x: x, y: y)) {
                cells.append(CGPoint(x: (x - 210) / 210, y: (y - 150) / 210))
            }
        }
        return cells
    }()

    private func draw(_ context: GraphicsContext, _ size: CGSize, _ now: TimeInterval) {
        let unit = size.width * 0.5, zoom = size.width / 420
        let middle = CGPoint(x: size.width / 2, y: size.height * 0.54)
        let parts = parts
        func light(_ button: ControllerButton) -> Double {
            reduceMotion ? (live.held.contains(button) ? 1 : 0) : live.light(button, at: now)
        }
        func dot(_ x: Double, _ y: Double, _ radius: Double, _ color: Color, _ alpha: Double) {
            let r = radius * zoom
            context.fill(Path(ellipseIn: CGRect(x: middle.x + x * unit - r, y: middle.y + y * unit - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(min(1, alpha))))
        }
        for cell in Self.cells {
            var nearest: (part: Part, distance: Double)?
            for part in parts {
                let distance = hypot(cell.x - part.x, cell.y - part.y)
                if distance < part.radius, distance < nearest?.distance ?? 1 { nearest = (part, distance) }
            }
            if let nearest {
                let lit = light(nearest.part.button), edge = nearest.distance / nearest.part.radius
                if lit > 0.04 {
                    dot(cell.x, cell.y, 2.4 + lit * 3.2 * (1 - edge * 0.4), SeleneTheme.focus, 0.35 + lit * 0.65)
                } else if edge > 0.66 {
                    dot(cell.x, cell.y, 2.2, SeleneTheme.glyph, SeleneTokens.Alpha.near)
                }
            } else {
                let shade = 0.4 + 0.5 * max(0, 0.5 + cell.x * 0.5 - cell.y * 0.4)
                dot(cell.x, cell.y, 1.5 + shade * 2.2, SeleneTheme.glyph, 0.25 + shade * 0.6)
            }
        }
        for (part, stick) in [(parts[0], live.left), (parts[1], live.right)] {
            let lean = SIMD2(Double(stick.x), -Double(stick.y)) * 0.05
            for step in 0..<16 {
                let angle = Double(step) / 16 * 2 * .pi
                dot(part.x + lean.x + cos(angle) * 0.065, part.y + lean.y + sin(angle) * 0.065, 2.3, SeleneTheme.glyph, 1)
            }
        }
        for (button, side, tier) in Self.shoulders {
            let lit = light(button)
            for step in 0..<9 {
                let t = Double(step) / 8
                dot(side * (0.3 + t * 0.34), -0.54 - tier * 0.07 + t * t * 0.1, 2 + lit * 2.6, lit > 0.04 ? SeleneTheme.focus : SeleneTheme.glyph,
                    0.5 - tier * 0.12 + lit * 0.5)
            }
        }
    }
}
