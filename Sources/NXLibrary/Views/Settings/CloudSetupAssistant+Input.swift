import AppKit
import NXLibraryCore

extension CloudSetupAssistant {
    func handleAssistantInput(_ action: GamepadAction) {
        guard viewModel.router?.isMenuPresented != true, !viewModel.cloudQuitRequested else { return }
        switch action {
        case .navigateUp: moveAssistantFocus(.up)
        case .navigateDown: moveAssistantFocus(.down)
        case .navigateLeft: moveAssistantFocus(.left)
        case .navigateRight: moveAssistantFocus(.right)
        case .confirm: perform(focusedTarget)
        case .cancel: cancel()
        default: break
        }
    }

    func installAssistantKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = event.window, window.attachedSheet == nil, !window.isSheet,
                  NSApp.modalWindow == nil, !NativeMenuCommands.shared.isTracking,
                  viewModel.router?.isMenuPresented != true, viewModel.router?.isPalettePresented != true,
                  !viewModel.cloudQuitRequested, !viewModel.noticeFocus.isActive,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
            let typing = window.firstResponder is NSText
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125: action = .navigateDown
            case 123 where !typing: action = .navigateLeft
            case 124 where !typing: action = .navigateRight
            case 36 where !typing, 49 where !typing, 76 where !typing: action = .confirm
            case 53: action = .cancel
            default: return event
            }
            handleAssistantInput(action)
            return nil
        }
    }

    func removeAssistantKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
