import SwiftUI
import NXLibraryCore

struct OortFormatBadges: View {
    @Environment(\.seleneCanvas) private var canvas
    let labels: [String]

    var body: some View {
        if !labels.isEmpty {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                ForEach(labels, id: \.self) { SeleneValueChip(text: $0) }
            }
        }
    }
}

/// Selectable and passive rows share the existing Selene option-row surface.
struct OortRow: View {
    enum Preset {
        case navigation(label: String, action: () -> Void)
        case info
    }

    let title: String
    let platform: PlatformKind?
    var status: String?
    var focused = false
    var tone: OortStatus.Tone = .neutral
    let preset: Preset

    var body: some View {
        switch preset {
        case .navigation(let label, let action):
            Button(action: action) {
                row {
                    Image(systemName: "chevron.right").seleneFont(.text, .semibold)
                        .foregroundStyle(SeleneTheme.glyph).accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(status ?? "")
            .accessibilityHint(label)
            .accessibilityAddTraits(focused ? .isSelected : [])
        case .info:
            row { EmptyView() }
                .accessibilityElement(children: .combine)
        }
    }

    private func row<Trailing: View>(@ViewBuilder trailing: @escaping () -> Trailing) -> some View {
        SeleneOptionRow(icon: nil, title: title, about: nil, focused: focused,
                        platform: platform) {
            HStack {
                if let status {
                    OortStatus(text: status, tone: tone)
                }
                trailing()
            }
        }
    }
}

struct OortReadout: View {
    /// `lead` is the explanation under a large heading.
    enum Preset { case body, quiet, lead }

    let text: String
    var preset: Preset = .body

    var body: some View {
        Text(text).seleneFont(preset == .body ? .text : preset == .lead ? .row : .badge)
            .foregroundStyle(preset == .body ? SeleneTheme.ink : preset == .lead ? SeleneTheme.ink82 : SeleneTheme.ink75)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct OortButton: View {
    /// `card` is an action's height and text, as narrow as its words.
    enum Preset { case action, card, compact }
    enum State { case ready, blocked, busy }
    enum Tone { case normal, destructive }

    let title: String
    /// The parts of the title that are not words of Oort: a folder's own name is never translated.
    var arguments: [String] = []
    var focused = false
    var state: State = .ready
    var preset: Preset = .action
    var fillsWidth = false
    var tone: Tone = .normal
    let action: () -> Void

    var body: some View {
        SelenePillButton(title: title, titleArguments: arguments, minWidth: preset == .action ? SeleneTokens.Space.pillWidth : 0,
                         fillsWidth: fillsWidth,
                         height: preset == .compact ? SeleneTokens.Space.compactPillHeight
                             : preset == .card ? SeleneTokens.Space.actionPillHeight : SeleneTokens.Space.pillHeight,
                         titleSize: preset == .compact ? .text : .row,
                         horizontalPadding: preset == .compact ? SeleneTokens.Space.medium
                             : preset == .card ? SeleneTokens.Space.large : SeleneTokens.Space.pillInset,
                         focused: focused, scalesOnFocus: preset == .action,
                         enabled: state != .blocked, waveDots: state == .busy,
                         tint: tone == .destructive ? SeleneTheme.dangerText : nil) {
            guard state == .ready else { return }
            action()
        }
        .accessibilityAddTraits(focused ? .isSelected : [])
    }
}

struct OortStatus: View {
    enum Tone {
        case neutral, working, attention, ready

        var color: Color {
            switch self {
            case .neutral: SeleneTheme.ink75
            case .working: SeleneTheme.statusCloud
            case .attention: SeleneTheme.untested
            case .ready: SeleneTheme.statusOK
            }
        }
    }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        SeleneStatusDot(text: text, color: tone.color, labelColor: SeleneTheme.ink90, pulses: tone == .working)
    }
}

struct OortSliderRow: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let displayValue: String

    var body: some View {
        SeleneRow(title, subtitle: subtitle) {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                OortSlider(value: $value, range: range, step: step)
                    .frame(width: canvas.u(SeleneTokens.Space.sliderMeasure))
                    .accessibilityLabel(L10n.text(title, context: localization))
                SeleneValueChip(text: displayValue).accessibilityHidden(true)
            }
        }
    }
}

/// A track of dots that lights up to the knob. The system slider stays underneath for keyboard and VoiceOver.
struct OortSlider: View {
    @Environment(\.seleneCanvas) private var canvas
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { geometry in
            let knob = canvas.u(SeleneTokens.Space.large)
            let span = max(1, geometry.size.width - knob)
            let fraction = range.upperBound > range.lowerBound ? (value - range.lowerBound) / (range.upperBound - range.lowerBound) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(SeleneTheme.panelRaised).frame(height: canvas.u(SeleneTokens.Space.small))
                OortDots(rise: 1, color: SeleneTheme.ink).frame(height: canvas.u(SeleneTokens.Effect.dotPitch))
                    .mask(alignment: .leading) { Rectangle().frame(width: max(0, fraction * span + knob / 2)) }
                Circle()
                    .fill(LinearGradient(colors: [SeleneTheme.focus, SeleneTheme.focus.mix(with: SeleneTheme.glyph, by: SeleneTokens.Effect.surfaceLineStrong)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: knob, height: knob)
                    .offset(x: fraction * span)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let raw = range.lowerBound + min(1, max(0, (drag.location.x - knob / 2) / span)) * (range.upperBound - range.lowerBound)
                value = min(range.upperBound, max(range.lowerBound, (raw / step).rounded() * step))
            })
        }
        .frame(height: canvas.u(SeleneTokens.Space.section))
        .accessibilityElement()
        .accessibilityValue("\(Int(((value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound) * 100).rounded())) %")
        .accessibilityAdjustableAction { direction in
            value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step)))
        }
    }
}
