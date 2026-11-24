import SwiftUI
import NXLibraryCore

struct SeleneValueChip: View {
    @Environment(\.seleneCanvas) private var canvas
    let text: String
    var symbol: String? = nil

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol).accessibilityLabel(text)
            } else {
                Text(text)
            }
        }
            .seleneFont(.body, .semibold)
            .foregroundColor(SeleneTheme.ink)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, canvas.u(symbol == nil ? 16 : 9))
            .padding(.top, canvas.u(SeleneTokens.Space.hairline))
            .padding(.bottom, canvas.u(SeleneTokens.Space.chipBottom))
            .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.chip), style: .continuous)
                .fill(symbol == nil ? SeleneTheme.ink.opacity(0.13) : SeleneTheme.glassSolid))
    }
}
