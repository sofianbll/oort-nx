import SwiftUI

/// Oort NX's colours, from the generated tokens. The Sun's gold is in the cloud's shader and nowhere else.
enum Oort {
    private static func hex(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255, blue: Double(value & 255) / 255)
    }
    static let focus = hex(SeleneTokens.Palette.focus)
    static let onFocus = hex(SeleneTokens.Palette.onFocus)
    static let ink = hex(SeleneTokens.Palette.ink)
    static let ink2 = hex(SeleneTokens.Palette.ink).opacity(0.72)
    static let night = hex(SeleneTokens.Palette.scrim)
    static let page = hex(SeleneTokens.Palette.glass)
    static let glyph = hex(SeleneTokens.Palette.glyph)
    static let light = hex(SeleneTokens.Palette.light)
    static let ok = hex(SeleneTokens.Color.statusOK)
    static let cloud = hex(SeleneTokens.Color.statusCloud)
    static let danger = hex(SeleneTokens.Color.danger)
    static let warning = hex(SeleneTokens.Color.untested)
    static let panelLow = page.mix(with: ink, by: SeleneTokens.Effect.surfaceLow)
    static let panelHigh = page.mix(with: ink, by: SeleneTokens.Effect.surfaceHigh)
    static let panelRaised = page.mix(with: ink, by: SeleneTokens.Effect.surfaceRaised)
    /// White words on it read at 4.5:1, and its own signs at 3:1 on the sidebar.
    static let chosen = page.mix(with: glyph, by: 0.56, in: .device)
    static let line = glyph.opacity(SeleneTokens.Effect.surfaceLine)
    static let lineStrong = glyph.opacity(SeleneTokens.Effect.surfaceLineStrong)
    static var gradient: RadialGradient {
        RadialGradient(colors: [hex(SeleneTokens.Palette.gradientStart), hex(SeleneTokens.Palette.gradientEnd)],
                       center: .topTrailing, startRadius: 0, endRadius: 900)
    }
    static let tile = SeleneTokens.Radius.card
    static let key = SeleneTokens.Radius.field

    /// The version the player reads: the app's number, with its stage.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return info["OortVersion"] as? String ?? info["CFBundleShortVersionString"] as? String ?? "—"
    }
    static func text(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }
    static func dots(_ reduced: Bool) -> Animation? {
        reduced ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: SeleneTokens.Motion.slow)
    }
    static func focusCurve(_ reduced: Bool) -> Animation? {
        reduced ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: SeleneTokens.Motion.focusIn)
    }
}

/// The halftone of the Oort mark, rising under a focused key.
struct OortDots: View, Animatable {
    nonisolated var rise: Double
    let color: Color
    nonisolated var animatableData: Double {
        get { rise }
        set { rise = newValue }
    }

    var body: some View {
        Canvas { context, size in
            guard rise > 0.01 else { return }
            let pitch = SeleneTokens.Effect.dotPitch, radius = SeleneTokens.Effect.dotRadius * rise
            var dots = Path()
            for row in 0...Int(size.height / pitch) {
                for column in 0...Int(size.width / pitch) {
                    dots.addEllipse(in: CGRect(x: (CGFloat(column) + 0.5) * pitch - radius, y: (CGFloat(row) + 0.5) * pitch - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
            context.fill(dots, with: .color(color))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The one key: solid for the main action, panel for the others. It sinks under the finger and lights under the controller.
struct OortKeyStyle: ButtonStyle {
    var solid = false
    var focused = false
    var round = false
    var tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let lit = focused || configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: round ? 100 : Oort.key, style: .continuous)
        configuration.label
            .labelStyle(OortKeyLabel())
            .font(.headline)
            // A round key is as wide as it is tall: its sign stops growing with it.
            .dynamicTypeSize(round ? ...DynamicTypeSize.xxxLarge : ...DynamicTypeSize.accessibility5)
            .foregroundStyle(tint ?? (solid ? Oort.onFocus : Oort.ink))
            .padding(.horizontal, round ? 0 : SeleneTokens.Space.large)
            .frame(minWidth: 50, minHeight: 50)
            .background {
                shape.fill(LinearGradient(colors: solid ? [Oort.focus, Oort.focus.mix(with: Oort.glyph, by: SeleneTokens.Effect.surfaceLineStrong)]
                                          : [Oort.panelRaised, Oort.panelLow], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        OortDots(rise: lit ? 1 : 0, color: solid ? Oort.glyph.opacity(0.55) : Oort.glyph.opacity(SeleneTokens.Effect.surfaceLineStrong))
                            .animation(Oort.dots(reduceMotion), value: lit)
                            .clipShape(shape)
                    }
                    .overlay {
                        shape.strokeBorder(focused ? Oort.focus : Oort.lineStrong, lineWidth: focused ? SeleneTokens.Space.focusStroke : 1)
                            .opacity(solid && !focused ? 0 : 1)
                    }
            }
            // A solid key is already white: its ring stands off it.
            .overlay {
                if solid && focused {
                    shape.inset(by: -5).strokeBorder(Oort.focus, lineWidth: SeleneTokens.Space.focusStroke)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? SeleneTokens.Effect.pressScale : 1)
            .opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .linear(duration: SeleneTokens.Motion.press), value: configuration.isPressed)
            .contentShape(shape)
    }
}

/// The icon beside its words, also inside a list.
private struct OortKeyLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: SeleneTokens.Space.compact) { configuration.icon; configuration.title }
    }
}

/// The panel every list row and card sits on.
struct OortPanel: ViewModifier {
    var radius = Oort.tile
    var focused = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            shape.fill(LinearGradient(colors: focused ? [Oort.panelRaised, Oort.panelHigh] : [Oort.panelHigh, Oort.panelLow],
                                      startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(focused ? Oort.focus : Oort.line, lineWidth: focused ? SeleneTokens.Space.focusStroke : 1)
        }
    }
}

extension View {
    func oortPanel(radius: CGFloat = Oort.tile, focused: Bool = false) -> some View { modifier(OortPanel(radius: radius, focused: focused)) }
}
