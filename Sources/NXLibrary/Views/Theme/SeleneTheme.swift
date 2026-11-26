import SwiftUI
import NXLibraryCore

enum SeleneTheme {
    private static var palette: SelenePalette { ThemeStore.shared.palette }

    static var focus: Color { Color(hex: palette.focus) }
    static var onFocus: Color { Color(hex: palette.onFocus) }
    static var ink: Color { Color(hex: palette.ink) }
    static var ink90: Color { ink.opacity(SeleneTokens.Alpha.near) }
    static var ink82: Color { ink.opacity(SeleneTokens.Alpha.heavy) }
    static var ink75: Color { ink.opacity(SeleneTokens.Alpha.strong) }
    static var ink60: Color { ink.opacity(SeleneTokens.Alpha.muted) }
    static var ink25: Color { ink.opacity(SeleneTokens.Alpha.line) }
    static var ink15: Color { ink.opacity(SeleneTokens.Alpha.soft) }
    static var scrim: Color { Color(hex: palette.scrim) }
    static var scrim65: Color { scrim.opacity(SeleneTokens.Effect.deepVeil) }
    static var scrim45: Color { scrim.opacity(SeleneTokens.Effect.panelVeil) }
    static var glass: Color { Color(hex: palette.glass, opacity: 0.75) }
    static var glassSolid: Color { Color(hex: palette.glass, opacity: 0.88) }
    static var glassLight: Color { Color(hex: palette.glass, opacity: 0.45) }
    /// The dialog card stays opaque even when the dimmed page has a bright wallpaper.
    static var glassCard: Color { pageSurface }
    static var pageSurface: Color { Color(hex: palette.glass) }
    static var glyph: Color { Color(hex: palette.glyph) }
    static var backgroundLight: Color { Color(hex: palette.backgroundLight) }
    static var moonlightSurface: MoonlightSurface { palette.surface }
    /// Every list icon in one colour: on Selene a soft ink (its blue accent read poorly
    /// on the glass), elsewhere the palette's glyph.
    static var rowIcon: Color { palette.id == SelenePaletteCatalog.classicBlueID ? ink82 : glyph }
    static var success: Color { Color(hex: palette.success) }
    static let danger = Color(hex: SeleneTokens.Color.danger)
    /// Monochrome themes still use semantic colors for status dots.
    static let statusOK = Color(hex: SeleneTokens.Color.statusOK)
    static let statusCloud = Color(hex: SeleneTokens.Color.statusCloud)
    static let untested = Color(hex: SeleneTokens.Color.untested)
    // Surfaces come from the palette's page and ink, so every palette gets its own.
    private static func surface(_ ink: Double) -> Color { pageSurface.mix(with: self.ink, by: ink) }
    static var panelLow: Color { surface(SeleneTokens.Effect.surfaceLow) }
    static var panelHigh: Color { surface(SeleneTokens.Effect.surfaceHigh) }
    static var panelRaised: Color { surface(SeleneTokens.Effect.surfaceRaised) }
    static var line: Color { glyph.opacity(SeleneTokens.Effect.surfaceLine) }
    static var lineStrong: Color { glyph.opacity(SeleneTokens.Effect.surfaceLineStrong) }
    static var shine: Color { ink.opacity(SeleneTokens.Effect.surfaceShine) }
    /// On artwork, whatever the palette: the shade under text and the ink over it.
    static let artShade = Color(hex: SeleneTokens.Art.shade)
    static let artInk = Color(hex: SeleneTokens.Art.ink)
    static let nsArtShade = NSColor(artShade)
    static let nsArtInk = NSColor(artInk)
    static let sun = Color(hex: SeleneTokens.Art.sun)
    static var focusGlow: Color { focus.opacity(SeleneTokens.Alpha.shade) }
    static var focusGlowStrong: Color { focus.opacity(SeleneTokens.Alpha.veil) }

    static var baseGradient: AnyShapeStyle { baseGradient(for: palette) }

    /// A palette's base gradient, active or not (the Theme screen's previews).
    static func baseGradient(for palette: SelenePalette) -> AnyShapeStyle {
        let stops = palette.base.stops.map {
            Gradient.Stop(color: Color(hex: $0.color), location: $0.location)
        }
        switch palette.base.kind {
        case .linear:
            return AnyShapeStyle(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
        case .radial:
            // Selene's RadiusX 0.5 / RadiusY 0.7 of the bounds, as an ellipse fraction.
            return AnyShapeStyle(EllipticalGradient(
                gradient: Gradient(stops: stops), center: UnitPoint(x: 0.5, y: 0.2),
                startRadiusFraction: 0, endRadiusFraction: 1.2))
        }
    }

    static let rowRadius = SeleneTokens.Radius.row
    static let contentRadius = SeleneTokens.Radius.content
    static let cardRadius = SeleneTokens.Radius.card
    static let modalRadius = SeleneTokens.Radius.modal
    static let coverRadius = SeleneTokens.Radius.cover
    static let standard = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.24)
    static let quick = Motion.focusIn
    static let focusIn = quick
    static let focusOut = Motion.focusOut
    static let screenDuration = Motion.screenDuration
    static let screen = Motion.screen
    static func cubicOut(_ duration: Double) -> Animation {
        .timingCurve(0.215, 0.61, 0.355, 1, duration: duration)
    }
    /// An image or a message that has just arrived.
    static let arrival = Animation.easeOut(duration: SeleneTokens.Motion.transfer)
    static let art = Animation.easeOut(duration: SeleneTokens.Motion.art)
    static func ease(_ duration: Double) -> Animation { .easeInOut(duration: duration) }
    /// A refused entry shakes at an even pace.
    static let shake = Animation.linear(duration: SeleneTokens.Motion.shake)
    static func settle(_ duration: Double) -> Animation { .easeOut(duration: duration) }
    static let menu = Animation.spring(response: 0.26, dampingFraction: 0.88)
    static let expand = Animation.spring(response: 0.42, dampingFraction: 0.86)

    static let heroLeftScrim = LinearGradient(
        stops: [
            .init(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.half), location: 0.00),
            .init(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.shade), location: 0.22),
            .init(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.line), location: 0.44),
            .init(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.faint), location: 0.62),
            .init(color: .clear, location: 0.78)
        ],
        startPoint: .leading, endPoint: .trailing
    )
    static let heroBottomScrim = LinearGradient(
        stops: [
            .init(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.heavy), location: 0.00),
            .init(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.muted), location: 0.14),
            .init(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.line), location: 0.28),
            .init(color: .clear, location: 0.45)
        ],
        startPoint: .bottom, endPoint: .top
    )
    static let topScrim = LinearGradient(
        stops: [
            .init(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.half), location: 0.00),
            .init(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.line), location: 0.08),
            .init(color: .clear, location: 0.16)
        ],
        startPoint: .top, endPoint: .bottom
    )
    static let heroAmbientVignette = RadialGradient(
        colors: [
            SeleneTheme.artShade.opacity(SeleneTokens.Alpha.half),
            SeleneTheme.artShade.opacity(SeleneTokens.Alpha.line),
            .clear
        ],
        center: .topLeading,
        startRadius: 50,
        endRadius: 750
    )
}

private struct SeleneRowFocusModifier: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let focused: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(SeleneTokens.Space.focusStroke))
                    .opacity(focused ? 1 : 0)
            }
            .animation(Motion.focus(reduceMotion), value: focused)
    }
}

extension View {
    /// Selene focus language for rows and cards: a 2u focus border at the
    /// element's own corner radius (in points, already scaled by the caller).
    func seleneRowFocus(_ focused: Bool, radius: CGFloat = SeleneTheme.rowRadius) -> some View {
        modifier(SeleneRowFocusModifier(focused: focused, radius: radius))
    }
}

private struct SeleneFocusedRowKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var seleneFocusedRowID: String? {
        get { self[SeleneFocusedRowKey.self] }
        set { self[SeleneFocusedRowKey.self] = newValue }
    }
}

extension View {
    /// The ring of the one key Left and Right put the focus on, in a row with more than one.
    func seleneKeyRing(_ focused: Bool) -> some View {
        padding(.horizontal, SeleneTokens.Space.gap)
            .padding(.vertical, SeleneTokens.Space.chipBottom)
            .overlay {
                Capsule().strokeBorder(SeleneTheme.focus, lineWidth: SeleneTokens.Space.focusStroke)
                    .opacity(focused ? 1 : 0)
            }
            .accessibilityAddTraits(focused ? .isSelected : [])
    }
}

private struct SeleneFocusedButtonKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Which button of the focused row has the focus, for a row with more than one (0 the first).
    var seleneFocusedButton: Int {
        get { self[SeleneFocusedButtonKey.self] }
        set { self[SeleneFocusedButtonKey.self] = newValue }
    }
}

private struct SeleneShowButtonHintsKey: EnvironmentKey {
    static let defaultValue = true
}

private struct SeleneHintsCoveredKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SeleneButtonNamesKey: EnvironmentKey {
    static let defaultValue = ButtonNameStyle.automatic
}

extension EnvironmentValues {
    var seleneShowButtonHints: Bool {
        get { self[SeleneShowButtonHintsKey.self] }
        set { self[SeleneShowButtonHintsKey.self] = newValue }
    }
    /// An overlay with its own hints is up over this screen: its hints step aside.
    var seleneHintsCovered: Bool {
        get { self[SeleneHintsCoveredKey.self] }
        set { self[SeleneHintsCoveredKey.self] = newValue }
    }
    var seleneButtonNames: ButtonNameStyle {
        get { self[SeleneButtonNamesKey.self] }
        set { self[SeleneButtonNamesKey.self] = newValue }
    }
}

private struct SeleneReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var seleneReduceMotion: Bool {
        get { self[SeleneReduceMotionKey.self] }
        set { self[SeleneReduceMotionKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
