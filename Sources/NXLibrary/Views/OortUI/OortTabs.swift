import SwiftUI
import NXLibraryCore

/// One pill glides from tab to tab. LB and RB move it, a click chooses; the caller owns what is chosen.
struct OortTabs<ID: Hashable>: View {
    struct Item {
        let id: ID
        let title: String
        var icon: MaterialIcon? = nil
        var count: Int? = nil
    }

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Namespace private var pill
    let items: [Item]
    let selected: ID?
    /// Set where Left and Right move a focus apart from the choice.
    var focused: ID? = nil
    /// What VoiceOver says for an item, when its title alone is not enough.
    var label: (Item) -> String = { $0.title }
    let select: (ID) -> Void

    var body: some View {
        HStack(spacing: 0) { ForEach(items, id: \.id, content: tab) }
            .padding(canvas.u(SeleneTokens.Space.hairline))
            .oortPanel(radius: canvas.u(SeleneTokens.Radius.hint) * 2)
            .animation(reduceMotion ? nil : Motion.dots(false), value: selected)
    }

    private func tab(_ item: Item) -> some View {
        let on = item.id == selected
        return HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            if let icon = item.icon {
                MaterialIconView(icon, size: SeleneTokens.Space.panel)
            }
            Text(item.title).seleneFont(.text, on ? .semibold : .regular)
            if let count = item.count {
                Text(count, format: .number)
                    .seleneFont(.text)
                    .monospacedDigit()
                    .opacity(SeleneTokens.Alpha.strong)
            }
        }
        .lineLimit(1)
        .foregroundStyle(on ? SeleneTheme.onFocus : SeleneTheme.ink75)
        .padding(.horizontal, canvas.u(SeleneTokens.Space.control))
        .padding(.top, canvas.u(SeleneTokens.Space.chipBottom))
        .padding(.bottom, canvas.u(SeleneTokens.Space.badge))
        .background {
            if on {
                Capsule().fill(LinearGradient(colors: [SeleneTheme.focus, SeleneTheme.focus.mix(with: SeleneTheme.glyph, by: SeleneTokens.Effect.surfaceLineStrong)],
                                              startPoint: .top, endPoint: .bottom))
                    .matchedGeometryEffect(id: "tab", in: pill)
            }
        }
        .overlay {
            Capsule().strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(SeleneTokens.Space.focusStroke))
                .padding(canvas.u(on ? -SeleneTokens.Space.hairline : 0))
                .opacity(focused == item.id ? 1 : 0)
                .animation(Motion.focus(reduceMotion), value: focused)
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.seam))
        .contentShape(Rectangle())
        .onTapGesture { select(item.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(item))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(item.id) }
        .id(item.id)
    }
}
