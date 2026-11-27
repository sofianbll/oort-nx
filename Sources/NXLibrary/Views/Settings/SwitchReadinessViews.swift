import SwiftUI
import NXLibraryCore
import ArcanePorting

/// Proposal (feat/proposition-accueil-ryujinx): how a prerequisite's state reads, the same on every screen
/// (Settings › Switch, First steps, Add game): a mark, a short state, and one sentence when something is to do.
extension SwitchReadiness.Tone {
    var color: Color {
        switch self {
        case .ready: return SeleneTheme.statusOK
        case .todo: return SeleneTheme.ink75
        case .optional: return SeleneTheme.ink60
        case .warning: return SeleneTheme.untested
        case .problem: return SeleneTheme.danger
        }
    }

    var symbol: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .todo: return "circle.dashed"
        case .optional: return "minus.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        }
    }
}

struct ReadinessStatus: View {
    let line: SwitchReadiness.Line
    var showsDetail = true

    var body: some View {
        VStack(alignment: .leading, spacing: SeleneTokens.Space.hairline) {
            HStack(spacing: SeleneTokens.Space.compact) {
                Image(systemName: line.tone.symbol)
                    .seleneFont(.text, .bold)
                    .foregroundColor(line.tone.color)
                    .accessibilityHidden(true)
                Text(line.title)
                    .seleneFont(.text, .semibold)
                    .foregroundColor(line.tone == .problem ? SeleneTheme.danger : SeleneTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsDetail, let detail = line.detail {
                Text(detail)
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink75)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A text button of a settings row, as the rows already draw them.
struct ReadinessButton: View {
    let title: String
    var secondary = false
    var focused = false
    let action: () -> Void

    var body: some View {
        Button(L10n.text(title), action: action)
            .buttonStyle(OortPressStyle())
            .seleneFont(.text, .semibold)
            .foregroundColor(secondary ? SeleneTheme.ink60 : SeleneTheme.glyph)
            .seleneKeyRing(focused)
    }
}
