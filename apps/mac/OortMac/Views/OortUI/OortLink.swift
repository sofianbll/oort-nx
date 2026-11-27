import SwiftUI
import NXLibraryCore

/// A link among a dialog's fields: a click, or Tab then Return. Tab goes through the fields and the links in order.
struct OortLink: View {
    @Environment(\.nxAppLocale) private var localization
    @FocusState private var focused: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(L10n.text(title, context: localization), action: action)
            .buttonStyle(OortPressStyle())
            .seleneFont(.text)
            .foregroundColor(SeleneTheme.focus)
            .seleneKeyRing(focused)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.return, .space, KeyEquivalent("\u{3}")]) { _ in
                action()
                return .handled
            }
    }
}
