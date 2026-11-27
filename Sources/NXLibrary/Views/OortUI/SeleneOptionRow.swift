import SwiftUI
import NXLibraryCore

struct SeleneOptionRow<Trailing: View>: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.oortGroupedRow) private var grouped
    @Environment(\.screenTrace) private var trace
    @State private var hovered = false

    let icon: MaterialIcon?
    let title: String
    let about: String?
    let focused: Bool
    var destructive = false
    /// False draws the row dim (ink60 text and icon), as Selene's disabled pills do. It still takes focus.
    var enabled = true
    /// Opt-in focus expansion; other option screens keep their existing layout.
    var aboutPreview: String? = nil
    var leading: AnyView? = nil
    var titleAccessory: AnyView? = nil
    var truncateAboutInMiddle = false
    var aboutFont: SeleneTokens.Text = .text
    var titleFont: SeleneTokens.Text = .row
    var platform: PlatformKind? = nil
    /// False: the line is data (a path, a state), not an explanation, and stays on the row.
    var aboutIsHelp = true
    /// The line is read as body text (what an entry sends, before it is turned on), not discreet.
    var aboutIsBody = false
    var formatBadges: [String] = []
    var detail: AnyView? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Group {
            if let detail {
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                    row
                    detail.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                row
            }
        }
        .modifier(SeleneOptionRowSurface(focused: focused))
        .onHover { hovered = $0 }
        .preference(key: OortRowHelpKey.self, value: grouped && aboutIsHelp && (focused || hovered) ? about : nil)
        .accessibilityHint(grouped && aboutIsHelp ? about ?? "" : "")
        .containerValue(\.oortSettingsRow, true)
        .screenTrace(trace, [.init(kind: .row, text: title, about: grouped && aboutIsHelp ? nil : about, focused: focused,
                                    role: aboutIsBody ? .body : .about)])
    }

    private var row: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.control)) {
            leading
            if let icon {
                MaterialIconView(icon, size: 24)
                    .foregroundColor(destructive ? SeleneTheme.danger : (enabled ? SeleneTheme.rowIcon : SeleneTheme.ink60))
            }
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.segmentInset)) {
                HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                    Group {
                        if let platform {
                            PlatformLabel(platform, title: title, preset: .row)
                        } else {
                            Text(title).seleneFont(titleFont, .medium)
                        }
                    }
                    .foregroundColor(destructive ? SeleneTheme.danger : (enabled ? SeleneTheme.ink : SeleneTheme.ink60))
                    titleAccessory
                }
                if let about, !(grouped && aboutIsHelp) {
                    Group {
                        if let aboutPreview {
                            SeleneExpandableText(text: about, preview: aboutPreview, expanded: focused)
                        } else {
                            Text(verbatim: about)
                                .lineLimit(truncateAboutInMiddle ? 1 : nil)
                                .truncationMode(truncateAboutInMiddle ? .middle : .tail)
                        }
                    }
                    .seleneFont(aboutFont)
                        .foregroundColor(aboutIsBody ? SeleneTheme.ink : SeleneTheme.ink60)
                        .fixedSize(horizontal: false, vertical: true)
                }
                OortFormatBadges(labels: formatBadges)
            }
            Spacer(minLength: canvas.u(16))
            trailing()
        }
    }
}

/// The option row's shell, also used when progress needs a full-width line below the content.
struct SeleneOptionRowSurface: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.oortGroupedRow) private var grouped
    let focused: Bool

    func body(content: Content) -> some View {
        let radius = canvas.u(SeleneTokens.Radius.card)
        content
            .padding(.leading, canvas.u(SeleneTokens.Space.rowLeading))
            .padding(.trailing, canvas.u(SeleneTokens.Space.large))
            .padding(.vertical, canvas.u(grouped ? SeleneTokens.Space.line : SeleneTokens.Space.control))
            .background { if !grouped { Color.clear.oortPanel(radius: radius) } }
            .background {
                if focused {
                    OortDots(rise: 1, color: SeleneTheme.glyph.opacity(SeleneTokens.Effect.surfaceLine))
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
            }
            .seleneRowFocus(focused, radius: radius)
            .oortPadPress(focused)
    }
}
