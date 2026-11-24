import Foundation
import NXLibraryCore

extension Notification.Name {
    static let nxIntegrationsAction = Self("NXIntegrationsAction")
}

extension AppRouter {
    func handleIntegrationBar(_ action: GamepadAction, profileFocused: inout Bool, hasProfile: Bool) -> Bool {
        if integrationBarFocused, [.secondaryAction, .contextAction, .jumpToStart, .jumpToEnd].contains(action) { return true }
        let step: MenuStep? = switch action {
        case .navigateLeft: .left
        case .navigateRight: .right
        case .navigateUp: .up
        case .navigateDown: .down
        case .confirm: .confirm
        case .cancel: .back
        default: nil
        }
        return stepIntegrationBar(step, profileFocused: &profileFocused, hasProfile: hasProfile)
    }
}

extension IntegrationsView {
    func handle(_ action: GamepadAction) {
        let ids = overview.rows.map(\.id)
        guard let first = ids.first else { return }
        let id = router.integrationFocus ?? first
        switch action {
        case .navigateUp, .navigateDown:
            let index = ids.firstIndex(of: id) ?? 0
            let next = min(max(index + (action == .navigateUp ? -1 : 1), 0), ids.count - 1)
            router.integrationFocus = ids[next]
        case .confirm: overview.open(id, in: router)
        case .cancel: router.back()
        default: break
        }
    }

    static func keyAction(_ key: UInt16) -> GamepadAction? {
        switch key {
        case 126: .navigateUp
        case 125: .navigateDown
        case 36, 49, 76: .confirm
        case 53: .cancel
        default: nil
        }
    }
}
