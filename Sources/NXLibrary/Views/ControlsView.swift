import SwiftUI
import AppKit
import NXLibraryCore

extension Notification.Name {
    static let nxControlsGamepadAction = Notification.Name("NXControlsGamepadAction")
}

/// Library navigation and the pinned engine's default game inputs are separate guides.
struct ControlsView: View {
    var layout: GamepadLayout = .arcane
    let onClose: () -> Void
    let canHandleInput: () -> Bool
    @ObservedObject private var controller = GameControllerService.shared
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var inGame = false
    @State private var focus = 0
    /// The kind shown: the connected one until another is picked.
    @State private var picked: ControllerShape.Family?
    @State private var keyMonitor: Any?

    init(layout: GamepadLayout = .arcane, canHandleInput: @escaping () -> Bool, onClose: @escaping () -> Void) {
        self.layout = layout
        self.canHandleInput = canHandleInput
        self.onClose = onClose
    }

    private var connectedKind: ControllerShape.Kind {
        .init(brand: controller.activeBrand, name: controller.activeControllerName)
    }

    private var shownKind: ControllerShape.Kind { picked?.kind(connected: connectedKind) ?? connectedKind }

    /// What each button of the shown controller does, by its place on it.
    private var entries: [OortControllerMap.Entry] {
        let kind = shownKind, shape = ControllerShape.of(kind)
        if inGame {
            // The engine's keys (front_mac.m, key_bit), by the Switch button each one is.
            let keys: [(ControllerButton, String, String)] = [
                (.zl, "ZL", "Z"), (.l, "L", "Q"), (.l3, L10n.text("Left stick"), "W A S D"),
                (.up, L10n.text("D-pad"), L10n.text("Arrow keys")), (.view, "−", "Tab"), (.zr, "ZR", "C"), (.r, "R", "E"),
                (.x, "X", "U"), (.y, "Y", "I"), (.a, "A", "J"), (.b, "B", "K"), (.menu, "+", "Return"),
                (.r3, L10n.text("Right stick"), L10n.text("Shift + Arrow keys")),
            ]
            return keys.map { button, title, key in
                .init(button: shape.switchName(button), name: key, title: title)
            }
        }
        return Self.libraryEntries(layout, kind: kind, hasHome: controller.homeAccess.hasHome || !controller.isGamepadConnected)
    }

    static func libraryEntries(_ layout: GamepadLayout, kind: ControllerShape.Kind, hasHome: Bool) -> [OortControllerMap.Entry] {
        [.init(button: .up, name: "✚", title: L10n.text("Move"))] + layout.guide(hasHome: hasHome).map { binding in
            .init(button: binding.button, name: ButtonPrompts.label(binding.prompt, style: kind.names, connected: .other),
                  title: L10n.text(binding.tap.guideTitle),
                  hold: binding.hold.map { L10n.format("Hold: %@", [L10n.text($0.guideTitle)]) })
        }
    }

    private func nextKind() {
        let all = ControllerShape.Family.allCases
        picked = all[(all.firstIndex(of: .init(shownKind))! + 1) % all.count]
    }

    private var rows: [(String, String)] {
        if inGame {
            // nxnative dm/host/front_mac.m: key_bit, on_key and push.
            return [
                (L10n.text("Left stick"), "W · A · S · D"),
                (L10n.text("D-pad"), L10n.text("Arrow keys")),
                ("A · B · X · Y", "J · K · U · I"),
                ("L · R", "Q · E"),
                ("ZL · ZR", "Z · C"),
                (L10n.text("Press left / right stick"), "F · G"),
                (L10n.text("Plus · Minus"), L10n.text("Return · Tab")),
                (L10n.text("Shake"), L10n.text("Hold Space")),
                (L10n.text("Right stick"), L10n.text("Shift + Arrow keys · Controller")),
                (L10n.text("Touchscreen"), L10n.text("Click and drag · Handheld mode")),
                ("Gamepad", L10n.text("USB or Bluetooth · Button positions follow the engine's layout")),
                ("Rumble", L10n.text("Depends on the game, build and controller")),
                // nxnative 48888df5 (home_quit.h): held for 2 s, a prompt; A quits as ⌘Q does, B or Home goes back.
                (L10n.text("Quit the game"), "⌘Q · Hold Home for 2 s, then A, in games built with the current engine")
            ]
        }
        let pad = ConnectedPad(connected: controller.isGamepadConnected, brand: controller.activeBrand)
        return [
            ("Move", L10n.text("Arrows · D-pad or left stick")),
        ] + layout.guide(hasHome: controller.homeAccess.hasHome)
            .map { (L10n.text($0.tap.guideTitle), $0.summary(style: .automatic, pad: pad)) } + [
            (L10n.text("Search everywhere"), PaletteAction.paletteShortcut),
            (L10n.text("Menu"), "⇧⌘K"),
            (L10n.text("Settings"), "⌘,"),
            (L10n.text("Search"), "⌘F"),
            (L10n.text("Profiles"), "⇧⌘P"),
            (L10n.text("Move a tile"), L10n.text("Options of the card, then Move"))
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small)) {
                        Text(L10n.text("Controls"))
                            .seleneFont(.screen)
                            .foregroundColor(SeleneTheme.ink)
                        Text(inGame ? L10n.text("Default game inputs. Older builds may differ.") : L10n.text("Navigate Oort."))
                            .seleneFont(.text)
                            .foregroundColor(SeleneTheme.ink60)
                            .padding(.bottom, canvas.u(SeleneTokens.Space.control))
                        SeleneSegmented(selection: $inGame, options: [(false, "Library"), (true, "In game")])
                            .padding(.bottom, canvas.u(SeleneTokens.Space.control))
                        SeleneSegmented(selection: Binding(get: { .init(shownKind) }, set: { picked = $0 }),
                                        options: ControllerShape.Family.allCases.map { ($0, $0.kind(connected: connectedKind).title) })
                        OortControllerMap(kind: shownKind, entries: entries)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, canvas.u(SeleneTokens.Space.section))
                        SeleneOptionRow(icon: .gamepad, title: L10n.text("Controller"),
                            about: controller.isGamepadConnected ? controller.activeControllerName : L10n.text("Not connected"),
                            focused: focus == 0) {
                            Button(L10n.text("Detect")) { controller.refreshControllers() }
                                .buttonStyle(OortPressStyle())
                                .seleneFont(.text, .semibold)
                                .foregroundColor(SeleneTheme.glyph)
                        }
                        .id(0)
                        ForEach(rows.indices, id: \.self) { index in
                            SeleneOptionRow(icon: nil, title: rows[index].0,
                                about: rows[index].1, focused: focus == index + 1) { EmptyView() }
                                .id(index + 1)
                        }
                    }
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.section))
                    .padding(.top, canvas.u(SeleneTokens.Space.pageTopCompact))
                    .padding(.bottom, canvas.u(SeleneTokens.Space.dialogInset))
                    .frame(maxWidth: max(700, canvas.u(1120)), alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .onChange(of: focus) { _, value in
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(value, anchor: .center) }
                }
                .onChange(of: inGame) { focus = 0; proxy.scrollTo(0, anchor: .top) }
            }
            SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"), action: onClose)],
                right: [HintItem(.lb, L10n.text("Library")) { inGame = false }, HintItem(.rb, L10n.text("In game")) { inGame = true },
                        HintItem(.x, L10n.text("Other controller"), action: nextKind)])
        }
        .background(SeleneBackdrop())
        .environment(\.seleneMinimumFont, 12)
        .onAppear(perform: installKeyMonitor)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxControlsGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
    }

    private func handle(_ action: GamepadAction) {
        guard canHandleInput() else { return }
        switch action {
        case .cancel: onClose()
        case .tabPrevious, .navigateLeft: inGame = false
        case .tabNext, .navigateRight: inGame = true
        case .navigateUp: focus = max(0, focus - 1)
        case .navigateDown: focus = min(rows.count, focus + 1)
        case .secondaryAction: nextKind()
        case .confirm: if focus == 0 { controller.refreshControllers() }
        default: break
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard canHandleInput(), let window = event.window, !window.isSheet,
                  window.attachedSheet == nil, NSApp.modalWindow == nil,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 53: handle(.cancel)
            case 126: handle(.navigateUp)
            case 125: handle(.navigateDown)
            case 123, 12: handle(.tabPrevious)
            case 124, 14: handle(.tabNext)
            case 36, 76, 49: handle(.confirm)
            case 7: handle(.secondaryAction)
            default: return event
            }
            return nil
        }
    }
}
