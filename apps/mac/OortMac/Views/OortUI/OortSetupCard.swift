import SwiftUI
import OortLibrary

/// A first-launch card row: icon, title, detail and what sits on the right. Focus draws the outline and glow.
struct SetupCardRow: View {
    enum Trailing { case chevron, text(String), toggle(Bool), none }

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let title: String
    let detail: String
    var note: String? = nil
    let icon: MaterialIcon
    var badges: [String] = []
    var platform: PlatformKind? = nil
    var trailing: Trailing = .chevron
    var height: CGFloat = 112
    let focused: Bool
    var enabled: Bool = true
    var onHover: () -> Void = {}
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: canvas.u(SeleneTokens.Space.large)) {
                if platform == nil { MaterialIconView(icon, size: 30).frame(width: canvas.u(40)) }
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                    if let platform {
                        PlatformLabel(platform, title: title, preset: .setup)
                    } else {
                        Text(title).seleneFont(.row, .semibold)
                    }
                    if !detail.isEmpty {
                        Text(detail).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                            .lineLimit(badges.isEmpty ? 2 : nil).truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    OortFormatBadges(labels: badges)
                    if let note {
                        Text(note).seleneFont(.badge).foregroundColor(SeleneTheme.ink60).padding(.top, canvas.u(SeleneTokens.Space.seam))
                    }
                }
                Spacer(minLength: canvas.u(12))
                switch trailing {
                case .chevron: MaterialIconView(.chevron, size: 22)
                case .text(let text): Text(text).seleneFont(.text, .semibold)
                case .toggle(let isOn): SeleneSwitch(isOn: .constant(isOn)).allowsHitTesting(false)
                case .none: EmptyView()
                }
            }
            .foregroundColor(SeleneTheme.ink)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.large))
            .frame(width: canvas.u(960))
            .frame(minHeight: canvas.u(height))
            .padding(.vertical, badges.isEmpty ? 0 : canvas.u(SeleneTokens.Space.compact))
            .oortPanel(radius: canvas.u(SeleneTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.cardRadius), style: .continuous)
                .strokeBorder(focused ? SeleneTheme.focus : .clear, lineWidth: canvas.u(SeleneTokens.Space.focusStroke)))
            .oortGlow(focused)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(OortPressStyle())
        .oortPadPress(focused)
        .disabled(!enabled)
        .seleneHover { onHover() }
        .animation(reduceMotion ? nil : SeleneTheme.focusIn, value: focused)
    }
}
