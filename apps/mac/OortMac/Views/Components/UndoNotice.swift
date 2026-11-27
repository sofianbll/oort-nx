import OortLibrary
import SwiftUI

/// What a notice says, how its keys are reached, and the keys. The keys light only once they were asked for: the
/// screen keeps its focus until then, and takes it back as it was.
private struct NoticeLayout: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @ObservedObject private var controller = GameControllerService.shared
    @AccessibilityFocusState private var spoken: Int?
    let message: String
    let detail: String
    var badge: PromptButton? = nil
    var badgeKey: KeyCap? = nil
    let keys: [NoticeKey]
    let focus: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.control)) {
            HStack(spacing: canvas.u(SeleneTokens.Space.gap)) {
                if let badge { SelenePromptBadge(button: badge, keyboardOverride: badgeKey).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                    Text(message)
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(2)
                    Text(detail)
                        .seleneFont(.text)
                        .foregroundColor(SeleneTheme.ink75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                // One key sits beside its words, several take the row below.
                if keys.count == 1 { key(0) }
            }
            if keys.count > 1 || focus == nil {
                HStack(spacing: canvas.u(SeleneTokens.Space.gap)) {
                    if keys.count > 1 {
                        ForEach(keys.indices, id: \.self) { key($0) }
                        Spacer(minLength: 0)
                    }
                    if focus == nil {
                        HStack(spacing: canvas.u(SeleneTokens.Space.gap)) {
                            SelenePromptBadge(button: .x, keyboardOverride: .symbol("arrow.right.to.line"))
                            Text(hint)
                                .seleneFont(.text)
                                .foregroundColor(SeleneTheme.ink75)
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.panel))
        .padding(.vertical, canvas.u(SeleneTokens.Space.control))
        .frame(width: canvas.u(SeleneTokens.Space.sidePanel))
        .fixedSize(horizontal: false, vertical: true)
        .oortPanel(radius: canvas.u(SeleneTokens.Radius.badge), floats: true)
        .onChange(of: focus) { _, index in spoken = index }
    }

    private func key(_ index: Int) -> some View {
        OortButton(title: keys[index].title, focused: focus == index, preset: .compact, action: keys[index].press)
            .accessibilityHint(message)
            .accessibilityFocused($spoken, equals: index)
    }

    private var hint: String {
        let choose = L10n.text("Choose", context: localization)
        return controller.controllerInHand ? L10n.format("Hold: %@", [choose], context: localization) : choose
    }
}

struct NoticeKey {
    let title: String
    let press: () -> Void
}

/// The last reversible gesture and its Undo key. ⌘Z and Activity keep the way back after the notice leaves.
struct UndoNotice: View {
    @Environment(\.nxAppLocale) private var localization
    @ObservedObject private var controller = GameControllerService.shared
    let message: String
    var focus: Int? = nil
    let onUndo: () -> Void

    var body: some View {
        NoticeLayout(message: message,
                   detail: L10n.text(controller.controllerInHand ? "Undo: Activity center" : "Undo: ⌘Z or Activity center",
                                     context: localization),
                   keys: [.init(title: "Undo", press: onUndo)], focus: focus)
    }
}

/// A shortcut told once. Got it, or no more tips; the same switch is in Settings → Controllers.
struct TipNotice: View {
    @Environment(\.nxAppLocale) private var localization
    let tip: Tip
    var focus: Int? = nil
    let onClose: () -> Void
    let onTurnOff: () -> Void

    var body: some View {
        NoticeLayout(message: L10n.text(tip.message, context: localization), detail: L10n.text(tip.detail, context: localization),
                   badge: tip == .search ? .ls : nil, badgeKey: .text("⌘F"),
                   keys: [.init(title: "Got it", press: onClose), .init(title: "No more tips", press: onTurnOff)], focus: focus)
    }
}

/// Its place: the session card's corner, below that card when both are there.
struct UndoNoticeLayer: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @ObservedObject var offers: UndoOffers
    @ObservedObject var tips: Tips
    let isBlocked: Bool
    let isBelowCard: Bool
    @Binding var focus: NoticeFocus
    let onUndo: () -> Void
    let onTurnOffTips: () -> Void
    @State private var hovered = false

    /// What was just done comes before a tip.
    private var shownOffer: UndoOffers.Offer? { offers.isShown && !isBlocked ? offers.offer : nil }
    private var shownTip: Tip? { shownOffer == nil && !isBlocked ? tips.shown : nil }
    private var shown: [String] { [shownOffer?.id.uuidString, shownTip?.rawValue].compactMap { $0 } }
    private var keyTitle: String {
        if shownOffer != nil { return "Undo" }
        return focus.index == 1 ? "No more tips" : "Got it"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // A click anywhere else gives the screen back.
            if focus.isActive && !isBlocked {
                Color.clear.contentShape(Rectangle()).onTapGesture { focus.leave() }.accessibilityHidden(true)
            }
            card
                .onHover { hovered = $0 }
                .padding(.top, canvas.u(isBelowCard ? SeleneTokens.Space.toastTop * 2 + SeleneTokens.Space.panel : SeleneTokens.Space.toastTop))
                .padding(.trailing, canvas.u(SeleneTokens.Space.feature))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .overlay(alignment: .bottom) {
            if focus.isActive && !isBlocked {
                SeleneHintsBar(left: [HintItem(.b, "Back", action: { focus.leave() })],
                               right: [HintItem(.a, L10n.text(keyTitle, context: localization))], bottom: SeleneBottomScrim.hintsBottom)
            }
        }
        .animation(Motion.toast(reduceMotion), value: shown)
        // Read at one's own pace: it stays while it is chosen, under the pointer and with VoiceOver.
        .task(id: shown + [String(hovered || focus.isActive)]) {
            guard !shown.isEmpty, !hovered, !focus.isActive, !voiceOver else { return }
            try? await Task.sleep(for: .seconds(SeleneTokens.Motion.notice))
            guard !Task.isCancelled else { return }
            if let offer = shownOffer { offers.hide(offer.id) } else { tips.dismiss() }
        }
        .onChange(of: shown) {
            hovered = false
            focus.leave()
        }
        .onChange(of: offers.offer?.id) {
            guard let message = offers.offer?.message else { return }
            announce([message, "Undo: ⌘Z or Activity center"])
        }
        .onChange(of: tips.shown) {
            guard let tip = tips.shown else { return }
            announce([tip.message, tip.detail])
        }
    }

    private var card: some View {
        ZStack(alignment: .topTrailing) {
            if let offer = shownOffer {
                UndoNotice(message: offer.message, focus: focus.index, onUndo: onUndo)
                    .id(offer.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: canvas.u(SeleneTokens.Space.panel))))
            } else if let tip = shownTip {
                TipNotice(tip: tip, focus: focus.index, onClose: tips.dismiss, onTurnOff: onTurnOffTips)
                    .transition(.opacity)
            }
        }
    }

    private func announce(_ keys: [String]) {
        AccessibilityNotification.Announcement(keys.map { L10n.text($0, context: localization) }.joined(separator: ". ")).post()
    }
}
