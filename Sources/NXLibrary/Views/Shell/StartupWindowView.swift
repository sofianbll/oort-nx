import AppKit
import SwiftUI

/// Reads the launch preference once; changing Settings never changes the current window's mode. `onSettled` runs
/// once the window has its launch mode (after it has faded in and gone full screen, or at once without a transition;
/// at most 3 s after the window's own wait).
struct StartupWindowView: NSViewRepresentable {
    let fullscreen: Bool
    var onSettled: () -> Void = {}
    func makeNSView(context: Context) -> StartupWindowObserver {
        StartupWindowObserver(fullscreen: fullscreen, onSettled: onSettled)
    }
    func updateNSView(_ view: StartupWindowObserver, context: Context) { view.guardWindowClose() }
    static func dismantleNSView(_ view: StartupWindowObserver, coordinator: ()) { view.detach() }
}

final class StartupWindowObserver: NSView {
    private let fullscreen: Bool
    private let onSettled: () -> Void
    private var applied = false
    private var settled = false
    private var observer: NSObjectProtocol?
    private var transition: [NSObjectProtocol] = []
    private let closeGuard = CloudWindowCloseGuard()
    private weak var observedWindow: NSWindow?

    init(fullscreen: Bool, onSettled: @escaping () -> Void) {
        self.fullscreen = fullscreen
        self.onSettled = onSettled
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        guardWindowClose()
        guard !applied, let window else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
            object: window, queue: .main) { [weak self] _ in self?.applyWhenReady() }
        applyWhenReady()
        // Never held longer: a window that is not made key, or a transition that never reports its end.
        DispatchQueue.main.asyncAfter(deadline: .now() + LaunchReveal.limit + 3) { [weak self] in self?.settle() }
    }

    private func applyWhenReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.applied, let window = self.window else { return }
            guard window.isVisible, window.isKeyWindow else { return }
            self.applied = true
            self.stop()
            // The fullscreen transition animates a picture of the window: it waits for the window to show the
            // moonlight (`LaunchReveal`), never a black window.
            LaunchReveal.whenShown { [weak self] in self?.applyMode(window) }
        }
    }

    private func applyMode(_ window: NSWindow) {
        guard window.styleMask.contains(.fullScreen) != fullscreen else { return settle() }
        transition = [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification]
            .map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.settle()
                }
            }
        window.toggleFullScreen(nil)
    }

    private func settle() {
        guard !settled else { return }
        settled = true
        transition.forEach(NotificationCenter.default.removeObserver)
        transition = []
        onSettled()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func detach() {
        stop()
        if AppDelegate.shellWindow === observedWindow { AppDelegate.shellWindow = nil }
        if observedWindow?.delegate === closeGuard { observedWindow?.delegate = closeGuard.original }
        observedWindow = nil
        closeGuard.original = nil
    }

    func guardWindowClose() {
        guard let window, window.delegate !== closeGuard else { return }
        observedWindow = window
        AppDelegate.shellWindow = window
        closeGuard.original = window.delegate
        window.delegate = closeGuard
    }
}

/// Keep the shell visible for the confirmation instead of closing its only window first.
private final class CloudWindowCloseGuard: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if AppDelegate.cloudLibrary?.isWorking == true || AppDelegate.settingsStore?.draft?.hasChanges == true {
            NSApp.terminate(nil)
            return false
        }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
}
