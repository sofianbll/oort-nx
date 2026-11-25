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
    private var playerJoining: (owner: UUID, consume: (String) -> Bool)?
    private var joiningHID: ObjectIdentifier?

    @Published var isGamepadConnected: Bool = false
    @Published var activeControllerName: String = "No Gamepad Connected"
    @Published var activeBrand: GamepadBrand = .generic
    /// Reported glyphs (including system remapping); the brand supplies missing glyphs.
    @Published var buttonSymbols: [PromptButton: String] = [:]
    /// The last thing used, shared by every prompt: a button, a key, a click or a real move of the mouse.
    @Published private(set) var inputInHand = InputInHand()
    /// The controller the prompts name, or none while the keyboard or the mouse leads.
    var padInHand: ConnectedPad { ConnectedPad(connected: controllerInHand, brand: activeBrand) }
    var pointerInHand: Bool { inputInHand.device == .pointer }
    var controllerInHand: Bool { inputInHand.usesController(connected: isGamepadConnected) }
    @Published private(set) var menuHoldStartedAt: TimeInterval?
    @Published private(set) var connectedControllers: [ConnectedController] = []
    @Published private(set) var homeAccess: ControllerHomeAccess = .disconnected
    var canOpenHomeSettings: Bool { (gcSource as? GCControllerSource)?.canOpenHomeSettings == true }
    func openHomeSettings() { (gcSource as? GCControllerSource)?.openHomeSettings() }
    private let buttonPresses = PassthroughSubject<String, Never>()
    var controllerButtonPresses: AnyPublisher<String, Never> { buttonPresses.eraseToAnyPublisher() }

    var onAction: ((GamepadAction) -> Void)?
    var onPadUse: (() -> Bool)?
    var layout = GamepadLayout.arcane {
        didSet { if layout != oldValue { resetInput() } }
    }
    var isBrowsing: () -> Bool = { false }

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

    private var isAppActive = true
    private var repeats = DirectionRepeat()
    private var repeatTimer: Timer?

    private let gcSource: ControllerSource
    private let hidSource: ControllerSource
    private let preferences: UserDefaults?
    private var gcPads: [ObjectIdentifier: ControllerIdentity] = [:]
    /// The pad last pressed leads; until one is, the first that macOS lists.
    private var lastUsed: ObjectIdentifier?
    private var gcPad: ControllerIdentity? {
        if let lastUsed, let pad = gcPads[lastUsed] { return pad }
        return gcSource.preferredID.flatMap { gcPads[$0] }
    }
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
    private var eligibleHID: [ControllerIdentity] = []
    private var fallbackTimer: Timer?
    private var activePad: ControllerIdentity?
    private var inputGeneration = 0
    private var handMonitor: Any?
    /// Tracked apart so that a moving pointer publishes only when the hand really changes.
    private var hand = InputInHand()

    private struct PendingHold {
        let binding: GamepadLayout.Binding
        var detector = HoldDetector()
    }
    private var holds: [ControllerButton: PendingHold] = [:]
    private var holdTimers: [ControllerButton: Timer] = [:]
    private var settingsHoldButton: ControllerButton?

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
            watchHand()
        }
        gcSource.onEvent = { [weak self] in self?.handle($0, fromHID: false) }
        (gcSource as? GCControllerSource)?.onHomeAccess = { [weak self] access in
            guard let self else { return }
            self.homeAccess = access
            self.resetInput()
        }
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

    /// Installed before any screen's monitor, so it sees the events they keep for themselves; it keeps none.
    private func watchHand() {
        let events: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
                                             .mouseMoved]
        handMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.handUsed(event)
            return event
        }
    }

    func handUsed(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            PointerAnchor.location = NSEvent.mouseLocation
            useHand { $0.keyPressed() }
        case .mouseMoved:
            let distance = hypot(event.deltaX, event.deltaY)
            useHand { $0.pointerMoved(by: distance, at: event.timestamp) }
        case .scrollWheel:
            // Momentum keeps arriving after the fingers have left.
            if event.momentumPhase.isEmpty, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 { useHand { $0.pointerUsed() } }
        default: useHand { $0.pointerUsed() }
        }
    }

    private func useHand(_ change: (inout InputInHand) -> Void) {
        change(&hand)
        if hand.device != inputInHand.device { inputInHand = hand }
    }

    deinit {
        if let handMonitor { NSEvent.removeMonitor(handMonitor) }
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

    /// Only the visible Players page may claim the first press of an unassigned pad.
    func watchPlayerJoining(_ consume: @escaping (String) -> Bool) -> () -> Void {
        let owner = UUID()
        playerJoining = (owner, consume)
        return { [weak self] in
            if self?.playerJoining?.owner == owner { self?.playerJoining = nil }
        }
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
        gcPads.removeAll()
        lastUsed = nil
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
            } else if identity.supportsNavigation {
                gcPads[identity.id] = identity
            }
        case let .disconnected(id):
            roster.disconnect(id)
            if lastUsed == id { lastUsed = nil }
            if fromHID {
                hidPads.removeAll { $0.identity.id == id }
            } else {
                gcPads.removeValue(forKey: id)
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
            if !fromHID, case .button(_, true) = input {
                emitButtonPress(id)
                if consumePlayerJoining(id, fromHID: false) { return }
            }
            if fromHID, joiningHID == id { return }
            if activePad?.id != id, !fromHID, Self.takesOver(input) { takeOver(id) }
            if activePad?.id == id { handleInput(input) }
            return
        case let .buttonPressed(id):
            if assignment != nil { queueAssignment(id, fromHID: fromHID) }
            else {
                emitButtonPress(id)
                if consumePlayerJoining(id, fromHID: fromHID), fromHID {
                    // HID sends mapped changes synchronously after the raw press in the same report.
                    joiningHID = id
                    DispatchQueue.main.async { [weak self] in self?.joiningHID = nil }
                } else if fromHID, activePad?.id != id, eligibleHID.contains(where: { $0.id == id }) {
                    // Its mapped changes start with the next report: this press only wakes it.
                    takeOver(id)
                }
            }
            return
        }
        selectController()
        updateRoster()
    }

    /// A press, or a stick pushed right over: a second pad lying on the sofa never takes the menus.
    private static func takesOver(_ input: ControllerInputChange) -> Bool {
        switch input {
        case let .button(_, pressed): pressed
        case let .leftStick(stick), let .rightStick(stick): (stick * stick).sum() >= 0.64
        }
    }

    private func takeOver(_ id: ObjectIdentifier) {
        guard isAppActive else { return }
        lastUsed = id
        gcSource.prefer(id)
        selectController()
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

    private func consumePlayerJoining(_ id: ObjectIdentifier, fromHID: Bool) -> Bool {
        guard isAppActive, let playerJoining,
              let entry = visibleControllers.first(where: {
                  $0.controller.id == id || (!fromHID && $0.secondaryGCID == id)
              }),
              // A proven pair uses the GC event so the same press cannot navigate after joining.
              !fromHID || entry.secondaryGCID == nil else { return false }
        return playerJoining.consume(entry.connectionID)
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
        let gcNames = gcPads.values.compactMap(\.name)
        var eligible: [ControllerIdentity] = []
        var deadline: TimeInterval?
        for index in hidPads.indices {
            switch hidPads[index].admission.admission(gcNames: gcNames, at: now) {
            case .gameController: break
            case .hid: eligible.append(hidPads[index].identity)
            case let .wait(until): deadline = min(deadline ?? until, until)
            }
        }
        eligibleHID = eligible
        if let pad = eligible.first(where: { $0.id == lastUsed }), hidSource.select(pad.id) { return setActive(pad) }
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

    /// Sources report on the main thread; a late one waits its turn rather than stopping the app.
    private func onLive(_ change: @escaping @MainActor (ControllerLive) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { change(.shared) }
        } else {
            DispatchQueue.main.async { change(.shared) }
        }
    }

    private func handleInput(_ input: ControllerInputChange) {
        guard isAppActive else { return }
        onLive { $0.receive(input) }
        switch input {
        case let .leftStick(stick): move(repeats.stick(stick, deadzone: deadzone, from: .leftStick))
        case let .rightStick(stick): move(repeats.stick(stick, deadzone: deadzone, from: .rightStick))
        case let .button(button, pressed):
            if let direction = Self.directions[button] {
                if pressed {
                    move(repeats.press(direction, from: .pad) ? direction : nil)
                } else {
                    repeats.release(direction, from: .pad)
                    move(nil)
                }
                return
            }
            guard let binding = layout.binding(button, browsing: isBrowsing()) else { return }
            if binding.release {
                handleHold(binding, pressed: pressed)
            } else if pressed {
                triggerAction(binding.tap)
            }
        }
    }

    private static let directions: [ControllerButton: ControllerDirection] = [.up: .up, .down: .down, .left: .left, .right: .right]

    private static func action(_ direction: ControllerDirection) -> GamepadAction {
        switch direction {
        case .up: .navigateUp
        case .down: .navigateDown
        case .left: .navigateLeft
        case .right: .navigateRight
        }
    }

    /// Moves now when a direction is new, then keeps moving while something is held.
    private func move(_ direction: ControllerDirection?) {
        if let direction { triggerAction(Self.action(direction)) }
        guard repeats.current != nil else {
            repeatTimer?.invalidate()
            repeatTimer = nil
            return
        }
        // A stick sends many values: only a new direction, or the end of one, starts the wait again.
        if direction != nil || repeatTimer == nil { scheduleRepeat() }
    }

    private func scheduleRepeat() {
        repeatTimer?.invalidate()
        let timer = Timer(timeInterval: repeats.nextDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = nil
            guard self.isAppActive, let direction = self.repeats.tick() else { return self.repeats.reset() }
            self.triggerAction(Self.action(direction))
            self.scheduleRepeat()
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func handleHold(_ binding: GamepadLayout.Binding, pressed: Bool) {
        let button = binding.button
        let now = ProcessInfo.processInfo.systemUptime
        guard pressed else {
            var pending = holds.removeValue(forKey: button)
            stopHoldTimer(button)
            guard pending?.binding.tap == binding.tap, pending?.binding.hold == binding.hold else { return }
            let gesture = pending?.detector.release(at: now)
            let action = gesture.flatMap { $0 == .tap ? binding.tap : binding.hold }
            if let action { triggerAction(action) }
            return
        }
        guard holds[button] == nil else { return }
        var pending = PendingHold(binding: binding)
        pending.detector.press(at: now)
        holds[button] = pending
        guard let action = binding.hold else { return }
        if action == .menuHold || action == .fullMenu {
            settingsHoldButton = button
            menuHoldStartedAt = now
        }
        let timer = Timer(timeInterval: HoldDetector.defaultThreshold, repeats: false) { [weak self] _ in
            guard let self, self.holds[button]?.detector.tick(at: ProcessInfo.processInfo.systemUptime) != nil else { return }
            self.stopHoldTimer(button)
            if self.layout.binding(button, browsing: self.isBrowsing())?.hold == action {
                self.triggerAction(action)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimers[button] = timer
    }

    private func stopHoldTimer(_ button: ControllerButton) {
        holdTimers.removeValue(forKey: button)?.invalidate()
        if settingsHoldButton == button {
            settingsHoldButton = nil
            menuHoldStartedAt = nil
        }
    }

    private func resetInput() {
        inputGeneration += 1
        holds.removeAll()
        for button in holdTimers.keys { stopHoldTimer(button) }
        repeats.reset()
        repeatTimer?.invalidate()
        repeatTimer = nil
        onLive { $0.reset() }
    }

    private func triggerAction(_ action: GamepadAction) {
        useHand { $0.controllerUsed(at: ProcessInfo.processInfo.systemUptime) }
        if preferences != nil { PointerAnchor.location = NSEvent.mouseLocation }
        let generation = inputGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isAppActive, self.inputGeneration == generation else { return }
            if self.onPadUse?() != true { self.onAction?(action) }
        }
    }
}
