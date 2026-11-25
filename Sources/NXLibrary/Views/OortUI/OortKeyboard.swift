import AppKit
import SwiftUI
import NXLibraryCore

/// The keys themselves: drawn here, typed by whoever shows them.
struct OortKeyboard: View {
    @Environment(\.seleneCanvas) private var canvas
    @Binding var keyboard: OnScreenKeyboard
    /// False while a real text field has the focus: no key is lit.
    var lit = true
    let press: (OnScreenKeyboard.Key) -> Void

    var body: some View {
        VStack(spacing: canvas.u(OnScreenKeyboard.gap)) {
            ForEach(Array(keyboard.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: canvas.u(OnScreenKeyboard.gap)) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            keyboard.focus(key)
                            press(key)
                        } label: { face(key) }
                        .buttonStyle(OortPressStyle())
                        .accessibilityLabel(name(key))
                        .accessibilityAddTraits(key == .shift && keyboard.shift ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func face(_ key: OnScreenKeyboard.Key) -> some View {
        Group {
            switch key {
            case .text: Text(verbatim: keyboard.text(key) ?? "")
            case .shift: Image(systemName: keyboard.shift ? "shift.fill" : "shift")
            case .page: Text(verbatim: pageMark)
            case .space: Text(L10n.text("Space"))
            case .erase: Image(systemName: "delete.left")
            case .done: Text(L10n.text("Done"))
            }
        }
        .seleneFont(isLetter(key) ? .heading : .text)
        .foregroundStyle(SeleneTheme.ink)
        .frame(width: canvas.u(OnScreenKeyboard.width(key)), height: canvas.u(64))
        .oortPanel(radius: canvas.u(SeleneTokens.Radius.card))
        .overlay(alignment: .topTrailing) {
            if let button = shortcut(key) {
                SelenePromptBadge(button: button, height: 22, keyboardOverride: key == .done ? .symbol("return") : nil)
                    .padding(canvas.u(SeleneTokens.Space.hairline)).accessibilityHidden(true)
            }
        }
        .modifier(TileFocus(focused: lit && keyboard.focused == key, radius: SeleneTokens.Radius.card, scale: 1.1))
        .oortPadPress(lit && keyboard.focused == key)
    }

    private func isLetter(_ key: OnScreenKeyboard.Key) -> Bool {
        if case .text = key { return true }
        return false
    }

    private var pageMark: String {
        switch keyboard.nextPage {
        case .letters: "abc"
        case .symbols: "#+="
        case .accents: "éàü"
        }
    }

    private func shortcut(_ key: OnScreenKeyboard.Key) -> PromptButton? {
        switch key {
        case .space: .y
        case .erase: .x
        case .done: .menu
        case .text, .shift, .page: nil
        }
    }

    private func name(_ key: OnScreenKeyboard.Key) -> String {
        switch key {
        case .text: keyboard.text(key) ?? ""
        case .shift: L10n.text("Shift")
        case .page: L10n.text(keyboard.nextPage == .letters ? "Letters" : keyboard.nextPage == .symbols ? "Symbols" : "Accents")
        case .space: L10n.text("Space")
        case .erase: L10n.text("Erase")
        case .done: L10n.text("Done")
        }
    }
}

/// The one on-screen keyboard: it opens under any text field a controller reaches, and types into that field.
/// A field needs nothing of its own; Done does what Return does there.
@MainActor final class OortKeyboardPresentation: ObservableObject {
    static let shared = OortKeyboardPresentation()
    @Published private(set) var isOpen = false
    @Published private(set) var text = ""
    @Published private(set) var isSecret = false
    /// The field is in the file picker's sheet, which draws the keyboard itself.
    @Published private(set) var inSheet = false
    @Published var keyboard = OnScreenKeyboard()
    /// Screens that draw their own keys (the profile's name).
    var ownKeys = 0
    var controllerInHand: () -> Bool = { GameControllerService.shared.controllerInHand }
    private weak var field: NSTextView?
    /// The field Done was pressed in: macOS selects it again at once, which is not the player coming back.
    private weak var finished: AnyObject?
    private var watch: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        observers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated { self?.follow(window) }
            },
            NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.read() }
            },
        ]
        follow(NSApp.keyWindow)
    }

    func follow(_ window: NSWindow?) {
        watch = window?.observe(\.firstResponder, options: [.initial]) { [weak self] window, _ in
            // Focus settles after the responder changes hands: look once it has.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.responderChanged(in: window) } }
        }
    }

    private func responderChanged(in window: NSWindow) {
        guard let next = window.firstResponder as? NSTextView, next.isEditable else { return close() }
        guard ownKeys == 0, controllerInHand() else { return }
        if let finished, owner(next) === finished { return }
        if !isOpen || field !== next { keyboard = OnScreenKeyboard() }
        field = next
        inSheet = window.isSheet
        isSecret = Self.isSecret(owner(next))
        isOpen = true
        read()
    }

    static func isSecret(_ owner: AnyObject) -> Bool { owner is NSSecureTextField }

    private func owner(_ editor: NSTextView) -> AnyObject { (editor.delegate as? NSTextField) ?? editor }

    private func read() {
        guard isOpen, let field else { return }
        let value = field.string
        if text != value { text = value }
    }

    /// True when the keyboard took the action.
    func handle(_ action: GamepadAction) -> Bool {
        guard isOpen, let field, field.window?.firstResponder === field else {
            finished = nil
            if isOpen { close() }
            return false
        }
        switch action {
        case .navigateUp: move(.up)
        case .navigateDown: move(.down)
        case .navigateLeft: move(.left)
        case .navigateRight: move(.right)
        case .confirm: press(keyboard.focused)
        case .secondaryAction: press(.erase)
        case .contextAction, .browseSearch: press(.space)
        case .menu, .menuHold: press(.done)
        case .tabPrevious, .jumpToStart: keyboard.turnPage(-1)
        case .tabNext, .jumpToEnd: keyboard.turnPage()
        case .search, .rightStickPress: press(.shift)
        case .cancel: leave()
        case .view, .profiles, .controlCenter, .fullMenu: break
        }
        return true
    }

    func press(_ key: OnScreenKeyboard.Key) {
        guard let field else { return close() }
        SoundEffectService.shared.play(.click)
        switch key {
        case .shift: keyboard.toggleShift()
        case .page: keyboard.turnPage()
        case .erase: field.deleteBackward(nil)
        case .done: finish(field)
        case .text, .space:
            if let text = keyboard.text(key) { field.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        read()
    }

    /// B keeps what is typed and gives the screen its buttons back.
    func leave() {
        SoundEffectService.shared.play(.back)
        let window = field?.window
        close()
        window?.makeFirstResponder(nil)
    }

    private func finish(_ field: NSTextView) {
        let owner = owner(field)
        close()
        if field.isFieldEditor {
            finished = owner
            field.insertNewline(nil)
        } else {
            // A longer text keeps its lines: its own buttons save it.
            field.window?.makeFirstResponder(nil)
        }
    }

    private func move(_ direction: OnScreenKeyboard.Move) {
        if keyboard.move(direction) { SoundEffectService.shared.play(.focus) }
    }

    private func close() {
        field = nil
        guard isOpen else { return }
        isOpen = false
        text = ""
    }
}

/// The keyboard over a window, with what is typed above the keys: the field itself may be under it.
struct OortKeyboardLayer: View {
    var inSheet = false
    @ObservedObject private var presentation = OortKeyboardPresentation.shared
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if presentation.isOpen, presentation.inSheet == inSheet {
                OortKeyboardPanel(presentation: presentation)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.overlay(reduceMotion), value: presentation.isOpen)
        .environment(\.seleneHintsCovered, false)
    }
}

struct OortKeyboardPanel: View {
    @ObservedObject var presentation: OortKeyboardPresentation
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                readout
                OortKeyboard(keyboard: $presentation.keyboard, press: presentation.press)
            }
            .padding(canvas.u(SeleneTokens.Space.large))
            .oortPanel(radius: canvas.u(SeleneTokens.Radius.modal), floats: true)
            .padding(.bottom, canvas.u(SeleneTokens.Space.settingsHintsClearance))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            SeleneHintsBar(left: [HintItem(.b, "Back"), HintItem(.lb, "Previous"), HintItem(.rb, "Next")],
                           right: [HintItem(.x, "Erase"), HintItem(.y, "Space"), HintItem(.a, "Select")],
                           press: { _ = presentation.handle($0) })
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Keyboard"))
    }

    private var readout: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.hairline)) {
            Text(verbatim: presentation.isSecret ? String(repeating: "•", count: presentation.text.count) : presentation.text)
                .seleneFont(.heading)
                .foregroundStyle(SeleneTheme.ink)
                .lineLimit(1)
                .truncationMode(.head)
            Rectangle().fill(SeleneTheme.focus)
                .frame(width: canvas.u(SeleneTokens.Space.seam), height: canvas.u(SeleneTokens.Space.section))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.large))
        .frame(width: canvas.u(OnScreenKeyboard.width), height: canvas.u(64))
        .oortWell(radius: canvas.u(SeleneTokens.Radius.field))
        .accessibilityHidden(true)
    }
}
