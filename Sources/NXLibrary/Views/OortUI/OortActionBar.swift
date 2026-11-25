import SwiftUI
import NXLibraryCore

/// The foot of a panel or a question: the way back on the left, the way forward last on the right.
struct OortActionBar: View {
    struct Action: Identifiable {
        let id: AnyHashable
        let title: String
        var arguments: [String] = []
        let role: ActionBarRole
        var enabled = true
        let perform: () -> Void
    }

    let actions: [Action]
    let focused: AnyHashable?
    let onFocus: (AnyHashable) -> Void
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        let sorted = ActionBarOrder.sorted(actions, role: \.role)
        let leading = sorted.filter(\.role.isLeading), trailing = sorted.filter { !$0.role.isLeading }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                ForEach(leading) { key($0) }
                Spacer(minLength: canvas.u(SeleneTokens.Space.group))
                ForEach(trailing) { key($0) }
            }
            // Too narrow for one line: the way back keeps the left, the way forward keeps the right, one line each.
            VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                    Spacer(minLength: 0)
                    ForEach(trailing) { key($0) }
                }
                HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                    ForEach(leading) { key($0) }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func key(_ action: Action) -> some View {
        OortButton(title: action.title, arguments: action.arguments, focused: focused == action.id,
                   state: action.enabled ? .ready : .blocked, tone: action.role == .destructive ? .destructive : .normal,
                   action: action.perform)
            .disabled(!action.enabled)
            .seleneHover { if action.enabled { onFocus(action.id) } }
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
