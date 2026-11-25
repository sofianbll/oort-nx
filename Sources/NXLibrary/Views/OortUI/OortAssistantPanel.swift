import SwiftUI
import NXLibraryCore

/// A task in a few steps over the stage: the steps on the left, the current one beside them, its actions and the hints below.
struct OortAssistantPanel<Content: View, Actions: View>: View {
    struct Step: Identifiable {
        enum State { case done, current, ahead }
        let id: Int
        let title: String
        let state: State
    }

    let title: String
    let heading: String
    let message: String?
    let steps: [Step]
    let focusedStep: Int?
    let back: HintItem?
    let confirm: HintItem?
    /// A step that can be reopened.
    let canOpen: (Int) -> Bool
    let onStep: (Int) -> Void
    let press: (GamepadAction) -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            rail
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.large)) {
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.tight)) {
                    Text(heading).seleneFont(.screen, .semibold).foregroundStyle(SeleneTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let message { OortReadout(text: message) }
                }
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: canvas.u(SeleneTokens.Space.medium), content: actions)
            }
            .padding(.horizontal, canvas.u(SeleneTokens.Space.dialogInset))
            .padding(.top, canvas.u(SeleneTokens.Space.dialogInset))
            .padding(.bottom, canvas.u(SeleneTokens.Space.pageTopCompact))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .oortPanel(radius: canvas.u(SeleneTokens.Radius.dialog), floats: true)
        .overlay(alignment: .bottom) {
            SeleneHintsBar(left: [back].compactMap { $0 }, right: [confirm].compactMap { $0 },
                           bottom: SeleneTokens.Space.control, leftInset: 0, press: press)
        }
        .clipShape(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.dialog), style: .continuous))
        .frame(maxWidth: canvas.u(SeleneTokens.Space.pageMeasure))
        .padding(canvas.u(SeleneTokens.Space.chromeGutter))
        .environment(\.seleneMinimumFont, SeleneTokens.Space.pageMinimumFont)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.tight)) {
            Text(title).seleneFont(.text, .semibold).foregroundStyle(SeleneTheme.ink75)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, canvas.u(SeleneTokens.Space.medium))
                .padding(.bottom, canvas.u(SeleneTokens.Space.small))
            ForEach(steps) { step in row(step) }
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.panel))
        .padding(.vertical, canvas.u(SeleneTokens.Space.dialogInset))
        .frame(width: canvas.u(SeleneTokens.Space.assistantRail), alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) {
            OortSeparator().padding(.vertical, canvas.u(SeleneTokens.Space.dialogInset))
        }
    }

    private func row(_ step: Step) -> some View {
        let lit = focusedStep == step.id
        return Button { onStep(step.id) } label: {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                Group {
                    if step.state == .done { MaterialIconView(.check, size: SeleneTokens.Space.large) }
                    else { Text(verbatim: "\(step.id + 1)").seleneFont(.row, .semibold) }
                }
                .frame(width: canvas.u(SeleneTokens.Space.section))
                Text(step.title).seleneFont(.row, .medium).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(lit ? SeleneTheme.onFocus : step.state == .ahead ? SeleneTheme.ink60 : SeleneTheme.ink)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
            .padding(.vertical, canvas.u(SeleneTokens.Space.line))
            .background {
                if step.state == .current || lit {
                    OortKeyFace(kind: lit ? .solid : .quiet, radius: canvas.u(SeleneTokens.Radius.card), lit: lit, outlined: false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(OortPressStyle())
        .disabled(!canOpen(step.id))
        .accessibilityLabel(L10n.format("Step %d of %d: %@", [step.id + 1, steps.count, step.title], context: localization))
        .accessibilityValue(step.state == .done ? L10n.text("Done", context: localization) : "")
        .accessibilityAddTraits(step.state == .current ? .isSelected : [])
    }
}

/// A hairline between two columns.
struct OortSeparator: View {
    var body: some View {
        Rectangle().fill(SeleneTheme.line).frame(width: SeleneTokens.Space.thinStroke).accessibilityHidden(true)
    }
}

/// One folder a player gives to Oort: its name in words, what it is for, where it is, and what is in it.
struct OortFolderCard<Status: View, Actions: View>: View {
    let icon: MaterialIcon
    let title: String
    let about: String
    let account: String
    let path: String?
    let placeholder: String
    @ViewBuilder var status: () -> Status
    @ViewBuilder var actions: () -> Actions
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        OortCard {
            HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.control)) {
                MaterialIconView(icon, size: SeleneTokens.Space.section).foregroundStyle(SeleneTheme.rowIcon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                    Text(title).seleneFont(.heading, .semibold).foregroundStyle(SeleneTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    OortReadout(text: about)
                }
                Spacer(minLength: canvas.u(SeleneTokens.Space.medium))
                HStack(spacing: canvas.u(SeleneTokens.Space.small), content: actions)
            }
            HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                Text(verbatim: path ?? placeholder).seleneFont(.row, .medium)
                    .foregroundStyle(path == nil ? SeleneTheme.ink60 : SeleneTheme.ink)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Text(verbatim: account).seleneFont(.text).foregroundStyle(SeleneTheme.ink75).lineLimit(1)
            }
            .padding(canvas.u(SeleneTokens.Space.line))
            .frame(maxWidth: .infinity, alignment: .leading)
            .oortWell(radius: canvas.u(SeleneTokens.Radius.content))
            status()
        }
        .accessibilityElement(children: .contain)
    }
}
