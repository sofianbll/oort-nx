import SwiftUI
import NXLibraryCore

/// The question a screen asks before an intent that cannot be taken back, and its focused choice. The host owns it,
/// so the input it routes reaches the question as it reaches the screen.
@MainActor final class ScreenQuestion: ObservableObject {
    @Published private(set) var asking: Screen.Question?
    @Published var choice = 0
    private(set) var intent: Screen.Intent?

    func ask(_ question: Screen.Question, for intent: Screen.Intent) {
        (asking, self.intent, choice) = (question, intent, question.focus)
    }

    func close() { (asking, intent) = (nil, nil) }
}

/// The SwiftUI renderer of a core screen (OortCore `Screen`): each node drawn with the Selene piece of its kind, the
/// focus moved in the published order, each gesture's intent handed to the host's effects table. It decides no word,
/// no order and no focus: the screen does.
struct ScreenView: View {
    @Environment(\.nxAppLocale) private var locale
    @Environment(\.seleneCanvas) private var canvas
    @AccessibilityFocusState(for: .voiceOver) private var accessibilityFocus: String?
    let screen: Screen
    /// The stored focus; nil or a vanished identity is the screen's initial focus.
    @Binding var focus: String?
    @ObservedObject var question: ScreenQuestion
    var restoreScroll = false
    var showsHints = true
    /// The host's picture of a node's icon identity.
    var platform: (String) -> PlatformKind? = { _ in nil }
    /// The host's effect of each intent.
    let perform: (Screen.Intent) -> ScreenOutcome

    private var focused: String? { screen.focus(focus) }
    private func say(_ text: Screen.Text?) -> String { text.map { L10n.say($0, context: locale) } ?? "" }

    var body: some View {
        OortPage(title: say(screen.title), scrollFocus: focus, initialFocus: screen.initialFocus, restoreScroll: restoreScroll,
                 back: hint(.b), confirm: hint(.a), extra: hint(.x)) {
            if let lead = screen.lead { OortReadout(text: say(lead), preset: .lead) }
            ForEach(Array(screen.blocks.enumerated()), id: \.offset) { _, block in node(block) }
        }
        // A new screen starts with its own scroll, as each screen had its own page before.
        .id(screen.id)
        .overlay { if let asking = question.asking { dialog(asking) } }
        .onChange(of: screen.id, initial: true) { accessibilityFocus = focused }
        .onChange(of: focus) { accessibilityFocus = focused }
    }

    // MARK: Input: the real entry of the keyboard, the controller and the hints

    /// Up and Down move through the published order; A, X and B make the focused node's gestures. While a question is
    /// asked, Left and Right move between its choices, A answers and B cancels.
    func handle(_ action: GamepadAction) {
        if let asking = question.asking {
            switch action {
            case .navigateLeft, .navigateRight:
                question.choice = min(max(question.choice + (action == .navigateLeft ? -1 : 1), 0), asking.choices.count - 1)
            case .confirm: answer(question.choice)
            case .cancel: question.close()
            default: break
            }
            return
        }
        switch action {
        case .navigateUp, .navigateDown: focus = screen.moved(from: focus, by: action == .navigateUp ? -1 : 1)
        case .confirm: press(.a)
        case .secondaryAction: press(.x)
        case .cancel: press(.b)
        default: break
        }
    }

    /// A key's gesture on a node (the focused one, or the one clicked). Refused, with its sound, where the node has
    /// none; A on a node with a question asks it first. A switch turned sounds once, however it was asked: a click
    /// already sounded (the switch, or the flat row that holds one).
    private func press(_ key: Screen.Key, at id: String? = nil, clicked: Bool = false) {
        let at = id ?? focused
        guard let gesture = screen.gesture(key, at: at) else {
            SoundEffectService.shared.play(.error)
            return
        }
        if key == .x { focus = at }
        if key == .a, let ask = screen.node(at)?.question {
            question.ask(ask, for: gesture.intent)
            return
        }
        let turns = if case .toggle = gesture.intent { true } else { false }
        run(gesture.intent, sounds: turns && !clicked)
    }

    private func run(_ intent: Screen.Intent, sounds: Bool) {
        switch perform(intent) {
        case .done: if sounds { SoundEffectService.shared.play(.key) }
        case .refused: SoundEffectService.shared.play(.error)
        case .stale: break
        }
    }

    private func answer(_ index: Int) {
        guard let asking = question.asking, asking.choices.indices.contains(index) else { return }
        let intent = question.intent
        question.close()
        if asking.choices[index].role == .destructive, let intent { run(intent, sounds: false) }
    }

    static func keyAction(_ key: UInt16) -> GamepadAction? {
        switch key {
        case 126: .navigateUp
        case 125: .navigateDown
        case 123: .navigateLeft
        case 124: .navigateRight
        case 36, 49, 76: .confirm
        case 7: .secondaryAction
        case 53: .cancel
        default: nil
        }
    }

    // MARK: Drawing: one Selene piece per node

    /// A hint per gesture of the focused node: B on the left, X then A on the right (OortPage's bar). A click on it is
    /// its key.
    private func hint(_ key: Screen.Key) -> HintItem? {
        guard showsHints, let gesture = screen.gesture(key, at: focused) else { return nil }
        let action: GamepadAction = switch key {
        case .a: .confirm
        case .b: .cancel
        case .x: .secondaryAction
        }
        return HintItem(PromptButton(rawValue: key.rawValue), say(gesture.title)) { handle(action) }
    }

    private func node(_ node: Screen.Node) -> AnyView {
        switch node.kind {
        case .section:
            AnyView(OortSection(title: say(node.title)) {
                ForEach(Array((node.items ?? []).enumerated()), id: \.offset) { _, item in self.node(item) }
                if let note = node.note { OortReadout(text: say(note), preset: .quiet) }
            })
        case .box:
            AnyView(OortCard(say(node.title)) {
                ForEach(Array((node.items ?? []).enumerated()), id: \.offset) { _, item in self.node(item) }
            })
        case .row: row(node)
        case .toggle: toggle(node)
        case .button:
            AnyView(OortButton(title: say(node.title), focused: focused == node.id, preset: .compact,
                               tone: node.question == nil ? .normal : .destructive) { press(.a, at: node.id, clicked: true) }
                .accessibilityFocused($accessibilityFocus, equals: node.id)
                .id(node.id))
        case .text: AnyView(OortReadout(text: say(node.text)))
        case .quiet: AnyView(OortReadout(text: say(node.text), preset: .quiet))
        case .status: AnyView(OortStatus(text: say(node.status?.text), tone: Self.tone(node.status?.tone)))
        case .facts:
            // Reads, Writes and Sends stay together, set apart from the checks by a token gap, not a box.
            AnyView(VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
                ForEach(Array((node.texts ?? []).enumerated()), id: \.offset) { _, text in OortReadout(text: say(text)) }
            }
            .padding(.top, canvas.u(SeleneTokens.Space.small)))
        }
    }

    private func row(_ node: Screen.Node) -> AnyView {
        let id = node.id
        let isOn = node.x == nil ? nil : node.on.map { on in Binding(get: { on }, set: { _ in press(.x, at: id, clicked: true) }) }
        let preset: OortRow.Preset = node.a.map { a in .navigation(label: say(a.title)) { press(.a, at: id, clicked: true) } } ?? .info
        return AnyView(OortRow(title: say(node.title), platform: node.icon.flatMap(platform), about: node.about.map(say),
                               aboutIsBody: node.about.map { ScreenTree.aboutRole($0) == .body } ?? false, status: node.status.map { say($0.text) }, focused: focused == id, tone: Self.tone(node.status?.tone),
                               isOn: isOn, preset: preset)
            .id(id)
            .accessibilityFocused($accessibilityFocus, equals: id)
            .accessibilityActions {
                // A named action is no click: it sounds as X does.
                if let x = node.x { Button(say(x.title)) { press(.x, at: id) } }
            })
    }

    /// A switch inside a box: flat, without chevron; the row and its switch ask for the other state.
    private func toggle(_ node: Screen.Node) -> AnyView {
        let id = node.id
        let isOn = Binding(get: { node.on ?? false }, set: { _ in press(.a, at: id, clicked: true) })
        return AnyView(OortRow(title: say(node.title), platform: nil, about: node.about.map(say),
                               aboutIsBody: node.about.map { ScreenTree.aboutRole($0) == .body } ?? false, focused: focused == id,
                               isOn: isOn, preset: .toggle(label: say(node.a?.title)))
            .environment(\.oortGroupedRow, true)
            .id(id)
            .accessibilityFocused($accessibilityFocus, equals: id))
    }

    private func dialog(_ asking: Screen.Question) -> some View {
        SeleneOverlay(style: .dialog) {
            SeleneChoiceDialog(title: say(asking.title), message: say(asking.message), choices: asking.choices.map { say($0.title) },
                               focus: $question.choice, cancelIndex: asking.choices.firstIndex { $0.role == .cancel },
                               destructive: Set(asking.choices.indices.filter { asking.choices[$0].role == .destructive }),
                               onCancel: { question.close() }, onChoose: answer)
        }
    }

    static func tone(_ tone: Screen.Tone?) -> OortStatus.Tone {
        switch tone {
        case .attention?: .attention
        case .working?: .working
        case .neutral?, nil: .neutral
        }
    }
}

// MARK: Trace: what the Selene pieces draw, said by the pieces themselves

/// One piece as it was drawn, for the parity check against a reference tree (OortCore ScreenTree).
struct ScreenTracePiece: Equatable {
    enum Kind: String { case row, dot, `switch`, pill, hint, text, question }
    let kind: Kind
    var text: String? = nil
    var about: String? = nil
    var tone: Screen.Tone? = nil
    var on: Bool? = nil
    var focused: Bool? = nil
    var destructive: Bool? = nil
    /// A hint's key and side of the bar.
    var key: String? = nil
    var left: Bool? = nil
    /// A text's typographic role.
    var role: ScreenTree.Words.Role? = nil
}

struct ScreenTraceKey: PreferenceKey {
    static let defaultValue: [ScreenTracePiece] = []
    static func reduce(value: inout [ScreenTracePiece], nextValue: () -> [ScreenTracePiece]) { value += nextValue() }
}

extension EnvironmentValues {
    /// On while a probe reads what the pieces draw; off everywhere else.
    @Entry var screenTrace = false
}

extension View {
    /// The piece first, then what it holds.
    func screenTrace(_ on: Bool, _ pieces: @autoclosure () -> [ScreenTracePiece]) -> some View {
        let drawn = on ? pieces() : []
        return transformPreference(ScreenTraceKey.self) { $0.insert(contentsOf: drawn, at: 0) }
    }
}

extension OortStatus.Tone {
    /// The tone a status colour says, as a screen names it.
    static func screen(_ color: Color) -> Screen.Tone? {
        switch color {
        case Self.neutral.color: .neutral
        case Self.working.color: .working
        case Self.attention.color: .attention
        default: nil
        }
    }
}
