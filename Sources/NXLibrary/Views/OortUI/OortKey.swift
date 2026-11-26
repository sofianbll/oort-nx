import Combine
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
        if kind == .solid { return SeleneTheme.glyph }
        // Destructive labels keep their contrast at focus; the outline still shows the selection.
        if tint == SeleneTheme.dangerText { return .clear }
        return (tint ?? SeleneTheme.glyph).opacity(SeleneTokens.Effect.surfaceLineStrong)
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

/// A press that comes from the controller or the keyboard, for whatever holds the focus.
enum OortPulse {
    static let press = PassthroughSubject<Void, Never>()
}

extension View {
    /// Sinks for a moment when A is pressed while this holds the focus.
    func oortPadPress(_ focused: Bool) -> some View { modifier(OortPadPress(focused: focused)) }
}

private struct OortPadPress: ViewModifier {
    let focused: Bool
    @State private var down = false

    func body(content: Content) -> some View {
        OortPressed(down: down && focused) { content }
            .onReceive(OortPulse.press) {
                guard focused else { return }
                down = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(110))
                    down = false
                }
            }
    }
}

/// The one panel: a surface lit from above, a hairline, a soft shadow when it floats.
struct OortPanelSurface: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.colorSchemeContrast) private var contrast
    let radius: CGFloat
    var raised = false
    var floats = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(LinearGradient(colors: raised ? [SeleneTheme.panelRaised, SeleneTheme.panelHigh]
                                          : [SeleneTheme.panelHigh, SeleneTheme.panelLow],
                                          startPoint: .top, endPoint: .bottom))
                    .overlay {
                        OortRing(radius: radius, width: max(1, canvas.u(SeleneTokens.Space.thinStroke)))
                            .fill(LinearGradient(colors: contrast == .increased ? [SeleneTheme.ink60, SeleneTheme.ink60]
                                                 : [SeleneTheme.lineStrong, SeleneTheme.line],
                                                 startPoint: .top, endPoint: .bottom), style: FillStyle(eoFill: true))
                    }
                    .modifier(OortFloat(on: floats))
            }
    }
}

/// A recess for what is typed or read: the ground shows through, under a hairline.
struct OortWellSurface: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.colorSchemeContrast) private var contrast
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(SeleneTheme.scrim45))
            .overlay(shape.strokeBorder(contrast == .increased ? SeleneTheme.ink60 : SeleneTheme.ink15, lineWidth: max(1, canvas.u(SeleneTokens.Space.thinStroke))).allowsHitTesting(false))
    }
}

/// The one focus ring of a picture: gold, concentric, with a dark edge so it reads on a light one too.
struct OortRingFocus: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    let on: Bool
    let radius: CGFloat
    let gap: CGFloat

    func body(content: Content) -> some View {
        let width = canvas.u(SeleneTokens.Space.strongStroke), edge = max(1, canvas.u(SeleneTokens.Space.thinStroke))
        content.overlay {
            ZStack {
                RoundedRectangle(cornerRadius: radius + gap + edge, style: .continuous)
                    .strokeBorder(SeleneTheme.scrim.opacity(SeleneTokens.Alpha.half), lineWidth: width + edge)
                    .padding(-gap - edge)
                RoundedRectangle(cornerRadius: radius + gap, style: .continuous)
                    .strokeBorder(SeleneTheme.focus, lineWidth: width)
                    .padding(-gap)
            }
            .opacity(on ? 1 : 0)
            .allowsHitTesting(false)
        }
    }
}

private struct OortFloat: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    let on: Bool

    func body(content: Content) -> some View {
        content.shadow(color: SeleneTheme.scrim.opacity(on ? SeleneTokens.Effect.dialogShadowOpacity : 0),
                       radius: on ? canvas.u(SeleneTokens.Effect.dialogShadowRadius) : 0,
                       y: on ? canvas.u(SeleneTokens.Space.small) : 0)
    }
}

extension View {
    /// `radius` and `gap` are in points, already scaled by the caller.
    func oortRing(_ on: Bool, radius: CGFloat, gap: CGFloat) -> some View {
        modifier(OortRingFocus(on: on, radius: radius, gap: gap))
    }
    func oortWell(radius: CGFloat) -> some View { modifier(OortWellSurface(radius: radius)) }
    func oortPanel(radius: CGFloat, raised: Bool = false, floats: Bool = false) -> some View {
        modifier(OortPanelSurface(radius: radius, raised: raised, floats: floats))
    }
}
