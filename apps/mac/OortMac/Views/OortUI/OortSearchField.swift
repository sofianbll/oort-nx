import SwiftUI
import OortLibrary

/// The one search field: a glass, the caller's text field, and a way to empty it. The caller keeps its focus and submit.
struct OortSearchField<Field: View>: View {
    /// `list` heads a list and follows its columns; `bar` stands alone above a grid.
    enum Preset { case list, bar }

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    @Binding var query: String
    let lit: Bool
    var preset: Preset = .bar
    /// Runs after the field is emptied by its button.
    var onClear: () -> Void = {}
    @ViewBuilder let field: () -> Field

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(preset == .list ? SeleneTokens.Radius.field - SeleneTokens.Space.small : SeleneTokens.Radius.badge), style: .continuous)
        HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            MaterialIconView(.search, size: SeleneTokens.Space.large)
                .foregroundStyle(lit ? SeleneTheme.ink : SeleneTheme.ink60)
                .accessibilityHidden(true)
            field()
                .textFieldStyle(.plain)
                .seleneFont(.row, .medium)
                .foregroundStyle(SeleneTheme.ink)
            if !query.isEmpty {
                Button {
                    query = ""
                    onClear()
                } label: {
                    MaterialIconView(.close, size: SeleneTokens.Space.panel)
                        .foregroundStyle(SeleneTheme.ink60)
                        .contentShape(Rectangle())
                }
                .buttonStyle(OortPressStyle())
                .accessibilityLabel(L10n.text("Clear search", context: locale))
            }
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.panel))
        .padding(.vertical, canvas.u(SeleneTokens.Space.small))
        .background(shape.fill(preset == .list ? SeleneTheme.scrim45 : SeleneTheme.panelHigh))
        .overlay(shape.strokeBorder(lit ? SeleneTheme.focus : SeleneTheme.ink15,
                                    lineWidth: max(1, canvas.u(lit ? SeleneTokens.Space.focusStroke : SeleneTokens.Space.thinStroke))))
        .contentShape(shape)
    }
}
