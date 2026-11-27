import SwiftUI
import OortLibrary
import ArcanePorting

struct CloudPersonalAppUpdateRow: View {
    @Environment(\.nxAppLocale) private var locale
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneShowButtonHints) private var showHints
    @Environment(\.seleneHintsCovered) private var covered
    @State private var hovered = false

    let comparison: PersonalAppReceipt.Comparison?
    let keepsStatus: Bool
    let canUpdate: Bool
    let status: SeleneStatusDot
    let onUpdate: () -> Void

    var body: some View {
        switch comparison {
        case .update(let offer):
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                if keepsStatus { status }
                let bytes = offer.downloadBytes.formatted(.byteCount(style: .file).locale(locale.formatLocale))
                SeleneStatusDot(text: L10n.text("Update available", context: locale) + " · " + bytes,
                                color: SeleneTheme.statusCloud, labelColor: SeleneTheme.ink90)
                SelenePillButton(title: "Update from my cloud", minWidth: 0, height: 40,
                                 titleSize: .text, horizontalPadding: 14, focused: hovered, enabled: canUpdate,
                                 accessory: showHints && !covered ? AnyView(
                                    SelenePromptBadge(button: .x, height: 22, keyboardOverride: .text("⌘U"))
                                        .accessibilityHidden(true)) : nil, action: review)
                    .disabled(!canUpdate || covered)
                    .onHover { hovered = $0 }
                    .keyboardShortcut("u", modifiers: .command)
                    .onReceive(NotificationCenter.default.publisher(for: .nxCloudLibraryGamepadAction)) { note in
                        if note.object as? GamepadAction == .secondaryAction { review() }
                    }
            }
        case .different:
            if keepsStatus { status }
            SeleneStatusDot(text: L10n.text("Copies are different", context: locale),
                            color: SeleneTheme.ink60, labelColor: SeleneTheme.ink90)
        default:
            status
        }
    }

    private func review() {
        if canUpdate && !covered { onUpdate() }
    }
}
