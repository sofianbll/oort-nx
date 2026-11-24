import SwiftUI
import NXLibraryCore

struct OortPage<ID: Hashable, Content: View>: View {
    enum Preset { case standard, legacyBackdrop }
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let title: String
    var preset: Preset = .standard
    var scrollFocus: ID?
    var initialFocus: ID?
    var restoreScroll = false
    var back: HintItem?
    var confirm: HintItem?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.panel)) {
            Text(title).seleneFont(.screen, .semibold)
                .accessibilityAddTraits(.isHeader)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small), content: content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, canvas.u(SeleneTokens.Space.control))
                }
                .onChange(of: scrollFocus, initial: true) { old, id in
                    guard let id, old != id || id != initialFocus || restoreScroll else { return }
                    withAnimation(Motion.focus(reduceMotion)) { proxy.scrollTo(id, anchor: .top) }
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
            if back != nil || confirm != nil {
                SeleneHintsBar(left: back.map { [$0] } ?? [], right: confirm.map { [$0] } ?? [])
            }
        }
    }
}

struct OortSection<Content: View>: View {
    @Environment(\.seleneCanvas) private var canvas
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            Text(title).seleneFont(.heading, .semibold)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .foregroundStyle(SeleneTheme.ink)
    }
}

struct OortEmptyState: View {
    @Environment(\.seleneCanvas) private var canvas
    let title: String

    var body: some View {
        Text(title)
            .seleneFont(.heading, .semibold)
            .foregroundStyle(SeleneTheme.ink82)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, canvas.u(SeleneTokens.Space.emptyStateInset))
    }
}
