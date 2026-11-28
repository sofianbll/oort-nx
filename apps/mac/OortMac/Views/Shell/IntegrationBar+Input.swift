import Foundation
import OortLibrary

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
