// Adapted from NX2Apple frontend-ios/Sources/ShellUI/ShellFocus.swift (ShellKeyboardNavigation) and ShellModalRouting.swift
// (ShellKeyboardCommandPolicy) at a79d397 (MIT, Copyright (c) 2026 seedds, jhaizhou, LNPANDY and NX2Apple contributors).
// One responder for the whole app, since Oort NX has one input log; the arrows win over the system's own focus.
import ShellModel
import SwiftUI

#if os(iOS)
/// A hardware keyboard's arrows, Return, Escape, O (options), Y or ⌘F (search) and comma (settings). It is not a text field,
/// so no on-screen keyboard comes up, and it stands aside while one is typed in or something is presented over the app.
struct OortKeys: UIViewRepresentable {
    /// Where the player is: a change gives the responder another chance to take the keys.
    let place: [String]
    let handle: (ShellInput.Action) -> Void
    func makeUIView(context: Context) -> Responder { Responder() }
    func updateUIView(_ view: Responder, context: Context) {
        view.handle = handle
        view.claimSoon()
    }

    final class Responder: UIView {
        var handle: ((ShellInput.Action) -> Void)?
        private static let actions: [(String, ShellInput.Action)] = [
            (UIKeyCommand.inputLeftArrow, .left), (UIKeyCommand.inputRightArrow, .right),
            (UIKeyCommand.inputUpArrow, .up), (UIKeyCommand.inputDownArrow, .down),
            ("\r", .activate), (UIKeyCommand.inputEscape, .back), ("o", .settings), ("y", .search), (",", .shellSettings),
        ]
        private var observers: [NSObjectProtocol] = []

        override var canBecomeFirstResponder: Bool { window != nil && !covered && !typing }

        override var keyCommands: [UIKeyCommand]? {
            (Self.actions.map { UIKeyCommand(input: $0.0, modifierFlags: [], action: #selector(pressed(_:))) }
             + [UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(pressed(_:)))]).map {
                $0.wantsPriorityOverSystemBehavior = true
                return $0
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = window == nil ? [] : [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification,
                                              UIWindow.didBecomeKeyNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.claimSoon() }
                }
            }
            claimSoon()
        }

        /// After the change that asked for it: the screen or the field is gone by then.
        func claimSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self, !isFirstResponder, canBecomeFirstResponder else { return }
                becomeFirstResponder()
            }
        }

        private var covered: Bool { window?.rootViewController?.presentedViewController != nil }

        private var typing: Bool {
            func editing(_ view: UIView) -> Bool { (view.isFirstResponder && view is UITextInput) || view.subviews.contains(where: editing) }
            return window.map(editing) ?? false
        }

        @objc private func pressed(_ command: UIKeyCommand) {
            guard !covered, let action = command.modifierFlags == .command ? .search : Self.actions.first(where: { $0.0 == command.input })?.1 else { return }
            handle?(action)
        }
    }
}
#endif
