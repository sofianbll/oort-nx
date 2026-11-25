import SwiftUI
import NXLibraryCore

/// Which pill of a confirmation dialog has focus.
enum SeleneConfirmButton: Hashable {
    case cancel
    case confirm

    static let left = Self.cancel
    static let right = Self.confirm
    static let ordered = [left, right]
}

/// Selene's confirmation card (its dialogs: a 640u card, centred title and text,
/// the action bar: the way back on the left, the answer on the right). Cancel is the focused pill by default, so a stray A keeps the item.
/// The caller owns input: it moves `focus` with Left/Right or hover, and acts on
/// the two closures. Reused by Game options now and by later confirmations.
struct SeleneConfirmDialog<Detail: View>: View {
    @Environment(\.seleneCanvas) private var canvas

    let title: String
    let message: String
    let confirmTitle: String
    var cancelTitle: String? = "Cancel"
    var confirmEnabled = true
    var highlightsPills = true
    var warningIcon = false
    /// The answer deletes, replaces or ends something: it takes the danger colour.
    var destructive = false
    @Binding var focus: SeleneConfirmButton
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var detailContent: () -> Detail

    var body: some View {
        VStack(spacing: 0) {
            if warningIcon {
                Image(systemName: "exclamationmark.triangle")
                    .seleneFont(.heading)
                    .foregroundStyle(SeleneTheme.danger)
                    .frame(width: canvas.u(68), height: canvas.u(68))
                    .background(Circle().fill(SeleneTheme.danger.opacity(SeleneTokens.Alpha.soft)))
                    .padding(.bottom, canvas.u(SeleneTokens.Space.panel))
                    .accessibilityHidden(true)
            }
            Text(L10n.text(title))
                .seleneFont(.screen, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink75)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, canvas.u(SeleneTokens.Space.line))
            detailContent()
            OortActionBar(actions: keys, focused: highlightsPills ? AnyHashable(focus) : nil) { id in
                if let button = id.base as? SeleneConfirmButton { focus = button }
            }
            .padding(.top, canvas.u(SeleneTokens.Space.dialogActionGap))
        }
        .modifier(SeleneDialogCard(cancelHint: cancelTitle.map { HintItem(.b, $0, action: onCancel) },
                                   confirmHint: confirmEnabled || cancelTitle != nil ? HintItem(.a, "Select") : nil))
    }

    private var keys: [OortActionBar.Action] {
        SeleneConfirmButton.ordered.compactMap { button in
            button == .cancel
                ? cancelTitle.map { .init(id: button, title: $0, role: .back, perform: onCancel) }
                : .init(id: button, title: confirmTitle, role: .primary, enabled: confirmEnabled, danger: destructive, perform: onConfirm)
        }
    }
}

extension SeleneConfirmDialog where Detail == SeleneDialogNotes {
    init(title: String, message: String, confirmTitle: String, cancelTitle: String? = "Cancel",
         detail: String? = nil, warningIcon: Bool = false, destructive: Bool = false, focus: Binding<SeleneConfirmButton>,
         onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.init(title: title, message: message, confirmTitle: confirmTitle, cancelTitle: cancelTitle,
                  warningIcon: warningIcon, destructive: destructive, focus: focus, onCancel: onCancel, onConfirm: onConfirm) {
            SeleneDialogNotes(detail: detail)
        }
    }
}

/// Plain release notes keep their own scrolling text layout.
struct SeleneDialogNotes: View {
    @Environment(\.seleneCanvas) private var canvas
    let detail: String?
    var scrollRequest = 0
    var plainText = false
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        if let detail, !detail.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.badge)) {
                        ForEach(Array(ReleaseNotesLayout.lines(detail).enumerated()), id: \.offset) { index, line in
                            noteLine(line, first: index == 0).id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(canvas.u(SeleneTokens.Space.medium))
                }
                .onChange(of: scrollRequest) { _, index in
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(index, anchor: .top) }
                }
            }
            .frame(maxHeight: canvas.u(260))
            .background(
                RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge), style: .continuous)
                    .fill(SeleneTheme.glassLight)
            )
            .padding(.top, canvas.u(SeleneTokens.Space.panel))
        }
    }

    /// Headings as the app's section labels, items with a dot and a hanging indent, blank lines as spacing only.
    @ViewBuilder
    private func noteLine(_ line: ReleaseNotesLayout.Line, first: Bool) -> some View {
        switch line.kind {
        case .heading:
            Text(line.text)
                .seleneFont(.badge, .semibold)
                .foregroundColor(SeleneTheme.ink60)
                .padding(.top, first ? 0 : canvas.u(10))
                .accessibilityAddTraits(.isHeader)
        case .item:
            HStack(alignment: .firstTextBaseline, spacing: canvas.u(SeleneTokens.Space.gap)) {
                Circle()
                    .fill(SeleneTheme.glyph)
                    .frame(width: canvas.u(5), height: canvas.u(5))
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + canvas.u(1) }
                    .accessibilityHidden(true)
                inline(line.text)
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink82)
                    .multilineTextAlignment(plainText ? .leading : .center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, canvas.u(SeleneTokens.Space.seam))
        case .text:
            inline(line.text)
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink75)
                .fixedSize(horizontal: false, vertical: true)
        case .blank:
            Color.clear.frame(height: canvas.u(2))
        }
    }

    /// Bold and code inside a line, as GitHub shows them.
    private func inline(_ text: String) -> Text {
        if plainText { return Text(verbatim: text) }
        return Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
             ?? AttributedString(text))
    }
}

/// A brief completion message in the same glass card as Selene's dialogs.
struct SeleneSuccessNotice: View {
    @Environment(\.seleneCanvas) private var canvas
    let title: String
    var message: String? = nil

    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: canvas.u(SeleneTokens.Text.heading.rawValue), weight: .light))
                .foregroundColor(SeleneTheme.ink75)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.tight)) {
                Text(L10n.text(title))
                    .seleneFont(.heading, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                if let message {
                    Text(message)
                        .seleneFont(.text)
                        .foregroundColor(SeleneTheme.ink75)
                }
            }
        }
        .modifier(SeleneDialogCard())
        .accessibilityElement(children: .combine)
    }
}

/// Selene's dialog card: glass, a hairline and a deep shadow; nil lets a wide choice row size the card.
struct SeleneDialogCard: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneShowButtonHints) private var showHints
    var width: CGFloat? = 640
    var cancelHint: HintItem? = nil
    var confirmHint: HintItem? = nil

    func body(content: Content) -> some View {
        let hasHints = showHints && (cancelHint != nil || confirmHint != nil)
        content
            .multilineTextAlignment(.center)
            .padding(.leading, canvas.u(SeleneTokens.Space.dialogInset))
            .padding(.top, canvas.u(SeleneTokens.Space.dialogInset))
            .padding(.trailing, canvas.u(SeleneTokens.Space.dialogInset))
            .padding(.bottom, canvas.u(hasHints ? 72 : 36))
            .frame(width: width.map(canvas.u))
            .oortPanel(radius: canvas.u(SeleneTokens.Radius.dialog), floats: true)
            .overlay(alignment: .bottom) {
                if hasHints {
                    SeleneHintsBar(left: [cancelHint].compactMap { $0 },
                                   right: [confirmHint].compactMap { $0 },
                                   bottom: SeleneTokens.Space.control, leftInset: 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.dialog), style: .continuous))
            .shadow(color: SeleneTheme.artShade.opacity(SeleneTokens.Effect.dialogShadowOpacity),
                    radius: canvas.u(SeleneTokens.Effect.dialogShadowRadius))
            .environment(\.seleneMinimumFont, 12)
    }
}

/// The same card with one key per choice, in the order they are drawn: what erases apart on the far left, the way
/// back, then the main answer last on the right. The caller owns input: it moves `focus` with arrows or hover and
/// acts on `onChoose` (the choice's index); B and a click outside are the caller's cancel.
struct SeleneChoiceDialog: View {
    @Environment(\.seleneCanvas) private var canvas

    let title: String
    let message: String
    let choices: [String]
    @Binding var focus: Int
    var cancelIndex: Int? = nil
    /// The choices that delete, replace or end something.
    var destructive: Set<Int> = []
    /// What B says when no choice is the way back.
    var backTitle = "Cancel"
    /// A list of things to pick, one a line, the way back at the bottom.
    var list = false
    var details: [String: String] = [:]
    var notes: String? = nil
    var notesScrollRequest = 0
    var onCancel: (() -> Void)? = nil
    let onChoose: (Int) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            card.fixedSize(horizontal: true, vertical: false).modifier(dialogCard(width: nil))
            card.modifier(dialogCard(width: SeleneTokens.Space.questionMeasure))
        }
    }

    private func dialogCard(width: CGFloat?) -> SeleneDialogCard {
        SeleneDialogCard(width: width,
            cancelHint: onCancel.map { HintItem(.b, backWords, action: $0) },
            confirmHint: choices.indices.contains { $0 != cancelIndex }
                ? HintItem(.a, "Select", action: { onChoose(focus) }) : nil)
    }

    /// The hint says the key's own words.
    private var backWords: String { choices.count == 1 ? choices[0] : cancelIndex.map { choices[$0] } ?? backTitle }

    private var card: some View {
        let textWidth = canvas.u(560)
        return VStack(spacing: 0) {
            Text(L10n.text(title))
                .seleneFont(.screen, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .frame(width: textWidth)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink75)
                .frame(width: textWidth)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, canvas.u(SeleneTokens.Space.line))
            SeleneDialogNotes(detail: notes, scrollRequest: notesScrollRequest, plainText: true)
                .frame(width: textWidth)
            OortActionBar(actions: keys, focused: focus, stacked: list) { id in
                if let index = id.base as? Int { focus = index }
            }
            .padding(.top, canvas.u(SeleneTokens.Space.dialogActionGap))
        }
    }

    private var keys: [OortActionBar.Action] {
        choices.enumerated().map { index, choice in
            let last = index == choices.count - 1
            let role: ActionBarRole = choices.count == 1 ? .primary : index == cancelIndex ? .back
                : list ? .secondary : last ? .primary : destructive.contains(index) ? .destructive : .secondary
            return .init(id: index, title: choice, role: role, danger: destructive.contains(index), detail: details[choice]) { onChoose(index) }
        }
    }
}
