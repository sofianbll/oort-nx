import ShellHost
import ShellModel
import SwiftUI

/// A question over the app: what it asks, what can be done, and the way out, which is chosen first.
struct OortQuestion {
    struct Choice {
        var label: String
        var destructive = false
        var run: @MainActor () -> Void
    }
    var title: String
    var message = ""
    var choices: [Choice] = []
    var cancelLabel = Oort.text("Cancel")
    var cancel: @MainActor () -> Void = {}

    /// A change that loses a choice: asked first.
    static func confirm(_ title: String, _ message: String, _ label: String, run: @escaping @MainActor () -> Void) -> OortQuestion {
        OortQuestion(title: title, message: message, choices: [Choice(label: label, destructive: true, run: run)])
    }
}

/// The question's panel. It alone reads the controller while it is shown: nothing behind it moves.
struct OortDialog: View {
    let question: OortQuestion
    let model: ShellHostModel
    let nav: OortNav
    @State private var focus = FocusGrid<Int>()

    /// The way out is the last key, and the first chosen.
    private var out: Int { question.choices.count }
    private var chosen: Int { focus.current ?? out }

    var body: some View {
        ZStack {
            Oort.night.opacity(0.78).ignoresSafeArea()
                .onTapGesture { question.cancel() }
                .accessibilityHidden(true)
            GeometryReader { geometry in
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: SeleneTokens.Space.medium) {
                            Text(question.title).font(.title3.bold()).foregroundStyle(Oort.ink).accessibilityAddTraits(.isHeader)
                            if !question.message.isEmpty { Text(question.message).font(.subheadline).foregroundStyle(Oort.ink2) }
                            VStack(spacing: SeleneTokens.Space.small) {
                                ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                                    key(index, choice.label, tint: choice.destructive ? Oort.danger : nil) { answer(choice.run) }
                                }
                                key(out, question.cancelLabel, tint: nil) { answer(question.cancel) }
                            }
                            OortHints(nav: nav, hints: [(.activate, Oort.text("Select")), (.back, question.cancelLabel)])
                        }
                        .padding(SeleneTokens.Space.panel)
                        .frame(maxWidth: 460)
                        .oortPanel(radius: SeleneTokens.Radius.dialog)
                        .padding(SeleneTokens.Space.panel)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: focus.current) { _, id in scroll.scrollTo(id) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("oort.question")
        .accessibilityAction(.escape) { answer(question.cancel) }
        .oortModalInput(model, nav) { action in
            if focus.current == nil {
                focus.set(out)
                if nav.revealing && action != .back { return true }
            }
            switch action {
            case .up, .down: nav.sounds.play(focus.move(direction(action), in: (0...out).map { [$0] }) ? .move : .deny)
            case .activate:
                nav.sounds.play(.select)
                answer(chosen < out ? question.choices[chosen].run : question.cancel)
            case .back:
                nav.sounds.play(.back)
                answer(question.cancel)
            default: break
            }
            return true
        }
    }

    /// The question goes first: what it runs may ask another.
    private func answer(_ run: @MainActor () -> Void) {
        nav.question = nil
        run()
    }

    private func key(_ index: Int, _ label: String, tint: Color?, run: @escaping () -> Void) -> some View {
        let focused = nav.device != nil && chosen == index
        return Button(action: run) { Text(label).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
            .buttonStyle(OortKeyStyle(focused: focused, tint: tint))
            .accessibilityAddTraits(focused ? .isSelected : [])
            .id(index)
    }
}

/// A text longer than the screen: up and down move through it, B closes it.
struct OortReading: ViewModifier {
    let model: ShellHostModel
    let nav: OortNav
    /// nil: B goes back as on any screen.
    var close: (() -> Void)?
    @State private var position = ScrollPosition()
    @State private var offset: CGFloat = 0
    @State private var most: CGFloat = 0
    @State private var page: CGFloat = 0

    private struct Place: Equatable { var offset, most, page: CGFloat }

    func body(content: Content) -> some View {
        let read = content
            .scrollPosition($position)
            .onScrollGeometryChange(for: Place.self) { g in
                Place(offset: g.contentOffset.y, most: max(g.contentSize.height + g.contentInsets.bottom - g.containerSize.height, -g.contentInsets.top),
                      page: g.containerSize.height)
            } action: { _, place in (offset, most, page) = (place.offset, place.most, place.page) }
        if close != nil { read.oortModalInput(model, nav, handle) } else { read.oortInput(model, nav, handle) }
    }

    private func handle(_ action: ShellInput.Action) -> Bool {
        switch action {
        case .up, .down:
            let next = min(max(offset + (action == .down ? 1 : -1) * page * 0.6, 0), most)
            guard abs(next - offset) > 1 else { nav.sounds.play(.deny); return true }
            offset = next
            nav.sounds.play(.move)
            withAnimation(.snappy) { position.scrollTo(y: next) }
        case .back:
            guard let close else { return false }
            nav.sounds.play(.back)
            close()
        default: return close != nil
        }
        return true
    }
}
