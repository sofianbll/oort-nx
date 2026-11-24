import Foundation
import AppKit
import Combine
import NXLibraryCore

final class GameControllerService: ObservableObject {
    static let shared = GameControllerService()

    enum AssignmentEvent: Equatable { case button(String), cancelled, timedOut }
    private struct Assignment {
        let token: UUID
        let receive: (AssignmentEvent) -> Void
        var cancelling = false
    }
    private var assignment: Assignment?
    private var assignmentTimer: Timer?

    @Published var isGamepadConnected: Bool = false
    @Published var activeControllerName: String = "No Gamepad Connected"
    @Published var activeBrand: GamepadBrand = .generic
    /// Reported glyphs (including system remapping); the brand supplies missing glyphs.
    @Published var buttonSymbols: [PromptButton: String] = [:]
    @Published private(set) var menuHoldStartedAt: TimeInterval?
    @Published private(set) var connectedControllers: [ConnectedController] = []
    private let buttonPresses = PassthroughSubject<String, Never>()
    var controllerButtonPresses: AnyPublisher<String, Never> { buttonPresses.eraseToAnyPublisher() }

    var onAction: ((GamepadAction) -> Void)?

    private let deadzoneKey = "NXNative_ControllerDeadzone"
    @Published private(set) var deadzone: Float = 0.35
    var legacyDeadzone: Double {
        guard let preferences, preferences.object(forKey: deadzoneKey) != nil else { return 0.35 }
        return min(max(preferences.double(forKey: deadzoneKey), 0.10), 0.80)
    }
    func useDeadzone(_ value: Double?) {
        let next = Float(min(max(value ?? legacyDeadzone, 0.10), 0.80))
        if next != deadzone { deadzone = next }
    }

    var navigationInterval: TimeInterval = 0.12
    private var isAppActive = true
    private var lastNavTime: TimeInterval = 0

    private let gcSource: ControllerSource
    private let hidSource: ControllerSource
    private let preferences: UserDefaults?
    private var gcPad: ControllerIdentity?
    private var roster = ControllerRoster()
    private var visibleControllers: [ControllerRoster.Entry] = []
    private var sleeping = false
    private var statusTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private struct HIDPad {
        let identity: ControllerIdentity
        var admission: ControllerArbitration.HID
    }
    private var hidPads: [HIDPad] = []
    private var fallbackTimer: Timer?
    private var activePad: ControllerIdentity?
    private var inputGeneration = 0

    private var holds: [ControllerButton: HoldDetector] = [:]
    private var holdTimers: [ControllerButton: Timer] = [:]

    private convenience init() {
        self.init(gcSource: GCControllerSource(), hidSource: HIDControllerSource(), preferences: AppData.preferences)
    }

    // Fakes pass no preferences and never initialize AppKit or enumerate hardware.
    init(gcSource: ControllerSource, hidSource: ControllerSource, preferences: UserDefaults? = nil) {
        self.gcSource = gcSource
        self.hidSource = hidSource
        self.preferences = preferences
        if preferences != nil {
            useDeadzone(nil)
            isAppActive = NSApplication.shared.isActive
            observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification) { service in
                service.isAppActive = true
                service.refreshControllers()
            }
            observe(NotificationCenter.default, NSApplication.didResignActiveNotification) { service in
                service.isAppActive = false
                service.finishAssignment(event: .cancelled)
                service.resetInput()
            }
            let workspace = NSWorkspace.shared.notificationCenter
            observe(workspace, NSWorkspace.willSleepNotification) { $0.suspendControllers() }
            observe(workspace, NSWorkspace.didWakeNotification) { $0.resumeControllers() }
        }
        gcSource.onEvent = { [weak self] in self?.handle($0, fromHID: false) }
        hidSource.onEvent = { [weak self] in self?.handle($0, fromHID: true) }
        gcSource.start()
        hidSource.start()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ action: @escaping (GameControllerService) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            if let self { action(self) }
        }
        observers.append((center, token))
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
        statusTimer?.invalidate()
        fallbackTimer?.invalidate()
        assignmentTimer?.invalidate()
    }

    /// Lease the input before it is turned into menu, Home, View or navigation actions.
    func waitForAssignment(timeout: TimeInterval = 12, receive: @escaping (AssignmentEvent) -> Void) -> (() -> Void)? {
        guard assignment == nil, isAppActive, !sleeping else { return nil }
        let token = UUID()
        resetInput()
        assignment = .init(token: token, receive: receive)
        let timer = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
            self?.finishAssignment(token, event: .timedOut)
        }
        RunLoop.main.add(timer, forMode: .common)
        assignmentTimer = timer
        return { [weak self] in self?.finishAssignment(token) }
    }

    private func finishAssignment(_ token: UUID? = nil, event: AssignmentEvent? = nil) {
        guard let waiting = assignment, token == nil || token == waiting.token else { return }
        assignment = nil
        assignmentTimer?.invalidate()
        assignmentTimer = nil
        resetInput()
        if let event { waiting.receive(event) }
    }

    @discardableResult
    func identify(_ connectionID: String) -> Bool {
        guard !sleeping,
              let entry = visibleControllers.first(where: { $0.connectionID == connectionID }) else { return false }
        if let id = entry.secondaryGCID, gcSource.identify(id) { return true }
        return source(for: entry).identify(entry.controller.id)
    }

    func suspendControllers() {
        guard !sleeping else { return }
        sleeping = true
        finishAssignment(event: .cancelled)
        roster.suspend()
        gcPad = nil
        hidPads.removeAll()
        selectController()
        resetInput()
        gcSource.stop()
        hidSource.stop()
        updateRoster()
    }

    func resumeControllers() {
        guard sleeping else { return }
        sleeping = false
        gcSource.start()
        hidSource.start()
    }

    func refreshControllers() {
        guard !sleeping else { return }
        gcSource.refresh()
        hidSource.start()
        selectController()
        updateRoster()
    }

    private func handle(_ event: ControllerSourceEvent, fromHID: Bool) {
        guard !sleeping else { return }
        switch event {
        case let .connected(identity, claimedByGC):
            roster.connect(identity, isHID: fromHID, claimedByGC: claimedByGC)
            if fromHID {
                if identity.supportsNavigation && !hidPads.contains(where: { $0.identity.id == identity.id }) {
                    hidPads.append(HIDPad(identity: identity,
                                          admission: .init(name: identity.name, claimedByGC: claimedByGC,
                                                           connectedAt: ProcessInfo.processInfo.systemUptime)))
                }
            } else if gcSource.preferredID == identity.id {
                gcPad = identity
            }
        case let .disconnected(id):
            roster.disconnect(id)
            if fromHID {
                hidPads.removeAll { $0.identity.id == id }
            } else if gcPad?.id == id {
                gcPad = nil
            }
        case let .input(id, input):
            if let waiting = assignment {
                if case let .button(button, true) = input {
                    if button == .b, id == activePad?.id {
                        assignment?.cancelling = true
                        // HID delivers the raw press before the mapped changes in the same report.
                        DispatchQueue.main.async { [weak self] in self?.finishAssignment(waiting.token, event: .cancelled) }
                    } else if !fromHID { queueAssignment(id, fromHID: false) }
                }
                return
            }
            if !fromHID, case .button(_, true) = input { emitButtonPress(id) }
            if activePad?.id == id { handleInput(input) }
            return
        case let .buttonPressed(id):
            if assignment != nil { queueAssignment(id, fromHID: fromHID) }
            else { emitButtonPress(id) }
            return
        }
        selectController()
        updateRoster()
    }

    private func queueAssignment(_ id: ObjectIdentifier, fromHID: Bool) {
        guard let waiting = assignment, let entry = visibleControllers.first(where: {
            $0.controller.id == id || (!fromHID && $0.secondaryGCID == id)
        }),
        // For a proven pair use the GC activity once, not its duplicate HID event.
        !fromHID || entry.secondaryGCID == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.assignment?.token == waiting.token, self.assignment?.cancelling == false,
                  self.visibleControllers.contains(where: { $0.connectionID == entry.connectionID }) else { return }
            self.finishAssignment(waiting.token, event: .button(entry.connectionID))
        }
    }

    private func emitButtonPress(_ id: ObjectIdentifier) {
        guard isAppActive,
              let entry = visibleControllers.first(where: { $0.controller.id == id }) else { return }
        buttonPresses.send(entry.connectionID)
    }

    private func source(for entry: ControllerRoster.Entry) -> ControllerSource { entry.isHID ? hidSource : gcSource }

    private func updateRoster() {
        let visible = roster.visible
        visibleControllers = visible
        hidSource.observe(Set(visible.filter(\.isHID).map(\.controller.id)))
        let current = roster.snapshot(visible) { entry in
            let primary = source(for: entry).status(entry.controller.id)
            guard let id = entry.secondaryGCID else { return primary }
            let secondary = gcSource.status(id)
            return ControllerStatus(batteryLevel: primary.batteryLevel ?? secondary.batteryLevel,
                                    isCharging: primary.isCharging ?? secondary.isCharging,
                                    canIdentifyWithLights: primary.canIdentifyWithLights || secondary.canIdentifyWithLights,
                                    canIdentifyWithRumble: primary.canIdentifyWithRumble || secondary.canIdentifyWithRumble)
        }
        if connectedControllers != current { connectedControllers = current }
        if current.isEmpty {
            statusTimer?.invalidate()
            statusTimer = nil
        } else if statusTimer == nil {
            let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.updateRoster() }
            RunLoop.main.add(timer, forMode: .common)
            statusTimer = timer
        }
    }

    private func selectController() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        let now = ProcessInfo.processInfo.systemUptime
        let gcNames = gcPad?.name.map { [$0] } ?? []
        var eligible: [ControllerIdentity] = []
        var deadline: TimeInterval?
        for index in hidPads.indices {
            switch hidPads[index].admission.admission(gcNames: gcNames, at: now) {
            case .gameController: break
            case .hid: eligible.append(hidPads[index].identity)
            case let .wait(until): deadline = min(deadline ?? until, until)
            }
        }
        switch ControllerArbitration.preferred(hasGameController: gcPad != nil, hasHID: !eligible.isEmpty) {
        case .gameController:
            hidSource.select(nil)
            setActive(gcPad)
            return
        case .hid:
            if let activePad, eligible.contains(activePad) { return }
            setActive(eligible.first { hidSource.select($0.id) })
        case .wait, nil:
            hidSource.select(nil)
            setActive(nil)
        }
        if activePad == nil, let deadline {
            let timer = Timer(timeInterval: max(0, deadline - now), repeats: false) { [weak self] _ in
                self?.refreshControllers()
            }
            RunLoop.main.add(timer, forMode: .common)
            fallbackTimer = timer
        }
    }

    private func setActive(_ pad: ControllerIdentity?) {
        if activePad?.id != pad?.id {
            resetInput()
        }
        guard activePad != pad else { return }
        activePad = pad
        isGamepadConnected = pad != nil
        activeControllerName = pad.map { $0.name ?? L10n.text("Gamepad") } ?? "No Gamepad Connected"
        activeBrand = pad?.brand ?? .generic
        buttonSymbols = pad?.symbols ?? [:]
    }

    private func handleInput(_ input: ControllerInputChange) {
        guard isAppActive else { return }
        switch input {
        case let .leftStick(stick):
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastNavTime > navigationInterval else { return }
            let action: GamepadAction
            if stick.x > deadzone { action = .navigateRight }
            else if stick.x < -deadzone { action = .navigateLeft }
            else if stick.y > deadzone { action = .navigateUp }
            else if stick.y < -deadzone { action = .navigateDown }
            else { return }
            lastNavTime = now
            triggerAction(action)
        case let .button(button, pressed):
            if button == .menu || button == .view || button == .home {
                handleHold(button, pressed: pressed)
            } else if pressed, let action = GamepadAction.onPress(button) {
                triggerAction(action)
            }
        }
    }

    private func handleHold(_ button: ControllerButton, pressed: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard pressed else {
            var detector = holds.removeValue(forKey: button)
            let action = detector?.release(at: now)
                .flatMap { GamepadAction.holdAction(button, $0) }
            stopHoldTimer(button)
            if let action { triggerAction(action) }
            return
        }
        guard holds[button] == nil else { return }
        holds[button, default: HoldDetector()].press(at: now)
        guard button != .home else { return }
        if button == .menu { menuHoldStartedAt = now }
        let timer = Timer(timeInterval: HoldDetector.defaultThreshold, repeats: false) { [weak self] _ in
            guard let self, let result = self.holds[button]?.tick(at: ProcessInfo.processInfo.systemUptime),
                  let action = GamepadAction.holdAction(button, result) else { return }
            self.stopHoldTimer(button)
            self.triggerAction(action)
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimers[button] = timer
    }

    private func stopHoldTimer(_ button: ControllerButton) {
        holdTimers.removeValue(forKey: button)?.invalidate()
        if button == .menu { menuHoldStartedAt = nil }
    }

    private func resetInput() {
        inputGeneration += 1
        holds.removeAll()
        for button in holdTimers.keys { stopHoldTimer(button) }
        lastNavTime = 0
    }

    private func triggerAction(_ action: GamepadAction) {
        let generation = inputGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isAppActive, self.inputGeneration == generation else { return }
            self.onAction?(action)
        }
    }
}
