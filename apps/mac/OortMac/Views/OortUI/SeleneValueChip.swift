import SwiftUI
import OortLibrary

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
            .seleneFont(.text, .semibold)
            .foregroundColor(SeleneTheme.ink)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, canvas.u(symbol == nil ? 16 : 9))
            .padding(.top, canvas.u(SeleneTokens.Space.hairline))
            .padding(.bottom, canvas.u(SeleneTokens.Space.chipBottom))
            .oortPanel(radius: canvas.u(SeleneTokens.Radius.chip), raised: true)
    }
}
