import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

extension SetupCheckView {
    /// The shell sends every controller action (and the keys, mapped) here while
    /// the Setup check is up.
    func handle(_ action: GamepadAction) {
        guard viewModel.showSetupCheck, NSApp.modalWindow == nil,
              viewModel.firstRunSetup.page == .requirements else { return }
        if pendingTool != nil {
            switch action {
            case .navigateLeft: toolFocus = .left
            case .navigateRight: toolFocus = .right
            case .confirm: if toolFocus == .confirm { confirmTool() } else { pendingTool = nil }
            case .cancel: pendingTool = nil
            default: break
            }
            return
        }
        switch action {
        case .navigateLeft: navigate(.left)
        case .navigateRight: navigate(.right)
        case .navigateUp: navigate(.up)
        case .navigateDown: navigate(.down)
        case .confirm: activate()
        case .cancel:
            if isFirstRun { backToFound() } else { close() }
        default: break
        }
    }

    func move(to next: SetupFocus) {
        guard next != focus else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    /// The first card that needs something, else Continue; once, when the cards arrive.
    func placeInitialFocus() {
        guard !focusPlaced, !items.isEmpty else { return }
        focusPlaced = true
        if let index = items.firstIndex(where: { $0.isRequired && $0.state != .ready }) { focus = .card(index) }
    }

    private func navigate(_ direction: MoveDirection) {
        switch focus {
        case .card(let index):
            if let next = SetupGrid.move(from: index, direction, rowCounts: rows) {
                move(to: .card(next))
            } else if direction == .down {
                // Onto the nearer button.
                move(to: .carryOn)
            }
        case .carryOn:
            switch direction {
            case .up:
                guard let last = rows.indices.last else { return }
                let start = rows.prefix(last).reduce(0, +)
                let nearest = (start..<(start + rows[last])).min {
                    abs(SetupGrid.offset(of: $0, rowCounts: rows)) < abs(SetupGrid.offset(of: $1, rowCounts: rows))
                }
                if let nearest { move(to: .card(nearest)) }
            default: break
            }
        }
    }

    func activate() {
        guard viewModel.showSetupCheck, viewModel.firstRunSetup.page == .requirements,
              NSApp.modalWindow == nil else { return }
        switch focus {
        case .card(let index):
            guard items.indices.contains(index) else { return }
            let item = items[index]
            guard item.state != .working, item.actionTitle != nil || item.state == .needsYou else {
                shake()
                return
            }
            SoundEffectService.shared.play(.click)
            if item.id == .metal || item.id == .engine {
                toolFocus = .cancel
                pendingTool = item.id
            } else { setup.activate(item.id) }
        case .carryOn:
            SoundEffectService.shared.play(.click)
            viewModel.advanceSetupToGames()
        }
    }

    /// B during the first launch: back to what Arcane found on the Mac.
    func backToFound() {
        SoundEffectService.shared.play(.back)
        viewModel.returnToFound()
    }

    func close() {
        viewModel.showSetupCheck = false
    }

    func shake() {
        SoundEffectService.shared.play(.error)
        withAnimation(SeleneTheme.shake) { shakes += 1 }
    }
}
