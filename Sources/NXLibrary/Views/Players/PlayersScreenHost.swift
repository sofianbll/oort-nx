import AppKit
import SwiftUI

/// Hooks the Selene screen into its parent's regular input route.
struct PlayersScreenHost: View {
    struct Notes {
        var order: [Int: String] = [:]
        var mode: String?
        var profiles: [Int: String] = [:]
        var supportsExtendedMerge = false
    }

    @StateObject var model: PlayersScreenModel
    @ObservedObject var controller: GameControllerService
    let input: Notification.Name
    let canHandleInput: () -> Bool
    let onClose: () -> Void
    var readNotes: (() async -> Notes)?
    var hasSettingsDraft = false
    var saveSettingsDraft: (() -> Void)?

    @Environment(\.seleneHintsCovered) private var covered
    @State private var notes = Notes()
    @State private var monitor: Any?

    var body: some View {
        let screen = PlayersScreen(model: model, onClose: onClose,
                                   orderNotes: notes.order, modeNote: notes.mode, profileNotes: notes.profiles,
                                   saveSettingsDraft: hasSettingsDraft ? saveSettingsDraft : nil)
        screen
            .task { await model.load() }
            .task(id: model.saving) {
                guard !model.saving, let readNotes else { return }
                let result = await readNotes()
                if !Task.isCancelled {
                    notes = result
                    model.showsGameLimits = true
                    model.supportsExtendedMerge = result.supportsExtendedMerge
                }
            }
            .onReceive(controller.$connectedControllers) { model.updatePads($0) }
            .onChange(of: covered) { _, isCovered in
                if isCovered && model.capturePlayer != nil { model.endCapture() }
            }
            .onReceive(NotificationCenter.default.publisher(for: input)) { event in
                guard !covered, canHandleInput(), let action = event.object as? GamepadAction else { return }
                if hasSettingsDraft, let saveSettingsDraft, action == .contextAction,
                   !model.saving, model.pin == nil, model.capturePlayer == nil, !model.confirmsReset {
                    saveSettingsDraft()
                    return
                }
                screen.handleController(action)
            }
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard !covered, canHandleInput(), !NativeMenuCommands.shared.isTracking,
                          let window = event.window, window.isKeyWindow, !window.isSheet,
                          window.attachedSheet == nil, NSApp.modalWindow == nil else { return event }
                    if hasSettingsDraft, event.keyCode == 16, event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                       !model.saving, model.pin == nil, model.capturePlayer == nil, !model.confirmsReset {
                        saveSettingsDraft?()
                        return nil
                    }
                    return screen.handleKey(event)
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
