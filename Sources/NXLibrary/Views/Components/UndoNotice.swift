import NXLibraryCore
import SwiftUI

/// The last reversible gesture and its Undo key, in the shared panel. It never takes the focus: the keyboard has
/// ⌘Z and the controller has Activity, which keep the way back after the notice leaves.
struct UndoNotice: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @ObservedObject private var controller = GameControllerService.shared
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                Text(message)
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(2)
                Text(L10n.text(controller.isGamepadConnected ? "Undo: Activity center" : "Undo: ⌘Z or Activity center", context: localization))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            OortButton(title: "Undo", focused: false, preset: .compact, action: onUndo)
                .accessibilityHint(message)
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.panel))
        .padding(.vertical, canvas.u(SeleneTokens.Space.control))
        .frame(width: canvas.u(SeleneTokens.Space.sidePanel))
        .oortPanel(radius: canvas.u(SeleneTokens.Radius.badge), floats: true)
    }
}

/// Its place: the session card's corner, below that card when both are there.
struct UndoNoticeLayer: View {
    static let hold: Duration = .seconds(8)

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @ObservedObject var offers: UndoOffers
    let isBlocked: Bool
    let isBelowCard: Bool
    let onUndo: () -> Void
    @State private var hovered = false

    var body: some View {
        let shown = offers.isShown && !isBlocked ? offers.offer : nil
        ZStack(alignment: .topTrailing) {
            if let shown {
                UndoNotice(message: shown.message, onUndo: onUndo)
                    .onHover { hovered = $0 }
                    .id(shown.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: canvas.u(SeleneTokens.Space.panel))))
                    // Read at one's own pace: it stays under the pointer and with VoiceOver.
                    .task(id: hovered) {
                        guard !hovered, !voiceOver else { return }
                        try? await Task.sleep(for: Self.hold)
                        if !Task.isCancelled { offers.hide(shown.id) }
                    }
            }
        }
        .padding(.top, canvas.u(SeleneTokens.Space.toastTop) * (isBelowCard ? 2.4 : 1))
        .padding(.trailing, canvas.u(SeleneTokens.Space.feature))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(Motion.toast(reduceMotion), value: shown)
        .onChange(of: offers.offer?.id) {
            hovered = false
            guard let message = offers.offer?.message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
