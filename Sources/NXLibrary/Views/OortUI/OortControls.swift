import SwiftUI
import NXLibraryCore

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
    enum Preset { case body, quiet }

    let text: String
    var preset: Preset = .body

    var body: some View {
        Text(text).seleneFont(preset == .body ? .text : .badge)
            .foregroundStyle(preset == .body ? SeleneTheme.ink : SeleneTheme.ink75)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct OortButton: View {
    enum Preset { case action, compact }
    enum State { case ready, blocked, busy }

    let title: String
    var focused = false
    var state: State = .ready
    var preset: Preset = .action
    let action: () -> Void

    var body: some View {
        SelenePillButton(title: title, minWidth: preset == .compact ? 0 : SeleneTokens.Space.pillWidth,
                         height: preset == .compact ? SeleneTokens.Space.compactPillHeight : SeleneTokens.Space.pillHeight,
                         titleSize: preset == .compact ? .text : .row,
                         horizontalPadding: preset == .compact ? SeleneTokens.Space.medium : SeleneTokens.Space.pillInset,
                         focused: focused, scalesOnFocus: preset != .compact,
                         enabled: state != .blocked, waveDots: state == .busy) {
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
                Slider(value: $value, in: range, step: step)
                    .frame(width: canvas.u(SeleneTokens.Space.sliderMeasure))
                    .accessibilityLabel(L10n.text(title, context: localization))
                SeleneValueChip(text: displayValue).accessibilityHidden(true)
            }
        }
    }
}
