import SwiftUI
import NXLibraryCore

/// The halftone of the Oort mark, rising under a focused key.
struct OortDots: View, Animatable {
    @Environment(\.seleneCanvas) private var canvas
    /// 0 = nothing, 1 = full dots.
    var rise: Double
    let color: Color

    var animatableData: Double {
        get { rise }
        set { rise = newValue }
    }

    var body: some View {
        Canvas { context, size in
            guard rise > 0.01 else { return }
            let pitch = canvas.u(SeleneTokens.Effect.dotPitch)
            let radius = canvas.u(SeleneTokens.Effect.dotRadius) * rise
            var dots = Path()
            for row in 0...Int(size.height / pitch) {
                for column in 0...Int(size.width / pitch) {
                    dots.addEllipse(in: CGRect(x: (CGFloat(column) + 0.5) * pitch - radius,
                                               y: (CGFloat(row) + 0.5) * pitch - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
            context.fill(dots, with: .color(color))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The one surface of every key: solid under focus, panel at rest, with the halftone rising on focus or hover.
struct OortKeyFace: View {
    enum Kind { case solid, quiet }

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let kind: Kind
    let radius: CGFloat
    /// The halftone is up.
    let lit: Bool
    /// The outline says focus where the key is not solid.
    let outlined: Bool
    var tint: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(fill)
            .overlay {
                OortDots(rise: lit ? 1 : 0, color: dots)
                    .animation(Motion.dots(reduceMotion), value: lit)
                    .clipShape(shape)
            }
            .overlay {
                // One line says either "key" or "focus"; the top edge catches the light.
                OortRing(radius: radius, width: max(1, canvas.u(outlined ? SeleneTokens.Space.focusStroke
                                                                : SeleneTokens.Space.thinStroke)))
                    .fill(outlined ? AnyShapeStyle(tint ?? SeleneTheme.focus)
                          : AnyShapeStyle(LinearGradient(colors: [SeleneTheme.lineStrong, SeleneTheme.line],
                                                         startPoint: .top, endPoint: .bottom)),
                          style: FillStyle(eoFill: true))
                    .opacity(kind == .solid ? 0 : 1)
            }
            .oortKeyShadow(kind == .solid)
    }

    private var fill: LinearGradient {
        let colors = kind == .solid
            ? [SeleneTheme.focus, SeleneTheme.focus.mix(with: SeleneTheme.glyph, by: SeleneTokens.Effect.surfaceLineStrong)]
            : [SeleneTheme.panelRaised, SeleneTheme.panelLow]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var dots: Color {
        kind == .solid ? SeleneTheme.glyph : (tint ?? SeleneTheme.glyph).opacity(SeleneTokens.Effect.surfaceLineStrong)
    }
}

/// AppKit's display cache draws spurs at the seams of a round strokeBorder.
struct OortRing: Shape {
    let radius: CGFloat
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var ring = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        let inner = rect.insetBy(dx: width, dy: width)
        if !inner.isEmpty {
            ring.addPath(RoundedRectangle(cornerRadius: max(0, radius - width), style: .continuous).path(in: inner))
        }
        return ring
    }
}

private extension View {
    func oortKeyShadow(_ solid: Bool) -> some View { modifier(OortKeyShadow(solid: solid)) }
}

private struct OortKeyShadow: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    let solid: Bool

    func body(content: Content) -> some View {
        content.shadow(color: SeleneTheme.scrim.opacity(SeleneTokens.Effect.dialogShadowOpacity),
                       radius: canvas.u(solid ? SeleneTokens.Space.large : SeleneTokens.Space.small),
                       y: canvas.u(solid ? SeleneTokens.Space.small : SeleneTokens.Space.hairline))
    }
}

/// Every key sinks and comes back the same way, by mouse, keyboard or controller.
struct OortPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OortPressed(down: configuration.isPressed) { configuration.label }
    }
}

struct OortPressed<Content: View>: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let down: Bool
    @ViewBuilder let content: Content

    var body: some View {
        let sinks = down && !reduceMotion
        content
            .scaleEffect(sinks ? SeleneTokens.Effect.pressScale : 1)
            .offset(y: sinks ? canvas.u(SeleneTokens.Effect.pressDepth) : 0)
            .opacity(down && reduceMotion ? SeleneTokens.Effect.searchVeil : 1)
            .animation(Motion.press(reduceMotion, down: down), value: down)
    }
}
