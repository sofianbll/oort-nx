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

    private func button(_ place: OortPadShape.Place) -> ControllerButton {
        let nintendo = brand == .nintendoSwitch
        return switch place {
        case .leftStick: .l3
        case .rightStick: .r3
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .top: nintendo ? .x : .y
        case .west: nintendo ? .y : .x
        case .east: nintendo ? .a : .b
        case .bottom: nintendo ? .b : .a
        case .view: .view
        case .menu: .menu
        case .home: .home
        }
    }

    /// Shoulders and triggers, as arcs of dots above the pad.
    private static let shoulders: [(ControllerButton, Double, Double)] = [(.l, -1, 0), (.zl, -1, 1), (.r, 1, 0), (.zr, 1, 1)]

    private func draw(_ context: GraphicsContext, _ size: CGSize, _ now: TimeInterval) {
        let unit = size.width * 0.5, zoom = size.width / 420
        let middle = CGPoint(x: size.width / 2, y: size.height * 0.54)
        func light(_ button: ControllerButton) -> Double {
            reduceMotion ? (live.held.contains(button) ? 1 : 0) : live.light(button, at: now)
        }
        func dot(_ x: Double, _ y: Double, _ radius: Double, _ color: Color, _ alpha: Double) {
            let r = radius * zoom
            context.fill(Path(ellipseIn: CGRect(x: middle.x + x * unit - r, y: middle.y + y * unit - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(min(1, alpha))))
        }
        for cell in OortPadShape.cells {
            if let place = cell.part {
                let lit = light(button(place)), edge = cell.edge
                if lit > 0.04 {
                    dot(cell.point.x, cell.point.y, 2.4 + lit * 3.2 * (1 - edge * 0.4), SeleneTheme.focus, 0.35 + lit * 0.65)
                } else if edge > 0.66 {
                    dot(cell.point.x, cell.point.y, 2.2, SeleneTheme.glyph, SeleneTokens.Alpha.near)
                }
            } else {
                let shade = 0.4 + 0.5 * max(0, 0.5 + cell.point.x * 0.5 - cell.point.y * 0.4)
                dot(cell.point.x, cell.point.y, 1.5 + shade * 2.2, SeleneTheme.glyph, 0.25 + shade * 0.6)
            }
        }
        for (part, stick) in [(OortPadShape.parts[0], live.left), (OortPadShape.parts[1], live.right)] {
            let lean = SIMD2(Double(stick.x), -Double(stick.y)) * 0.05
            for step in 0..<16 {
                let angle = Double(step) / 16 * 2 * .pi
                dot(part.x + lean.x + cos(angle) * 0.065, part.y + lean.y + sin(angle) * 0.065, 2.3, SeleneTheme.glyph, 1)
            }
        }
        for (button, side, tier) in Self.shoulders {
            let lit = light(button)
            for point in OortPadShape.shoulder(side: side, tier: tier) {
                dot(point.x, point.y, 2 + lit * 2.6, lit > 0.04 ? SeleneTheme.focus : SeleneTheme.glyph, 0.5 - tier * 0.12 + lit * 0.5)
            }
        }
    }
}
