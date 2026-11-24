import SwiftUI
import NXLibraryCore

/// The stages of a Selene dialog, with the current stage also exposed to VoiceOver.
struct SeleneStepper: View {
    @Environment(\.seleneCanvas) private var canvas
    let labels: [String]
    let active: Int

    var body: some View {
        HStack(spacing: canvas.u(10)) {
            ForEach(labels.indices, id: \.self) { index in
                if index > 0 {
                    Capsule().fill(SeleneTheme.ink15).frame(width: canvas.u(22), height: canvas.u(1))
                }
                Text("\(index + 1). \(labels[index])").seleneFont(.compactCaption, .semibold)
                    .foregroundColor(index == active ? SeleneTheme.onFocus : SeleneTheme.ink75)
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.small)).padding(.vertical, canvas.u(SeleneTokens.Space.tight))
                    .background(index == active ? SeleneTheme.focus : SeleneTheme.glass, in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

struct OortField: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    let focused: Bool

    func body(content: Content) -> some View {
        let radius = canvas.u(SeleneTheme.rowRadius)
        content.textFieldStyle(.plain).seleneFont(.body)
            .foregroundColor(SeleneTheme.ink)
            .padding(canvas.u(SeleneTokens.Space.fieldInset))
            .background(SeleneTheme.glassLight, in: RoundedRectangle(cornerRadius: radius))
            .seleneRowFocus(focused, radius: radius)
    }
}

typealias SeleneFieldSurface = OortField
