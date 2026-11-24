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

    @Environment(\.seleneHintsCovered) private var covered
    @State private var notes = Notes()
    @State private var monitor: Any?
    @State private var stopJoining: (() -> Void)?

    var body: some View {
        let screen = PlayersScreen(model: model, onClose: onClose,
                                   orderNotes: notes.order, modeNote: notes.mode, profileNotes: notes.profiles)
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
            .onChange(of: covered, initial: true) { _, isCovered in
                stopJoining?()
                stopJoining = nil
                if isCovered {
                    model.stopJoining()
                    if model.capturePlayer != nil { model.endCapture() }
                } else {
                    stopJoining = controller.watchPlayerJoining { id in
                        guard canHandleInput(), !NativeMenuCommands.shared.isTracking, NSApp.modalWindow == nil,
                              let window = NSApp.keyWindow, !window.isSheet, window.attachedSheet == nil else { return false }
                        return model.joinController(id)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: input)) { event in
                guard !covered, canHandleInput(), let action = event.object as? GamepadAction else { return }
                screen.handleController(action)
            }
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard !covered, canHandleInput(), !NativeMenuCommands.shared.isTracking,
                          let window = event.window, window.isKeyWindow, !window.isSheet,
                          window.attachedSheet == nil, NSApp.modalWindow == nil else { return event }
                    return screen.handleKey(event)
                }
            }
            .onDisappear {
                stopJoining?()
                stopJoining = nil
                model.stopJoining()
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
