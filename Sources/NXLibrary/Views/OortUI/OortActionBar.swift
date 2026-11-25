import SwiftUI
import NXLibraryCore

/// The foot of a panel or a question: the way back on the left, the way forward last on the right.
struct OortActionBar: View {
    struct Action: Identifiable {
        let id: AnyHashable
        let title: String
        var arguments: [String] = []
        let role: ActionBarRole
        var detail: String? = nil
        var enabled = true
        let perform: () -> Void
    }

    let actions: [Action]
    let focused: AnyHashable?
    let onFocus: (AnyHashable) -> Void
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        let sorted = ActionBarOrder.sorted(actions, role: \.role)
        let destructive = sorted.filter { $0.role == .destructive }
        let leading = sorted.filter { $0.role == .back }, trailing = sorted.filter { !$0.role.isLeading }
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.dialogActionGap)) {
            ForEach(destructive) { key($0, alignment: .leading) }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.medium)) {
                    ForEach(leading) { key($0, alignment: .leading) }
                    Spacer(minLength: canvas.u(SeleneTokens.Space.group))
                    ForEach(trailing) { key($0, alignment: .trailing) }
                }
                // Too narrow for one line: Back still stays on the left and the way forward on the right.
                VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                    ForEach(leading) { key($0, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(trailing) { key($0, alignment: .trailing).frame(maxWidth: .infinity, alignment: .trailing) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func key(_ action: Action, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: canvas.u(SeleneTokens.Space.compact)) {
            OortButton(title: action.title, arguments: action.arguments, focused: focused == action.id,
                       state: action.enabled ? .ready : .blocked, preset: .card,
                       tone: action.role == .destructive ? .destructive : .normal, action: action.perform)
                .disabled(!action.enabled)
                .accessibilityHint(action.detail ?? "")
                .seleneHover { if action.enabled { onFocus(action.id) } }
            if let detail = action.detail {
                Text(verbatim: detail).seleneFont(.text).foregroundStyle(SeleneTheme.ink75)
                    .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                    .frame(maxWidth: canvas.u(SeleneTokens.Space.metadataList))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// One question over a panel, with the same foot.
struct OortQuestion: View {
    let title: String
    let message: String
    let actions: [OortActionBar.Action]
    let focused: AnyHashable?
    let onFocus: (AnyHashable) -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
            Text(verbatim: title).seleneFont(.screen, .semibold).foregroundStyle(SeleneTheme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: message).seleneFont(.row).foregroundStyle(SeleneTheme.ink82)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            OortActionBar(actions: actions, focused: focused, onFocus: onFocus)
                .padding(.top, canvas.u(SeleneTokens.Space.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SeleneDialogCard(width: SeleneTokens.Space.questionMeasure,
                                   cancelHint: HintItem(.b, "Cancel", action: onCancel),
                                   confirmHint: HintItem(.a, "Select", action: onConfirm)))
        .accessibilityElement(children: .contain)
    }
}
