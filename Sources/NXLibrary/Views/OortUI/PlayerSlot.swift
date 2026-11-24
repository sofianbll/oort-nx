import SwiftUI
import NXLibraryCore

struct OortPlayerSlot<Portrait: View>: View {
    @Environment(\.seleneCanvas) private var canvas
    let title: String
    let detail: String
    let accessibilityTitle: String
    let accessibilityValue: String
    let focused: Bool
    let selected: Bool
    let marked: Bool
    let action: () -> Void
    @ViewBuilder let portrait: () -> Portrait

    var body: some View {
        Button(action: action) {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                portrait().accessibilityHidden(true)
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
                    Text(title).seleneFont(.row, .semibold)
                        .foregroundStyle(SeleneTheme.ink).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail).seleneFont(.text)
                        .foregroundStyle(SeleneTheme.ink82).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if marked {
                    MaterialIconView(.done, size: SeleneTokens.Space.large)
                        .foregroundStyle(SeleneTheme.glyph)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: canvas.u(SeleneTokens.Space.playerSlotContent))
            .modifier(SeleneOptionRowSurface(focused: focused))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
