import AppKit
import CoreHaptics
import GameController
import NXLibraryCore

protocol ControllerHomeSettings {
    func observe(_ update: @escaping (ControllerHomeAccess) -> Void) -> () -> Void
    func open()
}

func observeControllerHome(_ settings: ControllerHomeSettings?, hasHome: Bool,
                           update: @escaping (ControllerHomeAccess) -> Void) -> () -> Void {
    guard hasHome else { update(.noHome); return {} }
    guard let settings else { update(.launcher); return {} }
    update(.unavailable)
    return settings.observe(update)
}

@available(macOS 27, *)
private struct MacControllerHomeSettings: ControllerHomeSettings {
    func observe(_ update: @escaping (ControllerHomeAccess) -> Void) -> () -> Void {
        let task = Task { @MainActor in
            guard !Task.isCancelled, !GCController.controllers().isEmpty else { return }
            let manager = GCControllerHomeButtonSettingsManager()
            func read() {
                guard !Task.isCancelled, !GCController.controllers().isEmpty else { return }
                switch try? manager.controllerHomeButtonInAppAction.action {
                case .defer, .disabled: update(.launcher)
                case .systemDefault: update(.system)
                default: update(.unavailable)
                }
            }
            read()
            for await _ in manager.settingsUpdates { read() }
        }
        return { task.cancel() }
    }

    func open() {
        Task { @MainActor in
            guard !GCController.controllers().isEmpty else { return }
            try? GCControllerHomeButtonSettingsManager().openControllerHomeButtonSettings(for: .customizeInAppAction)
        }
    }
}

final class GCControllerSource: ControllerSource {
    var onEvent: ((ControllerSourceEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var controller: GCController?
    /// Every pad with a full profile is read; the service keeps the input of the one in use.
    private var unbind: [ObjectIdentifier: () -> Void] = [:]
    private var homeAccesses: [ObjectIdentifier: ControllerHomeAccess] = [:]
    private var connected: [ObjectIdentifier: GCController] = [:]
    private var unbindActivity: [ObjectIdentifier: () -> Void] = [:]
    private var stopIdentification: [ObjectIdentifier: () -> Void] = [:]
    private var generation = 0
    var preferredID: ObjectIdentifier? { controller.map(ObjectIdentifier.init) }
    private let homeSettings: ControllerHomeSettings?
    var onHomeAccess: ((ControllerHomeAccess) -> Void)?
    private(set) var homeAccess: ControllerHomeAccess = .disconnected {
        didSet { if oldValue != homeAccess { onHomeAccess?(homeAccess) } }
    }
    private func readHomeAccess() {
        homeAccess = controller.map { homeAccesses[ObjectIdentifier($0)] ?? .noHome } ?? .disconnected
    }

    func prefer(_ id: ObjectIdentifier) {
        guard let next = connected[id], next !== controller, next.extendedGamepad != nil else { return }
        controller = next
        readHomeAccess()
    }
    var canOpenHomeSettings: Bool { controller?.extendedGamepad?.buttonHome != nil && homeSettings != nil }

    convenience init() {
        if #available(macOS 27, *) { self.init(homeSettings: MacControllerHomeSettings()) }
        else { self.init(homeSettings: nil) }
    }

    init(homeSettings: ControllerHomeSettings?) { self.homeSettings = homeSettings }

    func openHomeSettings() {
        guard canOpenHomeSettings else { return }
        homeSettings?.open()
    }

    func start() {
        guard observers.isEmpty else { return }
        observers = [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
    }

    func stop() {
        let previous = Array(connected.keys)
        tearDown()
        for id in previous { onEvent?(.disconnected(id)) }
    }

    deinit { tearDown() }

    private func tearDown() {
        generation += 1
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        for cleanup in unbind.values { cleanup() }
        unbind.removeAll()
        homeAccesses.removeAll()
        controller = nil
        homeAccess = .disconnected
        for cleanup in unbindActivity.values { cleanup() }
        for cleanup in stopIdentification.values { cleanup() }
        unbindActivity.removeAll()
        stopIdentification.removeAll()
        connected.removeAll()
    }

    func refresh() {
        guard !observers.isEmpty else { return }
        // A controller without an extended profile can't drive the launcher.
        let controllers = GCController.controllers().filter { !$0.isSnapshot }
        let usable = controllers.filter { $0.extendedGamepad != nil }
        let next = usable.first { $0 === controller } ?? usable.first
        let current = Set(controllers.map(ObjectIdentifier.init))
        let removed = connected.keys.filter { !current.contains($0) }
        for id in removed {
            unbind.removeValue(forKey: id)?()
            homeAccesses.removeValue(forKey: id)
            unbindActivity.removeValue(forKey: id)?()
            stopIdentification.removeValue(forKey: id)?()
            connected.removeValue(forKey: id)
        }
        controller = next
        // Publish a replacement first so the service doesn't briefly fall back to HID.
        let ordered = (next.map { [$0] } ?? []) + controllers.filter { $0 !== next }
        for item in ordered {
            let id = ObjectIdentifier(item)
            connected[id] = item
            let brand = Self.brand(vendor: item.vendorName ?? "", category: item.productCategory)
            let pad = item.extendedGamepad
            var symbols: [PromptButton: String] = [:]
            if let pad {
                let face = Self.faceButtons(pad, nintendo: brand == .nintendoSwitch)
                let view = Self.viewButton(pad, brand: brand)
                if unbind[id] == nil { bind(item, pad: pad, face: face, view: view) }
                symbols = Self.symbols(pad, face: face, view: view)
            } else if unbindActivity[id] == nil {
                bindActivity(item, excluding: [])
            }
            onEvent?(.connected(ControllerIdentity(id: id, name: item.vendorName, brand: brand, symbols: symbols,
                                                  supportsNavigation: pad != nil)))
        }
        readHomeAccess()
        for id in removed { onEvent?(.disconnected(id)) }
    }

    private func bindActivity(_ controller: GCController, excluding: Set<ObjectIdentifier>) {
        let id = ObjectIdentifier(controller)
        let generation = generation
        let profile = controller.physicalInputProfile
        let directions = profile.dpads.values.flatMap { [$0.up, $0.down, $0.left, $0.right] }
        var seen = excluding
        let buttons = (Array(profile.buttons.values) + directions).filter { seen.insert(ObjectIdentifier($0)).inserted }
        for button in buttons {
            button.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
                guard pressed else { return }
                let deliver = { [weak self, weak controller] in
                    guard let self, let controller, self.generation == generation, self.connected[id] === controller else { return }
                    self.onEvent?(.buttonPressed(id))
                }
                if Thread.isMainThread { deliver() } else { DispatchQueue.main.async(execute: deliver) }
            }
        }
        unbindActivity[id] = {
            for button in buttons { button.pressedChangedHandler = nil }
        }
    }

    func status(_ id: ObjectIdentifier) -> ControllerStatus {
        guard let controller = connected[id] else { return .init() }
        let battery = controller.battery
        let level = battery.flatMap {
            (0...1).contains($0.batteryLevel) && ($0.batteryLevel != 0 || $0.batteryState != .unknown) ? $0.batteryLevel : nil
        }
        let charging: Bool?
        switch battery?.batteryState {
        case .charging: charging = true
        case .full, .discharging: charging = false
        default: charging = nil
        }
        return .init(batteryLevel: level, isCharging: charging, canIdentifyWithLights: controller.light != nil,
                     canIdentifyWithRumble: controller.haptics != nil)
    }

    func identify(_ id: ObjectIdentifier) -> Bool {
        guard let controller = connected[id] else { return false }
        stopIdentification.removeValue(forKey: id)?()
        let cleanup: () -> Void
        let duration: TimeInterval
        if let light = controller.light {
            let previous = light.color
            let flash = previous.red > 0.5 ? GCColor(red: 0, green: 0.7, blue: 1) : GCColor(red: 1, green: 1, blue: 1)
            light.color = flash
            cleanup = { if light.color == flash { light.color = previous } }
            duration = 0.7
        } else if let engine = controller.haptics?.createEngine(withLocality: .default) {
            do {
                let event = CHHapticEvent(eventType: .hapticContinuous,
                                          parameters: [.init(parameterID: .hapticIntensity, value: 0.55)],
                                          relativeTime: 0, duration: 0.25)
                let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
                try engine.start()
                try player.start(atTime: CHHapticTimeImmediate)
                cleanup = { _ = player; engine.stop(completionHandler: nil) }
                duration = 0.35
            } catch {
                engine.stop(completionHandler: nil)
                return false
            }
        } else { return false }
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            self?.stopIdentification.removeValue(forKey: id)?()
        }
        stopIdentification[id] = { timer.invalidate(); cleanup() }
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    private func bind(_ controller: GCController, pad: GCExtendedGamepad, face: FaceButtons,
                      view: GCControllerButtonInput?) {
        let id = ObjectIdentifier(controller)
        let generation = generation
        let emit: (ControllerInputChange) -> Void = { [weak self, weak controller] input in
            // GameController defaults to the main queue; also honor the source contract
            // if the handler queue has been changed.
            let deliver = { [weak self, weak controller] in
                guard let self, let controller, self.generation == generation, self.connected[id] === controller else { return }
                self.onEvent?(.input(id, input))
            }
            if Thread.isMainThread { deliver() } else { DispatchQueue.main.async(execute: deliver) }
        }
        var buttons: [(GCControllerButtonInput, ControllerButton)] = [
            (pad.dpad.up, .up), (pad.dpad.down, .down), (pad.dpad.left, .left), (pad.dpad.right, .right),
            (face.confirm, .a), (face.cancel, .b), (face.secondary, .x), (face.context, .y),
            (pad.leftShoulder, .l), (pad.rightShoulder, .r),
            (pad.leftTrigger, .zl), (pad.rightTrigger, .zr), (pad.buttonMenu, .menu),
        ]
        let gestures = [pad.buttonMenu] + (view.map { [$0] } ?? [])
        if let view { buttons.append((view, .view)) }
        var unbindHome: (() -> Void)?
        if let home = pad.buttonHome, !buttons.contains(where: { $0.0 === home }) {
            buttons.append((home, .home))
            let previous = home.preferredSystemGestureState
            let refreshHome = { [weak self] in
                home.preferredSystemGestureState = NSApp.isActive && self?.homeAccesses[id] == .launcher ? .disabled : previous
            }
            let stopHome = observeControllerHome(homeSettings, hasHome: true) { [weak self, weak controller] state in
                guard let self, let controller, self.connected[id] === controller else { return }
                self.homeAccesses[id] = state
                self.readHomeAccess()
                refreshHome()
            }
            let homeObservers = [
                NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                       object: nil, queue: .main) { _ in refreshHome() },
                NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                       object: nil, queue: .main) { _ in home.preferredSystemGestureState = previous },
            ]
            unbindHome = {
                stopHome()
                homeObservers.forEach(NotificationCenter.default.removeObserver)
                home.preferredSystemGestureState = previous
            }
        }
        if let click = pad.rightThumbstickButton { buttons.append((click, .r3)) }
        if let click = pad.leftThumbstickButton { buttons.append((click, .l3)) }

        let systemGestures = gestures.map { ($0, $0.preferredSystemGestureState) }
        for (button, _) in systemGestures { button.preferredSystemGestureState = .disabled }
        for (button, control) in buttons {
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                if control != .home || self?.homeAccesses[id] == .launcher { emit(.button(control, pressed)) }
            }
        }
        pad.leftThumbstick.valueChangedHandler = { _, x, y in emit(.leftStick(SIMD2(x, y))) }
        pad.rightThumbstick.valueChangedHandler = { _, x, y in emit(.rightStick(SIMD2(x, y))) }
        bindActivity(controller, excluding: Set(buttons.map { ObjectIdentifier($0.0) }))
        unbind[id] = {
            unbindHome?()
            for (button, _) in buttons { button.pressedChangedHandler = nil }
            for (button, state) in systemGestures { button.preferredSystemGestureState = state }
            pad.leftThumbstick.valueChangedHandler = nil
            pad.rightThumbstick.valueChangedHandler = nil
        }
    }

    private static func viewButton(_ pad: GCExtendedGamepad, brand: GamepadBrand) -> GCControllerButtonInput? {
        let button = brand == .playstation
            ? (pad as? GCDualSenseGamepad)?.touchpadButton ?? (pad as? GCDualShockGamepad)?.touchpadButton
            : pad.buttonOptions
        return button === pad.buttonMenu ? nil : button
    }

    static func brand(vendor: String, category: String) -> GamepadBrand {
        switch category {
        case GCProductCategoryDualSense, GCProductCategoryDualShock4: return .playstation
        case GCProductCategoryXboxOne: return .xbox
        default: break
        }
        let lower = (vendor + " " + category).lowercased()
        if lower.contains("switch") || lower.contains("joy-con") || lower.contains("nintendo") {
            return .nintendoSwitch
        } else if lower.contains("xbox") || lower.contains("microsoft") {
            return .xbox
        } else if lower.contains("dualsense") || lower.contains("dualshock") || lower.contains("sony") || lower.contains("playstation") {
            return .playstation
        }
        return .generic
    }

    private struct FaceButtons {
        let confirm, cancel, secondary, context: GCControllerButtonInput
    }

    /// GameController maps by position (A = bottom). Keep a Nintendo profile
    /// already mapped by the printed A, otherwise use the right button.
    private static func faceButtons(_ pad: GCExtendedGamepad, nintendo: Bool) -> FaceButtons {
        if nintendo, pad.buttonA.unmappedSfSymbolsName?.hasPrefix("a.") != true {
            return FaceButtons(confirm: pad.buttonB, cancel: pad.buttonA,
                               secondary: pad.buttonY, context: pad.buttonX)
        }
        return FaceButtons(confirm: pad.buttonA, cancel: pad.buttonB,
                           secondary: pad.buttonX, context: pad.buttonY)
    }

    private static func symbols(_ pad: GCExtendedGamepad, face: FaceButtons,
                                view: GCControllerButtonInput?) -> [PromptButton: String] {
        let elements: [PromptButton: GCControllerElement?] = [
            .a: face.confirm, .b: face.cancel, .x: face.secondary, .y: face.context,
            .lb: pad.leftShoulder, .rb: pad.rightShoulder,
            .lt: pad.leftTrigger, .rt: pad.rightTrigger,
            .rs: pad.rightThumbstickButton, .ls: pad.leftThumbstickButton, .view: view, .menu: pad.buttonMenu, .home: pad.buttonHome,
        ]
        return elements.compactMapValues { element in
            guard let name = element?.sfSymbolsName, !name.isEmpty,
                  !ButtonPrompts.isGenericShape(name) else { return nil }
            return name
        }
    }
}
