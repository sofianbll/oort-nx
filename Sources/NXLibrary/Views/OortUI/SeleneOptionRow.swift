import SwiftUI
import NXLibraryCore

struct SeleneOptionRow<Trailing: View>: View {
    @Environment(\.seleneCanvas) private var canvas

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
    var platform: PlatformKind? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: canvas.u(18)) {
            leading
            if let icon {
                MaterialIconView(icon, size: 24)
                    .foregroundColor(destructive ? SeleneTheme.danger : (enabled ? SeleneTheme.rowIcon : SeleneTheme.ink60))
            }
            VStack(alignment: .leading, spacing: canvas.u(3)) {
                HStack(spacing: canvas.u(8)) {
                    Group {
                        if let platform {
                            PlatformLabel(platform, title: title, preset: .row)
                        } else {
                            Text(title).seleneFont(.row, .medium)
                        }
                    }
                    .foregroundColor(destructive ? SeleneTheme.danger : (enabled ? SeleneTheme.ink : SeleneTheme.ink60))
                    titleAccessory
                }
                if let about {
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
                        .foregroundColor(SeleneTheme.ink60)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: canvas.u(16))
            trailing()
        }
        .modifier(SeleneOptionRowSurface(focused: focused))
    }
}

/// The option row's shell, also used when progress needs a full-width line below the content.
struct SeleneOptionRowSurface: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    let focused: Bool

    func body(content: Content) -> some View {
        let radius = canvas.u(16)
        content
            .padding(.leading, canvas.u(SeleneTokens.Space.rowLeading))
            .padding(.trailing, canvas.u(SeleneTokens.Space.large))
            .padding(.vertical, canvas.u(SeleneTokens.Space.control))
            .background(SeleneTheme.glass, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .seleneRowFocus(focused, radius: radius)
    }
}
