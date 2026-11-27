#!/usr/bin/env python3
"""Drive the shell's actual key and restart paths with fake OS side effects."""
from pathlib import Path
import sys

from audit_probe_host import ROOT, run_host
import names  # noqa: E402  architecture/names.json (on sys.path from audit_probe_host)


def member(name, signature):
    source = (ROOT / "apps/mac/OortMac/Views/Shell" / name).read_text()
    start = source.index(signature)
    end = source.index("\n    }", start)
    return source[start:end + len("\n    }")]


shell = "AppShellView+Input.swift"
gesture = (member(shell, "func installGestureKeyMonitor()")
           .replace("NSEvent.addLocalMonitorForEvents", "InputMonitor.capture")
           .replace("[router, viewModel]", "[self, router, viewModel]"))
restart = member(shell, "func relaunchApp()")
notice_key = member(shell, "func noticeKeyAction(")
notice_room = member(shell, "var leavesNoticesRoom:")
palette = member("AppShellView+Palette.swift", "func paletteKey(")
modes = sys.argv[1:] or ["restart", "repeat", "palette"]
actions = {"restart": "restart", "repeat": "repeatKeys", "palette": "paletteKeyboard"}
if set(modes) - actions.keys():
    raise SystemExit("Use restart, repeat or palette")

run_host(r'''
import AppKit
import Combine
import OortLibrary
@testable import OortMac

@MainActor enum InputMonitor {
    static var handler: ((NSEvent) -> NSEvent?)!
    static func capture(matching: NSEvent.EventTypeMask, _ block: @escaping (NSEvent) -> NSEvent?) -> Int {
        handler = block
        return 1
    }
}

@MainActor final class Process {
    static var starts = 0
    var executableURL: URL?
    var arguments: [String]?
    func run() throws { Self.starts += 1 }
}
@MainActor final class NSApplication {
    static let shared = NSApplication()
    var quits = 0
    func terminate(_ sender: Any?) { quits += 1 }
}
@MainActor enum AppDelegate { static var relaunchScheduled = false }

@MainActor final class GameControllerService {
    static let shared = GameControllerService()
    var onAction: ((GamepadAction) -> Void)?
}
final class NoHardware: ControllerSource {
    var onEvent: ((ControllerSourceEvent) -> Void)?
    func start() {}
    func stop() {}
}
enum GameInboxView { static func keyAction(_ code: UInt16) -> GamepadAction? { nil } }
enum IntegrationsView { static func keyAction(_ code: UInt16) -> GamepadAction? { nil } }

@MainActor final class ShellProbe {
    let router = AppRouter()
    let viewModel = Model()
    let palette = CommandPalette()
    let nativeMenus = NativeMenus()
    let profiles = Profiles()
    var nativeDialogOwnsInput = false
    var showsWelcome = false
    var showsInstallFailure = false
    var showsUpdateOffer = false
    var showsSettingsNotice = false
    var isCloseGameOpen = false
    var isHomeRoute = true
    var gestureKeyMonitor: Int?
    let noticeKeys: [() -> Void] = []
    let canUndoLastChange = false
    var actions: [GamepadAction] = []
    struct NativeMenus { let isTracking = false }
    final class Profiles { var guest: Int? }
    final class Cloud { var isWorking = false }
    final class Model {
        var alertMessage: String?
        let cloudLibrary = Cloud()
        var launchOverlay: Int?
        var cloudQuitRequested = false
        var showSetupCheck = false
        var isGuidedSetupOpen = false
        var profileOwnsInput = false
        var isGameOptionsOpen = false
        var gameToClose: Int?
        var gameToRemove: Int?
        var cloudLibraryGameID: UUID?
        var noticeFocus = NoticeFocus()
        var notices = 0
        func showSettingsNotice(title: String, message: String) { notices += 1 }
    }
    func cloudQuitKey(_ code: UInt16) { actions.append(code == 123 ? .navigateLeft : .confirm) }
    func profileKey(_ event: NSEvent) -> NSEvent? { event }
    func activityCenterKey(_ code: UInt16) -> GamepadAction? { nil }
    func paletteInput(_ action: GamepadAction) { palette.handle(action) }
    func chooseNotice() {}
    func undoLastChange() {}
    // GESTURE
    // RESTART
    // NOTICE_KEY
    // NOTICE_ROOM
    // PALETTE

    func key(_ code: UInt16, repeated: Bool = false, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                         windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                         isARepeat: repeated, keyCode: code)!
    }

    func restart() -> Bool {
        var dirty = true
        router.openSettings(.startUp)
        router.hasPendingSettings = { dirty }
        relaunchApp()
        let deferred = router.settingsDecision == .leave && Process.starts == 0 &&
            NSApplication.shared.quits == 0 && !AppDelegate.relaunchScheduled
        router.finishSettingsDecision(proceed: false)
        let cancelled = Process.starts == 0 && !AppDelegate.relaunchScheduled
        relaunchApp()
        viewModel.cloudLibrary.isWorking = true
        dirty = false
        router.finishSettingsDecision(proceed: true)
        let rechecked = Process.starts == 0 && viewModel.notices == 1
        viewModel.cloudLibrary.isWorking = false
        dirty = true
        relaunchApp()
        dirty = false
        router.finishSettingsDecision(proceed: true)
        let allowed = Process.starts == 1 && AppDelegate.relaunchScheduled && NSApplication.shared.quits == 1
        print("Fake restart: deferred=\(deferred), cancelled=\(cancelled), guard rechecked=\(rechecked), allowed=\(allowed)")
        return deferred && cancelled && rechecked && allowed
    }

    func repeatKeys() -> Bool {
        installGestureKeyMonitor()
        GameControllerService.shared.onAction = { self.actions.append($0) }
        let monitor = APP_MODULE.GameControllerService(gcSource: NoHardware(), hidSource: NoHardware())
        func deliver(_ event: NSEvent) -> NSEvent? { monitor.monitorHand(event).flatMap(InputMonitor.handler) }
        router.isMenuPresented = true
        var power: [PowerAction] = []
        GameControllerService.shared.onAction = { action in
            guard action == .confirm else { return }
            switch self.router.menuStep(.confirm) {
            case .action(let icon): self.router.pressMenuIcon(icon)
            case .power(let action): power.append(action)
            default: break
            }
        }
        _ = deliver(key(36))
        let opened = router.menuSelection.isPowerOpen
        _ = deliver(key(36, repeated: true))
        var ok = opened && power.isEmpty
        if !ok { print("Held Return opened Power and requested \(power) (fake only)") }
        router.closeMenu()
        GameControllerService.shared.onAction = { self.actions.append($0) }
        typealias Context = (String, () -> Void, UInt16)
        let cases: [Context] = [
            ("control center", { self.router.isMenuPresented = true }, 123),
            ("close dialog", { self.router.isMenuPresented = false; self.isCloseGameOpen = true }, 123),
            ("Setup", { self.isCloseGameOpen = false; self.viewModel.showSetupCheck = true }, 123),
            ("cloud quit", { self.viewModel.showSetupCheck = false; self.viewModel.cloudQuitRequested = true }, 123),
        ]
        for (name, select, arrow) in cases {
            select()
            for code: UInt16 in [36, 49, 76] {
                actions = []
                let first = deliver(key(code))
                let later = deliver(key(code, repeated: true))
                let accepted = first == nil && later == nil && actions == [.confirm]
                if !accepted { print("Repeated confirmation reached \(name), key \(code): \(actions)"); ok = false }
            }
            actions = []
            if deliver(key(arrow, repeated: true)) != nil || actions != [.navigateLeft] {
                print("Repeated arrow did not reach \(name)"); ok = false
            }
        }
        viewModel.cloudQuitRequested = false
        viewModel.noticeFocus.enter(keys: 1)
        viewModel.isGameOptionsOpen = true
        actions = []
        let optionsOwnReturn = deliver(key(36)) != nil && !viewModel.noticeFocus.isActive && actions.isEmpty
        if !optionsOwnReturn { print("A notice took Return from Game Options"); ok = false }
        viewModel.isGameOptionsOpen = false
        router.openSettings(.cloudLibrary)
        router.settingsOverlayOwnsInput = true
        viewModel.noticeFocus.enter(keys: 1)
        let assistantOwnsReturn = deliver(key(36)) != nil && !viewModel.noticeFocus.isActive && actions.isEmpty
        if !assistantOwnsReturn { print("A notice took Return from the Drive assistant"); ok = false }
        router.settingsOverlayOwnsInput = false
        router.navigate(to: .console)
        viewModel.noticeFocus.enter(keys: 1)
        let consoleOwnsReturn = deliver(key(36)) != nil && !viewModel.noticeFocus.isActive && actions.isEmpty
        if !consoleOwnsReturn { print("A notice took Return from the console"); ok = false }
        if ok { print("Single confirmations and repeating arrows in all shell layers (no power action executed)") }
        return ok
    }

    func paletteKeyboard() -> Bool {
        let items = ["Moon", "Comet"].map { PaletteItem(id: $0, kind: .game, title: $0) }
        palette.open(items: items, recents: [], suggestions: items.map(\.id), symbols: [:])
        var chosen: [String] = []
        palette.onChoose = { item, _ in chosen.append(item.id) }
        // The controller route represents the already open virtual keyboard.
        GameControllerService.shared.onAction = { self.actions.append($0) }
        let down = paletteKey(key(125))
        let enter = paletteKey(key(36))
        _ = paletteKey(key(36, repeated: true))
        let ok = down == nil && enter == nil && chosen == ["Comet"] && actions.isEmpty
        print("Physical palette keys: ran \(chosen), controller route received \(actions)")
        return ok
    }
}

@main struct InputProbe {
    @MainActor static func main() {
        assertFixtureHome()
        var ok = true
        // CHECKS
        if !ok { exit(1) }
    }
}
'''.replace("// GESTURE", gesture).replace("// RESTART", restart).replace("// PALETTE", palette)
    .replace("// NOTICE_KEY", notice_key).replace("// NOTICE_ROOM", notice_room)
    .replace("APP_MODULE.", f"{names.APP}.")
    .replace("// CHECKS", "\n        ".join(f"if !ShellProbe().{actions[mode]}() {{ ok = false }}" for mode in modes)))
