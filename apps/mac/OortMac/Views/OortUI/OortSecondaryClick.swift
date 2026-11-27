import AppKit
import SwiftUI
import OortLibrary

/// A right click (or Control-click) on a piece, which opens its options like + does; every other event goes
/// through to the piece. The options stay reachable without it: this only doubles the hint and the button.
private struct OortSecondaryClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> SecondaryClickView { SecondaryClickView(action) }
    func updateNSView(_ view: SecondaryClickView, context: Context) { view.action = action }
}

final class SecondaryClickView: NSView {
    var action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    static func isSecondary(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return event.type == .rightMouseDown || event.type == .leftMouseDown && event.modifierFlags.contains(.control)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        Self.isSecondary(NSApp.currentEvent) ? super.hitTest(point) : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) { action() }
    override func mouseDown(with event: NSEvent) { if Self.isSecondary(event) { action() } else { super.mouseDown(with: event) } }
}

private struct OortLivePointerKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The window takes the pointer. Still images have none, and draw no AppKit view.
    var oortLivePointer: Bool {
        get { self[OortLivePointerKey.self] }
        set { self[OortLivePointerKey.self] = newValue }
    }
}

private struct OortSecondaryClickLayer: ViewModifier {
    @Environment(\.oortLivePointer) private var live
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .overlay { if live { OortSecondaryClick(action: action).accessibilityHidden(true) } }
                .accessibilityAction(named: Text(L10n.text("Options")), action)
        } else {
            content
        }
    }
}

extension View {
    /// Right click: the same options as + on the selected piece. Nil leaves the click alone.
    func oortSecondaryClick(_ action: (() -> Void)?) -> some View { modifier(OortSecondaryClickLayer(action: action)) }
}
