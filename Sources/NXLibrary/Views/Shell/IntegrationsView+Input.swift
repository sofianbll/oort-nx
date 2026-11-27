import Foundation
import NXLibraryCore
import ArcanePorting

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
        if let id = router.integrationDetail, let row = overview.row(id) {
            switch action {
            case .confirm:
                if let focus = detailFocus(row) { activate(focus, for: row) }
            case .cancel: router.backFromIntegration()
            case .navigateUp, .navigateDown:
                let actions = row.actions
                if let focus = detailFocus(row), let index = actions.firstIndex(of: focus) {
                    router.integrationAction = actions[min(max(index + (action == .navigateUp ? -1 : 1), 0), actions.count - 1)]
                }
            default: break
            }
            return
        }
        let ids = overview.sections.flatMap { $0.entries.map(\.id) }
        guard !ids.isEmpty, let id = catalogueFocus else { return }
        switch action {
        case .navigateUp, .navigateDown:
            let index = ids.firstIndex(of: id) ?? 0
            let next = min(max(index + (action == .navigateUp ? -1 : 1), 0), ids.count - 1)
            router.integrationFocus = ids[next]
        case .confirm: router.showIntegrationDetail(id)
        case .secondaryAction: if flip(id) { SoundEffectService.shared.play(.key) }
        case .cancel: router.backFromIntegration()
        default: break
        }
    }

    /// The row's switch, from the list: focus stays on the row, and the owner says the new state.
    @discardableResult
    func flip(_ id: IntegrationID) -> Bool {
        router.integrationFocus = id
        guard overview.row(id)?.switchOn != nil, toggle(id) else {
            SoundEffectService.shared.play(.error)
            return false
        }
        return true
    }

    func detailFocus(_ row: IntegrationRow) -> IntegrationDetailAction? {
        row.actions.first { $0 == router.integrationAction } ?? row.actions.last
    }

    func activate(_ action: IntegrationDetailAction, for row: IntegrationRow) {
        switch action {
        case .settings: overview.open(row.id, in: router)
        case .switchGames: router.browseIntegrationLibrary(.nxnative)
        case .steamGames: router.browseIntegrationLibrary(.steam)
        }
    }

    static func keyAction(_ key: UInt16) -> GamepadAction? {
        switch key {
        case 126: .navigateUp
        case 125: .navigateDown
        case 36, 49, 76: .confirm
        case 7: .secondaryAction
        case 53: .cancel
        default: nil
        }
    }
}
