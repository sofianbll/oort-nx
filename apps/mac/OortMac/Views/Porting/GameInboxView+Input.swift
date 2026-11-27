import Foundation
import NXLibraryCore
import SwiftUI

extension Notification.Name {
    static let nxGameInboxAction = Notification.Name("nxGameInboxAction")
}

extension GameInboxView {
    static func keyAction(_ key: UInt16) -> GamepadAction? {
        switch key {
        case 126: return .navigateUp
        case 125: return .navigateDown
        case 123: return .navigateLeft
        case 124: return .navigateRight
        case 36, 76, 49: return .confirm
        case 53: return .cancel
        default: return nil
        }
    }

    func input(_ action: GamepadAction) {
        if action == .cancel {
            router.back()
            return
        }
        guard !model.busy else { return }
        let targets = actions
        let index = targets.firstIndex(of: focused) ?? 0
        switch action {
        case .navigateUp, .navigateLeft: focused = targets[max(0, index - 1)]
        case .navigateDown, .navigateRight: focused = targets[min(targets.count - 1, index + 1)]
        case .jumpToStart: focused = targets[0]
        case .jumpToEnd: focused = targets[targets.count - 1]
        case .confirm: run(focused)
        default: break
        }
        if targets[index] != focused { SoundEffectService.shared.play(.focus) }
    }

    func run(_ action: Action) {
        guard !model.busy, actions.contains(action) else { return }
        SoundEffectService.shared.play(.click)
        switch action {
        case .correction: model.offerGameFilesCorrection()
        case .folder: model.chooseFolder()
        case .refresh: model.refresh()
        case .sortAll: model.confirm(ready)
        case .file(let url): model.confirm(ready.filter { $0.id == url })
        }
    }
}
