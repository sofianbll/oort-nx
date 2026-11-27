import SwiftUI
import NXLibraryCore

extension ContainerValues {
    /// A settings row: neighbours share one card. Anything else (a heading, a note, a panel) stands on its own.
    @Entry var oortSettingsRow = false
}

extension EnvironmentValues {
    /// A row inside an `OortSettingsGroup` draws no card and leaves its explanation to the page's help line.
    @Entry var oortGroupedRow = false
    /// A row drawn flat inside a box: its text lines up with the box's sentences and buttons; its focus ring and dots
    /// reach into the box's margin by a compact step.
    @Entry var oortFlushRow = false
}

/// A settings heading; on light backdrops, use Selene's reading shade under the ink.
struct SettingsSubheading: View {
    @Environment(\.seleneCanvas) private var canvas
    let title: String
    let overBackdrop: Bool

    init(_ title: String, overBackdrop: Bool = false) {
        self.title = title
        self.overBackdrop = overBackdrop
    }

    var body: some View {
        Text(L10n.text(title))
            .seleneFont(.text, .semibold)
            .foregroundColor(SeleneTheme.ink)
            .background {
                if overBackdrop && ThemeStore.shared.palette.mode == .light {
                    RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.row))
                        .fill(SeleneTheme.scrim)
                        .padding(.horizontal, -canvas.u(SeleneTokens.Space.small))
                        .padding(.vertical, -canvas.u(SeleneTokens.Space.hairline))
                }
            }
            .padding(.top, canvas.u(SeleneTokens.Space.tight))
            .padding(.bottom, canvas.u(SeleneTokens.Space.hairline))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The explanation of the row under the pointer or in focus, shown once for the whole page.
struct OortRowHelpKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) { value = value ?? nextValue() }
}

/// Settings rows as System Settings groups them: one card per run of rows, separators inside, air between cards.
struct OortSettingsGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        // Set on the content: a subview keeps the environment it was declared in.
        Group(subviews: content().environment(\.oortGroupedRow, true)) { subviews in
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.large)) {
                ForEach(runs(subviews)) { run in
                    if run.isRows { card(run.views) } else { ForEach(run.views) { $0 } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct Run: Identifiable {
        let id: AnyHashable
        let isRows: Bool
        var views: [Subview]
    }

    private func runs(_ subviews: SubviewsCollection) -> [Run] {
        subviews.reduce(into: []) { runs, view in
            let isRow = view.containerValues.oortSettingsRow
            if isRow, runs.last?.isRows == true {
                runs[runs.count - 1].views.append(view)
            } else {
                runs.append(Run(id: AnyHashable(view.id), isRows: isRow, views: [view]))
            }
        }
    }

    private func card(_ rows: [Subview]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle().fill(SeleneTheme.line)
                        .frame(height: max(SeleneTokens.Space.thinStroke, canvas.u(SeleneTokens.Space.thinStroke)))
                        .padding(.leading, canvas.u(SeleneTokens.Space.rowLeading))
                        .accessibilityHidden(true)
                }
                row
            }
        }
        .oortPanel(radius: canvas.u(SeleneTokens.Radius.card))
    }
}

/// One steady line under the rows: what the current row does. Its height never changes, so nothing jumps.
struct OortSettingsHelp: View {
    let text: String?
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: text ?? " ")
            .seleneFont(.text)
            .foregroundStyle(SeleneTheme.ink)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: canvas.u(SeleneTokens.Space.actionPillHeight), alignment: .leading)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.rowLeading))
            .oortPanel(radius: canvas.u(SeleneTokens.Radius.card))
            .opacity(text == nil ? 0 : 1)
            .animation(Motion.focus(reduceMotion), value: text)
            .accessibilityHidden(true)
    }
}

/// A short panel at the screen's right edge, over what it belongs to: a title, grouped rows, one help line.
struct OortSidePanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @State private var help: String?
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.large)) {
            Text(verbatim: title)
                .seleneFont(.heading, .semibold)
                .foregroundStyle(SeleneTheme.ink)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            ScrollView { OortSettingsGroup(content: content) }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            OortSettingsHelp(text: help)
        }
        .onPreferenceChange(OortRowHelpKey.self) { help = $0 }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.section))
        .padding(.top, canvas.u(SeleneTokens.Space.stageHeader))
        .padding(.bottom, canvas.u(SeleneTokens.Space.settingsHintsClearance))
        .frame(width: canvas.u(SeleneTokens.Space.sidePanel))
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            LinearGradient(colors: [SeleneTheme.panelHigh, SeleneTheme.panelLow], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .leading) { Rectangle().fill(SeleneTheme.lineStrong).frame(width: SeleneTokens.Space.thinStroke) }
        }
        .contentShape(Rectangle())
    }
}
