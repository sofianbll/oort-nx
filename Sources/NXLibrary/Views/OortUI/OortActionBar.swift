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
        /// One line under the key.
        var detail: String? = nil
        let perform: () -> Void
    }

    let actions: [Action]
    let focused: AnyHashable?
    var preset: OortButton.Preset = .action
    /// Apart from edge to edge, or side by side in the middle of a full page.
    var spread = true
    /// One key a line: the way forward on top, what erases then the way back at the bottom.
    var stacked = false
    let onFocus: (AnyHashable) -> Void
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        let sorted = ActionBarOrder.sorted(actions, role: \.role)
        Group {
            if stacked {
                VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                    ForEach(ActionBarOrder.stacked(actions, role: \.role)) { key($0, fills: true) }
                }
            } else {
                row(sorted)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func row(_ sorted: [Action]) -> some View {
        let apart = ActionBarOrder.separatesDestructive(sorted, role: \.role)
        let left = sorted.filter { apart ? $0.role == .destructive : $0.role == .back }
        let right = sorted.filter { apart ? $0.role != .destructive : $0.role != .back }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: canvas.u(apart ? SeleneTokens.Space.group : SeleneTokens.Space.medium)) {
                HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.medium)) {
                    ForEach(left) { key($0) }
                }
                if spread && !apart { Spacer(minLength: canvas.u(SeleneTokens.Space.group)) }
                HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.medium)) {
                    ForEach(right) { key($0) }
                }
            }
            // Keep reading and navigation order if two groups need their own lines.
            VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.medium)) {
                    ForEach(left) { key($0) }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.medium)) {
                    Spacer(minLength: 0)
                    ForEach(right) { key($0) }
                }
            }
        }
    }

    private func key(_ action: Action, fills: Bool = false) -> some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            OortButton(title: action.title, arguments: action.arguments, focused: focused == action.id,
                       state: action.enabled ? .ready : .blocked, preset: preset, fillsWidth: fills,
                       tone: action.role == .destructive ? .destructive : .normal,
                       action: action.perform)
                .disabled(!action.enabled)
                .accessibilityHint(action.detail ?? "")
                .seleneHover { if action.enabled { onFocus(action.id) } }
            if let detail = action.detail {
                Text(verbatim: detail).seleneFont(.text).foregroundStyle(SeleneTheme.ink60)
                    .multilineTextAlignment(.center)
                    .frame(idealWidth: canvas.u(SeleneTokens.Space.pillWidth), maxWidth: fills ? nil : canvas.u(SeleneTokens.Space.keyDetailMeasure))
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
            OortActionBar(actions: actions, focused: focused, stacked: ActionBarOrder.isStacked(count: actions.count), onFocus: onFocus)
                .padding(.top, canvas.u(SeleneTokens.Space.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SeleneDialogCard(width: SeleneTokens.Space.questionMeasure,
                                   cancelHint: HintItem(.b, "Cancel", action: onCancel),
                                   confirmHint: HintItem(.a, "Select", action: onConfirm)))
        .accessibilityElement(children: .contain)
    }
}
