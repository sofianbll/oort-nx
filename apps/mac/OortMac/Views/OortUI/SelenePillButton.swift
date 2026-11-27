import SwiftUI
import OortLibrary

/// Selene's pill: glass at rest, solid focus colour with glow when focused.
struct SelenePillButton: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.nxAppLocale) private var localization
    @State private var hovered = false

    let title: String?
    var titleArguments: [String] = []
    var icon: MaterialIcon? = nil
    var iconSize: CGFloat = 26
    var minWidth: CGFloat = 180
    /// Takes the width its container offers: pills stacked in a fixed-size column all take the widest one's.
    var fillsWidth = false
    var height: CGFloat = 60
    var titleSize: SeleneTokens.Text = .row
    /// Selene's Padding="36,0"; the round Favorite pill uses 0.
    var horizontalPadding: CGFloat = 36
    let focused: Bool
    var fillsOnFocus = true
    var scalesOnFocus = true
    /// False draws the pill dim: it still takes focus (a ring), but never the solid focus fill.
    var enabled: Bool = true
    /// Three dots after the title rising and falling like a wave ("Porting…").
    var waveDots = false
    var tint: Color? = nil
    var queuedBuild = false
    var accessory: AnyView? = nil
    var keyboardFocus: FocusState<Bool>.Binding? = nil
    /// Zero keeps the outlined download style; nil uses the normal pill style.
    var downloadFill: Double? = nil
    var passive = false
    let action: () -> Void

    static func roundIcon(_ icon: MaterialIcon, focused: Bool = false, enabled: Bool = true,
                          action: @escaping () -> Void) -> Self {
        Self(title: nil, icon: icon, iconSize: 22, minWidth: 44, height: 44, horizontalPadding: 0,
             focused: focused, enabled: enabled, action: action)
    }

    static func buildQueue(minWidth: CGFloat = 180, focused: Bool, action: @escaping () -> Void) -> Self {
        Self(title: "Queued", icon: .schedule, iconSize: 20, minWidth: minWidth, height: 52, horizontalPadding: 18,
             focused: focused, tint: PortingPillCopy.softRed, queuedBuild: true, action: action)
    }

    var body: some View {
        if queuedBuild {
            pill.onHover { hovered = $0 }
                .accessibilityLabel(L10n.text("Cancel queued build", context: localization))
                .accessibilityValue(L10n.text("Queued", context: localization))
        } else if let keyboardFocus {
            pill.onHover { hovered = $0 }.focusable(interactions: .activate)
                .focusEffectDisabled()
                .focused(keyboardFocus)
        } else {
            pill.onHover { hovered = $0 }
        }
    }

    @ViewBuilder private var pill: some View {
        let cancelling = queuedBuild && (focused || hovered)
        let focused = self.focused || cancelling
        let tint = !queuedBuild || cancelling ? self.tint : nil
        let title = cancelling ? "Cancel" : self.title
        let icon = cancelling ? MaterialIcon.close : self.icon
        // A key with an icon alone stays round.
        let radius = title == nil ? canvas.u(height) / 2 : min(canvas.u(height) / 2, canvas.u(SeleneTokens.Radius.card))
        let solid = downloadFill == nil && focused && enabled && tint == nil && fillsOnFocus
        let label = HStack(spacing: canvas.u(SeleneTokens.Space.gap)) {
            accessory
            if let icon {
                MaterialIconView(icon, size: iconSize)
            }
            if let title {
                // A pill's title stays on one line: the pill grows instead.
                ZStack {
                    if queuedBuild {
                        Text(L10n.text(cancelling ? "Queued" : "Cancel", context: localization))
                            .hidden().accessibilityHidden(true)
                    }
                    Text(titleArguments.isEmpty ? L10n.text(title, context: localization)
                         : L10n.format(title, titleArguments, context: localization))
                }
                .seleneFont(titleSize)
                .lineLimit(1)
                .fixedSize()
            }
            if waveDots {
                WaveDots()
                    .padding(.leading, -canvas.u(SeleneTokens.Space.hairline))
            }
        }
        .padding(.horizontal, canvas.u(horizontalPadding))
        .frame(minWidth: canvas.u(minWidth), maxWidth: fillsWidth ? .infinity : nil,
               minHeight: canvas.u(height), maxHeight: canvas.u(height))
        let capsule = label
            .foregroundColor(downloadFill != nil ? .white : solid ? SeleneTheme.onFocus
                             : (enabled ? tint ?? SeleneTheme.ink : SeleneTheme.ink60))
            .background(OortKeyFace(kind: solid ? .solid : .quiet, radius: radius,
                                    lit: enabled && downloadFill == nil && (focused || hovered),
                                    outlined: focused, tint: tint))
            .overlay {
                if let downloadFill {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(SeleneTheme.artInk)
                        .overlay { label.foregroundColor(SeleneTheme.artShade) }
                        // One moving edge clips both the white fill and the black glyphs.
                        .mask { DownloadFillMask(fraction: downloadFill) }
                        .animation(Motion.transfer(reduceMotion), value: downloadFill)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(scalesOnFocus && focused && !reduceMotion ? 1.06 : 1)
            // Focus eases across pills; the colour change is a fade, so it stays under reduce motion.
            .animation(SeleneTheme.cubicOut(0.26), value: focused)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        if passive {
            capsule
        } else {
            Button(action: action) { capsule }
                .buttonStyle(OortPressStyle())
                .oortPadPress(focused)
        }
    }
}

struct PillOutline: Shape {
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        // AppKit's display cache can draw spurs at the seams of Capsule.strokeBorder.
        var ring = Capsule().path(in: rect)
        let inner = rect.insetBy(dx: width, dy: width)
        if !inner.isEmpty { ring.addPath(Capsule().path(in: inner)) }
        return ring
    }
}

private struct DownloadFillMask: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height))
    }
}

/// Three small dots, each rising and falling a little after the one before, like
/// the crest of a wave. Still with Reduce motion.
struct WaveDots: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = reduceMotion ? 0 : max(0, sin((time / 1.1) * 2 * .pi - Double(index) * 0.9))
                    Circle()
                        .frame(width: canvas.u(5), height: canvas.u(5))
                        .offset(y: canvas.u(-5) * wave)
                        .opacity(SeleneTokens.Alpha.veil + 0.45 * wave)
                }
            }
            .frame(height: canvas.u(14), alignment: .bottom)
            .padding(.top, canvas.u(SeleneTokens.Space.tight))
        }
        .accessibilityHidden(true)
    }
}
