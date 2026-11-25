import AppKit
import SwiftUI
import NXLibraryCore

extension Notification.Name {
    static let playersPIN = Notification.Name("ArcanePlayersPIN")
}

extension PlayersScreen {
    var gridFocus: PlayersScreenModel.Row {
        switch model.page {
        case .profiles:
            return model.focusedRow ?? .profile(nil)
        case .swap(let number):
            if case .swapWith = model.focus { return model.focus }
            return .swapWith(number)
        case .player(let number): return .player(number)
        default:
            switch model.focus {
            case .player, .mode, .retry: return model.focus
            case .mergeTarget: return .player(model.mergeTarget)
            default: return .mode(model.plan.mode)
            }
        }
    }

    var focusedPlayer: Int? {
        if case .player(let number) = gridFocus { return number }
        return nil
    }

    var profilePlayer: Int? {
        if case .profiles(let number) = model.page { return number }
        return nil
    }

    var isMoving: Bool {
        if case .swap = model.page { return true }
        return false
    }

    var isEditing: Bool { isMoving || profilePlayer != nil }

    var commandHints: [HintItem] {
        guard model.readable else {
            return model.loading ? [] : [HintItem(.a, "Retry", action: activate)]
        }
        if isEditing {
            return [HintItem(.navigate, "Move"), HintItem(.a, "Select", action: activate)]
        }
        guard let number = focusedPlayer else {
            return [HintItem(.navigate, "Move")] + resetHints + [HintItem(.a, "Select", action: activate)]
        }
        return placeHints(number) + [HintItem(.a, "Profile", action: activate)]
    }

    var resetHints: [HintItem] {
        model.rows.contains(.reset) ? [HintItem(.x, "Reset players") { model.select(.reset) }] : []
    }

    /// What a place can do, under the grid, on a right click and in the hints.
    func placeHints(_ number: Int) -> [HintItem] {
        guard model.readable, !isEditing else { return [] }
        var hints: [HintItem] = []
        if model.plan.slot(number) != nil {
            hints.append(HintItem(.x, "Move") { beginMove(number) })
            hints.append(HintItem(.y, "Free this place") { model.removePlayer(number) })
            if let title = controllerCommand(number) {
                hints.append(HintItem(.rs, title) { runControllerCommand(number) })
            }
        }
        if canSetMergeTarget(number) {
            hints.append(HintItem(.rt, "Give all controllers") { model.chooseMergeTarget(number) })
        }
        return hints
    }

    func back() {
        if isEditing, !model.saving, model.pin == nil, model.capturePlayer == nil, !model.confirmsReset {
            if let number = profilePlayer { model.open(.overview, focus: .player(number)) }
            if case .swap(let number) = model.page { model.open(.overview, focus: .player(number)) }
            return
        }
        if !model.back() { onClose() }
    }

    func activate() {
        switch gridFocus {
        case .mode(let mode): model.selectMode(mode)
        case .player(let number), .swapWith(let number): chooseCard(number)
        case .profile, .retry: model.select(gridFocus)
        default: break
        }
    }

    func chooseCard(_ number: Int) {
        if case .swap(let from) = model.page {
            if number == from { back() }
            else { model.movePlayer(from, to: number) }
        } else {
            model.chooseProfile(at: number)
        }
    }

    private func beginMove(_ number: Int) {
        guard !model.saving, model.plan.slot(number) != nil else { return }
        model.open(.swap(number), focus: .swapWith(number))
    }

    private func canSetMergeTarget(_ number: Int) -> Bool {
        (number == 1 || model.supportsExtendedMerge) && (model.plan.mode != .merge || model.mergeTarget != number)
    }

    private func controllerCommand(_ number: Int) -> String? {
        if model.identifiablePad(number) != nil { return "Identify" }
        return model.plan.mode != .merge && model.leaseCapture != nil ? "Assign controller" : nil
    }

    private func runControllerCommand(_ number: Int) {
        guard !model.saving else { return }
        if model.identifiablePad(number) != nil { model.identifyPlayer(number) }
        else if controllerCommand(number) != nil { model.startCapture(number) }
    }

    private func navigate(_ action: GamepadAction) {
        let modes = PlayerControllerMode.allCases
        switch gridFocus {
        case .mode(let mode):
            let index = modes.firstIndex(of: mode) ?? 0
            switch action {
            case .navigateLeft: model.focus = .mode(modes[max(0, index - 1)])
            case .navigateRight: model.focus = .mode(modes[min(modes.count - 1, index + 1)])
            case .navigateDown: model.focus = .player(index + 1)
            default: break
            }
        case .player(let number), .swapWith(let number):
            let columns = Self.columns
            let column = (number - 1) % columns
            let row = (number - 1) / columns
            if action == .navigateUp, row == 0, !isMoving {
                model.focus = .mode(modes[min(column, modes.count - 1)])
                return
            }
            let target: Int? = switch action {
            case .navigateLeft where column > 0: number - 1
            case .navigateRight where column < columns - 1: number + 1
            case .navigateUp where row > 0: number - columns
            case .navigateDown where model.places.contains(number + columns): number + columns
            default: nil
            }
            if let target { model.focus = isMoving ? .swapWith(target) : .player(target) }
        case .profile:
            switch action {
            case .navigateLeft, .navigateUp: model.move(-1)
            case .navigateRight, .navigateDown: model.move(1)
            default: break
            }
        default: break
        }
    }

    private func tab(_ step: Int) {
        if isEditing && !isMoving {
            model.move(step)
            return
        }
        let rows = isMoving ? model.places.map(PlayersScreenModel.Row.swapWith)
            : PlayerControllerMode.allCases.map(PlayersScreenModel.Row.mode) + model.places.map(PlayersScreenModel.Row.player)
        guard let index = rows.firstIndex(of: gridFocus) else { return }
        model.focus = rows[min(rows.count - 1, max(0, index + step))]
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
        let previous = gridFocus
        switch action {
        case .navigateUp, .navigateDown, .navigateLeft, .navigateRight: navigate(action)
        case .confirm: activate()
        case .cancel: back()
        case .secondaryAction where !isEditing:
            if let number = focusedPlayer { beginMove(number) }
            else { model.select(.reset) }
        case .contextAction where !isEditing:
            if let number = focusedPlayer { model.removePlayer(number) }
        case .rightStickPress where !isEditing:
            if let number = focusedPlayer { runControllerCommand(number) }
        case .jumpToEnd where !isEditing:
            if let number = focusedPlayer, canSetMergeTarget(number) { model.chooseMergeTarget(number) }
        default: break
        }
        if previous != gridFocus { SoundEffectService.shared.play(.focus) }
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
                tab(event.modifierFlags.contains(.shift) ? -1 : 1)
                return nil
            }
        case 126: action = .navigateUp
        case 125: action = .navigateDown
        case 123: action = .navigateLeft
        case 124: action = .navigateRight
        case 36, 49, 76: action = .confirm
        case 53: action = .cancel
        case 7: action = .secondaryAction
        case 16: action = .contextAction
        case 1, 99: action = .rightStickPress  // S, or F3 where Mission Control leaves it
        case 119: action = .jumpToEnd
        default: return event
        }
        if !event.isARepeat || [.navigateUp, .navigateDown, .navigateLeft, .navigateRight].contains(action) {
            handleController(action)
        }
        return nil
    }
}
