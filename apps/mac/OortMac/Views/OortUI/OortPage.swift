import SwiftUI
import OortLibrary

extension EnvironmentValues {
    /// A probe draws the screen into an image (ImageRenderer, whose PDF and pixels assertVisible reads). ImageRenderer
    /// paints no scroll view's content, and on macOS 27.0.1 nothing of a view bound to an accessibility focus: the page
    /// is drawn whole without its scroll view, and nodes without their VoiceOver focus, which has no pixels. Off in the app.
    @Entry var oortRenderedAsImage = false
}

struct OortPage<ID: Hashable, Content: View>: View {
    enum Preset { case standard, legacyBackdrop }
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.oortRenderedAsImage) private var unscrolled
    @Environment(\.screenTrace) private var trace
    let title: String
    var preset: Preset = .standard
    var scrollFocus: ID?
    var initialFocus: ID?
    var restoreScroll = false
    var back: HintItem?
    var confirm: HintItem?
    /// A second gesture of the focused row, before A.
    var extra: HintItem? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.panel)) {
            Text(title).seleneFont(.screen, .semibold)
                .accessibilityAddTraits(.isHeader)
                .screenTrace(trace, [.init(kind: .text, text: title, role: .screen)])
            if unscrolled {
                column.frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollViewReader { proxy in
                    ScrollView { column }
                    .onChange(of: scrollFocus, initial: true) { old, id in
                        guard let id, old != id || id != initialFocus || restoreScroll else { return }
                        withAnimation(Motion.focus(reduceMotion)) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
        }
        .frame(maxWidth: canvas.u(SeleneTokens.Space.pageMeasure))
        .padding(.horizontal, canvas.u(SeleneTokens.Space.stageGutter))
        .padding(.top, canvas.u(SeleneTokens.Space.stageHeader))
        .padding(.bottom, canvas.u(SeleneBottomScrim.contentClearance))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.seleneMinimumFont, SeleneTokens.Space.pageMinimumFont)
        .foregroundStyle(SeleneTheme.ink)
        .background {
            if preset == .legacyBackdrop {
                SeleneBackdrop(still: reduceMotion)
            } else {
                SeleneTheme.pageSurface.ignoresSafeArea()
            }
        }
        .overlay(alignment: .bottom) {
            if back != nil || confirm != nil || extra != nil {
                SeleneHintsBar(left: back.map { [$0] } ?? [], right: [extra, confirm].compactMap { $0 })
            }
        }
    }
}

private extension OortPage {
    var column: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small), content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, canvas.u(SeleneTokens.Space.control))
    }
}

struct OortSection<Content: View>: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.screenTrace) private var trace
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            Text(title).seleneFont(.heading, .semibold)
                .accessibilityAddTraits(.isHeader)
                .screenTrace(trace, [.init(kind: .text, text: title, role: .heading)])
            content()
        }
        .foregroundStyle(SeleneTheme.ink)
    }
}

struct OortEmptyState: View {
    @Environment(\.seleneCanvas) private var canvas
    let title: String
    /// What fills it.
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            Text(title)
                .seleneFont(.heading, .semibold)
                .foregroundStyle(SeleneTheme.ink82)
            if let hint {
                Text(hint).seleneFont(.text).foregroundStyle(SeleneTheme.ink75)
            }
        }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, canvas.u(SeleneTokens.Space.emptyStateInset))
            .accessibilityElement(children: .combine)
    }
}
