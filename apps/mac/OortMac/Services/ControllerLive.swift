import Combine
import Foundation
import OortLibrary

/// What the active controller's hands are doing now. Apart from `GameControllerService`, so only what draws the pad
/// follows every stick value.
@MainActor final class ControllerLive: ObservableObject {
    static let shared = ControllerLive()

    @Published private(set) var held: Set<ControllerButton> = []
    @Published private(set) var left = SIMD2<Float>.zero
    @Published private(set) var right = SIMD2<Float>.zero
    /// True while something is held or still fading.
    @Published private(set) var awake = false
    private(set) var released: [ControllerButton: TimeInterval] = [:]
    private var rest: Task<Void, Never>?

    static let fade: TimeInterval = 0.36

    func receive(_ input: ControllerInputChange, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        switch input {
        case let .button(button, pressed):
            if pressed { held.insert(button) } else if held.remove(button) != nil { released[button] = now }
        case let .leftStick(stick): left = stick
        case let .rightStick(stick): right = stick
        }
        wake()
    }

    func reset() {
        held = []
        left = .zero
        right = .zero
        released = [:]
    }

    /// 1 while held, then out.
    func light(_ button: ControllerButton, at now: TimeInterval) -> Double {
        if held.contains(button) { return 1 }
        guard let since = released[button].map({ now - $0 }), since < Self.fade else { return 0 }
        return 1 - since / Self.fade
    }

    private func wake() {
        awake = true
        rest?.cancel()
        guard held.isEmpty, left == .zero, right == .zero else { return }
        rest = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fade + 0.1))
            guard !Task.isCancelled else { return }
            self?.awake = false
        }
    }
}

#if DEBUG
extension ControllerLive {
    /// A pad mid-press, for the gallery.
    static let sample: ControllerLive = {
        let live = ControllerLive()
        for button in [ControllerButton.a, .up, .zr] { live.receive(.button(button, true)) }
        live.receive(.leftStick(SIMD2(0.8, 0.4)))
        return live
    }()
}
#endif
