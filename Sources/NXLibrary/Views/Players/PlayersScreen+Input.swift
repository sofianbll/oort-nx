import AppKit
import SwiftUI

extension Notification.Name {
    static let playersPIN = Notification.Name("ArcanePlayersPIN")
}

extension PlayersScreen {
    func back() {
        if !model.back() { onClose() }
    }

    func activate() {
        if let row = model.focusedRow { model.select(row) }
    }

    func handleController(_ action: GamepadAction) {
        if model.capturePlayer != nil { return }
        if model.pin != nil {
            NotificationCenter.default.post(name: .playersPIN, object: action)
            return
        }
        if model.confirmsReset {
            switch action {
            case .navigateLeft: model.resetFocus = .left
            case .navigateRight: model.resetFocus = .right
            case .confirm: if model.resetFocus == .confirm { model.reset() } else { back() }
            case .cancel: back()
            default: break
            }
            return
        }
        let previous = model.focusedRow
        switch action {
        case .navigateUp: model.move(-1)
        case .navigateDown: model.move(1)
        case .confirm: activate()
        case .cancel: back()
        default: break
        }
        if previous != model.focusedRow { SoundEffectService.shared.play(.focus) }
    }

    func handleKey(_ event: NSEvent) -> NSEvent? {
        if model.capturePlayer != nil {
            if event.keyCode == 53, !event.isARepeat { back() }
            return nil
        }
        if model.pin != nil { return ProfilePINDialog.handleKey(event, input: .playersPIN) }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return event }
        let action: GamepadAction
        switch event.keyCode {
        case 48:
            if model.confirmsReset {
                action = event.modifierFlags.contains(.shift) ? .navigateLeft : .navigateRight
            } else {
                action = event.modifierFlags.contains(.shift) ? .navigateUp : .navigateDown
            }
        case 126: action = .navigateUp
        case 125: action = .navigateDown
        case 123: action = .navigateLeft
        case 124: action = .navigateRight
        case 36, 49, 76: action = .confirm
        case 53: action = .cancel
        default: return event
        }
        if !event.isARepeat || action == .navigateUp || action == .navigateDown { handleController(action) }
        return nil
    }
}
