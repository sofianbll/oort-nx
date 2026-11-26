import AppKit
import Combine
import Foundation
import NXLibraryCore

private final class FakeSource: ControllerSource {
    var onEvent: ((ControllerSourceEvent) -> Void)?
    var preferredID: ObjectIdentifier?
    var inventory: [(ControllerIdentity, Bool)] = []
    var selected: ObjectIdentifier?
    var observed: Set<ObjectIdentifier> = []
    var identified: [ObjectIdentifier] = []
    var statuses: [ObjectIdentifier: ControllerStatus] = [:]

    func start() { refresh() }
    func stop() { for (pad, _) in inventory { onEvent?(.disconnected(pad.id)) } }
    func refresh() { for (pad, claimed) in inventory { onEvent?(.connected(pad, claimedByGC: claimed)) } }
    func select(_ id: ObjectIdentifier?) -> Bool { selected = id; return true }
    func observe(_ ids: Set<ObjectIdentifier>) { observed = ids }
    func status(_ id: ObjectIdentifier) -> ControllerStatus { statuses[id, default: .init()] }
    func identify(_ id: ObjectIdentifier) -> Bool {
        identified.append(id)
        return status(id).canIdentifyWithLights || status(id).canIdentifyWithRumble
    }

    func add(_ pad: ControllerIdentity, claimed: Bool = false) {
        inventory.append((pad, claimed))
        onEvent?(.connected(pad, claimedByGC: claimed))
    }

    func remove(_ pad: ControllerIdentity) {
        inventory.removeAll { $0.0.id == pad.id }
        onEvent?(.disconnected(pad.id))
    }
}

@main struct ControllerIdentityProbe {
    static func main() {
        if CommandLine.arguments.contains("--fallback") { lastPressedLeads(); return }
        hashes()
        gameControllerTwins()
        mixedSourcesAndWake()
        dualSourceTwins()
        ambiguousPairStaysUnpaired(twinOnHID: false)
        ambiguousPairStaysUnpaired(twinOnHID: true)
        repeatedHardwareID()
        exclusiveAssignment()
        promptsFollowTheHand()
        lastPressedLeads()
        print("Controller identity: hash privacy, pairing, sticky ambiguity, activity, output routing, sleep and hot plug passed")
    }

    /// Two pads on the sofa: the one pressed drives the menus and names the buttons, without losing that press.
    private static func lastPressedLeads() {
        let gc = FakeSource(), hid = FakeSource()
        let objects = (0..<3).map { _ in NSObject() }
        let first = ControllerIdentity(id: ObjectIdentifier(objects[0]), name: "First", brand: .xbox)
        let second = ControllerIdentity(id: ObjectIdentifier(objects[1]), name: "Second", brand: .playstation,
                                        symbols: [.a: "xmark.circle"])
        let raw = ControllerIdentity(id: ObjectIdentifier(objects[2]), name: "Raw", brand: .nintendoSwitch)
        gc.preferredID = first.id
        gc.add(first)
        gc.add(second)
        let service = GameControllerService(gcSource: gc, hidSource: hid)
        var actions: [GamepadAction] = []
        service.onAction = { actions.append($0) }
        func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
        func press(_ pad: ControllerIdentity) {
            gc.onEvent?(.input(pad.id, .button(.a, true)))
            gc.onEvent?(.input(pad.id, .button(.a, false)))
            drain()
        }
        precondition(service.activeBrand == .xbox)
        for step in 0..<40 { gc.onEvent?(.input(second.id, .leftStick(SIMD2(step.isMultiple(of: 2) ? 0.5 : -0.3, 0.2)))) }
        drain()
        precondition(service.activeBrand == .xbox && actions.isEmpty, "A pad lying on the sofa takes nothing")
        press(second)
        precondition(service.activeBrand == .playstation && actions == [.confirm], "The press that wakes it counts")
        precondition(service.activeControllerName == "Second" && service.buttonSymbols[.a] == "xmark.circle")
        service.refreshControllers()
        precondition(service.activeBrand == .playstation, "A refresh keeps the pad in use")
        press(first)
        precondition(service.activeBrand == .xbox && actions == [.confirm, .confirm])
        hid.add(raw, claimed: true)
        hid.onEvent?(.buttonPressed(raw.id))
        precondition(service.activeBrand == .xbox, "A claimed HID pad waits for a matching GameController profile")
        RunLoop.main.run(until: Date().addingTimeInterval(2.2))
        precondition(service.activeBrand == .xbox)
        hid.onEvent?(.buttonPressed(raw.id))
        precondition(service.activeBrand == .nintendoSwitch && hid.selected == raw.id,
                     "The fallback deadline admits the second pad without a manual refresh")
        hid.onEvent?(.input(raw.id, .button(.b, true)))
        drain()
        precondition(actions.last == .cancel)
        press(second)
        precondition(service.activeBrand == .playstation && hid.selected == nil)
        gc.preferredID = first.id
        gc.remove(second)
        precondition(service.activeBrand == .xbox, "Unplugged, the other one leads")
        withExtendedLifetime(objects) {}
    }

    /// The prompts name the controller only while it is the last thing used, and never flicker.
    private static func promptsFollowTheHand() {
        let gc = FakeSource(), hid = FakeSource()
        let object = NSObject()
        let pad = ControllerIdentity(id: ObjectIdentifier(object), name: "Pad", brand: .playstation)
        let service = GameControllerService(gcSource: gc, hidSource: hid)
        precondition(service.padInHand == .none)
        gc.preferredID = pad.id
        gc.add(pad)
        precondition(service.padInHand == .playstation)
        func key() -> NSEvent {
            .keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                      characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
        }
        func mouse(_ type: NSEvent.EventType) -> NSEvent {
            .mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func press(_ input: ControllerInputChange) { gc.onEvent?(.input(pad.id, input)) }
        service.handUsed(key())
        precondition(service.padInHand == .none)
        var changes = 0
        let subscription = service.$inputInHand.dropFirst().sink { _ in changes += 1 }
        defer { subscription.cancel() }
        for step in 0..<60 { press(.leftStick(SIMD2(step.isMultiple(of: 2) ? 0.2 : -0.2, 0.1))) }
        precondition(service.padInHand == .none && changes == 0, "A drifting stick is no hand")
        press(.button(.a, true))
        precondition(service.padInHand == .playstation && changes == 1)
        press(.button(.a, false))
        for _ in 0..<60 { service.handUsed(mouse(.mouseMoved)) }
        precondition(service.padInHand == .playstation && changes == 1, "A still pointer's events are no hand")
        service.handUsed(mouse(.leftMouseDown))
        precondition(service.padInHand == .none && changes == 2)
        press(.leftStick(SIMD2(1, 0)))
        precondition(service.padInHand == .playstation)
        gc.preferredID = nil
        gc.remove(pad)
        precondition(service.padInHand == .none)
        withExtendedLifetime(object) {}
    }

    private static func exclusiveAssignment() {
        let gc = FakeSource(), hid = FakeSource()
        let menu = NSObject(), other = NSObject(), raw = NSObject()
        let first = ControllerIdentity(id: ObjectIdentifier(menu), name: "Menu pad", brand: .xbox)
        let second = ControllerIdentity(id: ObjectIdentifier(other), name: "Second", brand: .generic)
        let third = ControllerIdentity(id: ObjectIdentifier(raw), name: "Raw", brand: .nintendoSwitch)
        gc.preferredID = first.id
        gc.add(first)
        gc.add(second)
        hid.add(third)
        let service = GameControllerService(gcSource: gc, hidSource: hid)
        var actions: [GamepadAction] = []
        var assignments: [GameControllerService.AssignmentEvent] = []
        service.onAction = { actions.append($0) }
        func settle(_ time: TimeInterval = 0.01) { RunLoop.main.run(until: Date(timeIntervalSinceNow: time)) }
        func wait(_ timeout: TimeInterval = 12) -> () -> Void {
            service.waitForAssignment(timeout: timeout) { assignments.append($0) }!
        }
        // Starting a lease invalidates a queued menu command and an already armed hold.
        gc.onEvent?(.input(first.id, .button(.a, true)))
        gc.onEvent?(.input(first.id, .button(.menu, true)))
        let staleRelease = wait()
        precondition(service.menuHoldStartedAt == nil)
        gc.onEvent?(.input(first.id, .button(.home, true)))
        gc.onEvent?(.input(first.id, .button(.home, false)))
        gc.onEvent?(.input(first.id, .button(.menu, false)))
        settle()
        precondition(actions.isEmpty && assignments == [.button(service.connectedControllers[0].id)])
        _ = wait()
        staleRelease()
        gc.onEvent?(.buttonPressed(second.id))
        settle()
        precondition(actions.isEmpty && assignments.last == .button(service.connectedControllers[1].id))
        _ = wait()
        gc.onEvent?(.input(first.id, .button(.b, true)))
        gc.onEvent?(.input(first.id, .button(.b, false)))
        settle()
        precondition(actions.isEmpty && assignments.last == .cancelled)
        _ = wait(0.01)
        settle(0.04)
        precondition(assignments.last == .timedOut)
        gc.onEvent?(.input(first.id, .button(.a, true)))
        settle()
        precondition(actions == [.confirm])
        gc.remove(first)
        let count = assignments.count
        _ = wait()
        hid.onEvent?(.buttonPressed(third.id))
        hid.onEvent?(.input(third.id, .button(.b, true)))
        hid.onEvent?(.input(third.id, .button(.a, true)))
        settle()
        precondition(assignments.count == count + 1 && assignments.last == .cancelled && actions == [.confirm])
        let release = wait()
        release()
        hid.onEvent?(.input(third.id, .button(.a, true)))
        settle()
        precondition(actions == [.confirm, .confirm])
        withExtendedLifetime([menu, other, raw]) {}
    }

    private static func hashes() {
        let salt = Data(repeating: 9, count: 32)
        let other = Data(repeating: 7, count: 32)
        func hash(_ serial: String?, _ address: String? = nil, salt override: Data? = nil) -> String? {
            ControllerHardwareID.make(serial: serial, bluetoothAddress: address, vendor: 1, product: 2, salt: override ?? salt)
        }
        precondition(hash("fake-hardware") != nil)
        precondition(hash("fake-hardware") == hash(" fake-hardware "))
        precondition(hash("fake-hardware") != hash("fake-hardware", salt: other))
        precondition(hash("fake-hardware")?.contains("fake-hardware") == false)
        precondition(hash("000000") == nil && hash(nil, "FF-FF-FF-FF-FF-FF") == nil)
        precondition(hash(nil, "01:ab:23:cd:45:ef") == hash(nil, "01-AB-23-CD-45-EF"))
        precondition(hash("fake-hardware") != hash(nil, "01:ab:23:cd:45:ef"))
    }

    private static func gameControllerTwins() {
        let gc = FakeSource(), hid = FakeSource()
        let first = NSObject(), second = NSObject(), mirror = NSObject()
        let a = ControllerIdentity(id: ObjectIdentifier(first), name: "Twin", brand: .xbox)
        let b = ControllerIdentity(id: ObjectIdentifier(second), name: "Twin", brand: .xbox)
        let ghost = ControllerIdentity(id: ObjectIdentifier(mirror), name: "Twin", brand: .xbox)
        gc.preferredID = a.id
        gc.statuses[b.id] = .init(batteryLevel: 0.75, isCharging: true, canIdentifyWithRumble: true)
        let service = GameControllerService(gcSource: gc, hidSource: hid)
        var pulses: [String] = [], actions: [GamepadAction] = []
        let subscription = service.controllerButtonPresses.sink { pulses.append($0) }
        defer { subscription.cancel() }
        service.onAction = { actions.append($0) }
        gc.add(a)
        hid.add(ghost, claimed: true)
        precondition(service.connectedControllers.count == 1 && hid.observed.isEmpty)
        hid.remove(ghost)
        gc.add(b)
        let rows = service.connectedControllers
        precondition(rows.count == 2 && rows[0].id != rows[1].id)
        precondition(rows.allSatisfy { $0.identity == .sameModelCannotTellApart })
        precondition(rows[1].status.batteryLevel == 0.75 && rows[1].status.isCharging == true)
        precondition(service.identify(rows[1].id) && gc.identified == [b.id])
        gc.onEvent?(.buttonPressed(b.id))
        gc.onEvent?(.input(a.id, .button(.a, true)))
        gc.onEvent?(.input(a.id, .button(.a, false)))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        precondition(pulses == [rows[1].id, rows[0].id] && actions == [.confirm])
        gc.refresh()
        precondition(service.connectedControllers == rows)
        gc.remove(b)
        precondition(!service.identify(rows[1].id))
        gc.add(b)
        precondition(service.connectedControllers[1].id != rows[1].id)
        withExtendedLifetime([first, second, mirror]) {}
    }

    private static func mixedSourcesAndWake() {
        let gc = FakeSource(), hid = FakeSource()
        let os = NSObject(), hardware = NSObject(), otherModel = NSObject()
        let a = ControllerIdentity(id: ObjectIdentifier(os), name: "Switch", brand: .nintendoSwitch)
        let h = ControllerIdentity(id: ObjectIdentifier(hardware), name: "switch", brand: .nintendoSwitch, stableID: "synthetic")
        let different = ControllerIdentity(id: ObjectIdentifier(otherModel), name: "Other", brand: .generic, supportsNavigation: false)
        let service = GameControllerService(gcSource: gc, hidSource: hid)
        gc.preferredID = a.id
        let gcStatus = ControllerStatus(batteryLevel: 0.75, isCharging: true,
                                        canIdentifyWithLights: true, canIdentifyWithRumble: true)
        gc.statuses[a.id] = gcStatus
        gc.add(a)
        hid.add(h, claimed: true)
        let row = service.connectedControllers[0]
        precondition(service.connectedControllers.count == 1 && row.stableID == "synthetic")
        precondition(row.status == gcStatus, "A unique HID/GC pair must retain GC battery, lights and rumble")
        precondition(service.identify(row.id) && gc.identified == [a.id], "Identify must reach the paired GC device")
        hid.statuses[h.id] = .init(batteryLevel: 0.5, isCharging: false)
        service.refreshControllers()
        precondition(service.connectedControllers[0].status == .init(batteryLevel: 0.5, isCharging: false,
                                                                     canIdentifyWithLights: true,
                                                                     canIdentifyWithRumble: true))
        precondition(hid.observed == [h.id] && hid.selected == nil)
        var pulses: [String] = []
        let subscription = service.controllerButtonPresses.sink { pulses.append($0) }
        defer { subscription.cancel() }
        gc.onEvent?(.input(a.id, .button(.b, true)))
        hid.onEvent?(.buttonPressed(h.id))
        precondition(pulses == [row.id])
        hid.add(different)
        precondition(service.connectedControllers.count == 2 && hid.observed == [h.id, different.id])

        gc.onEvent?(.input(a.id, .button(.menu, true)))
        precondition(service.menuHoldStartedAt != nil && service.holdAction == .menuHold)
        gc.onEvent?(.input(a.id, .button(.view, true)))
        precondition(service.holdAction == .search, "The ring names the hold under the thumb")
        gc.onEvent?(.input(a.id, .button(.view, false)))
        precondition(service.holdAction == nil && service.menuHoldStartedAt == nil)
        gc.onEvent?(.input(a.id, .button(.menu, false)))
        gc.onEvent?(.input(a.id, .button(.menu, true)))
        service.suspendControllers()
        precondition(service.connectedControllers.isEmpty && !service.isGamepadConnected && service.menuHoldStartedAt == nil)
        hid.onEvent?(.buttonPressed(h.id))
        precondition(pulses == [row.id])
        precondition(!service.identify(row.id))
        service.resumeControllers()
        precondition(service.connectedControllers.count == 2 && service.isGamepadConnected)
        guard let resumed = service.connectedControllers.first(where: { $0.stableID == "synthetic" }) else {
            preconditionFailure("The HID identity must return after sleep")
        }
        precondition(resumed.stableID == row.stableID && resumed.id != row.id)
        precondition(resumed.status.canIdentifyWithLights)
        precondition(!service.identify(row.id))
        gc.preferredID = nil
        gc.remove(a)
        precondition(service.activeControllerName == h.name && hid.selected == h.id)
        precondition(service.connectedControllers.first?.status == hid.statuses[h.id])
        precondition(!service.identify(resumed.id) && gc.identified == [a.id])
        hid.onEvent?(.buttonPressed(h.id))
        precondition(pulses.last == resumed.id)
        withExtendedLifetime([os, hardware, otherModel]) {}
    }

    private static func dualSourceTwins() {
        let gc = FakeSource(), hid = FakeSource()
        let objects = (0..<4).map { _ in NSObject() }
        let pads = objects.enumerated().map { index, object in
            ControllerIdentity(id: ObjectIdentifier(object), name: "Twin", brand: .playstation,
                               stableID: index < 2 ? nil : "unique-\(index)")
        }
        let service = GameControllerService(gcSource: gc, hidSource: hid)
        gc.preferredID = pads[0].id
        for pad in pads.prefix(2) { gc.add(pad) }
        for pad in pads.suffix(2).reversed() { hid.add(pad, claimed: true) }
        let rows = service.connectedControllers
        precondition(rows.count == 2 && Set(rows.compactMap(\.stableID)) == ["unique-2", "unique-3"])
        precondition(rows[0].id != rows[1].id)
        precondition(!service.identify(rows[0].id) && gc.identified.isEmpty)
        withExtendedLifetime(objects) {}
    }

    private static func ambiguousPairStaysUnpaired(twinOnHID: Bool) {
        let gc = FakeSource(), hid = FakeSource()
        let os = NSObject(), hardware = NSObject(), twin = NSObject()
        let a = ControllerIdentity(id: ObjectIdentifier(os), name: "Twin", brand: .xbox)
        let h = ControllerIdentity(id: ObjectIdentifier(hardware), name: "Twin", brand: .xbox, stableID: "hardware")
        let b = ControllerIdentity(id: ObjectIdentifier(twin), name: "Twin", brand: .xbox)
        gc.statuses[a.id] = .init(batteryLevel: 0.9, isCharging: true, canIdentifyWithRumble: true)
        let service = GameControllerService(gcSource: gc, hidSource: hid)
        gc.add(a)
        hid.add(h, claimed: true)
        precondition(service.connectedControllers.first?.status == gc.statuses[a.id])

        func expectNoTransfer() {
            guard let row = service.connectedControllers.first(where: { $0.stableID == "hardware" }) else {
                preconditionFailure("The HID identity must stay visible")
            }
            precondition(row.status == .init() && !service.identify(row.id) && gc.identified.isEmpty,
                         "A same-model twin forbids borrowing GC status and output for the rest of the session")
        }

        // Even a HID twin that macOS does not claim makes the model ambiguous.
        let twinSource = twinOnHID ? hid : gc
        twinSource.add(b)
        expectNoTransfer()
        twinSource.remove(b)
        expectNoTransfer()
        service.suspendControllers()
        service.resumeControllers()
        expectNoTransfer()
        withExtendedLifetime([os, hardware, twin]) {}
    }

    private static func repeatedHardwareID() {
        let first = NSObject(), second = NSObject()
        let a = ControllerIdentity(id: ObjectIdentifier(first), name: "Twin", brand: .xbox, stableID: "collision")
        let b = ControllerIdentity(id: ObjectIdentifier(second), name: "Twin", brand: .xbox, stableID: "collision")
        var roster = ControllerRoster()
        for pad in [a, b] { roster.connect(pad, isHID: true, claimedByGC: false) }
        precondition(roster.snapshot(roster.visible) { _ in .init() }.allSatisfy { $0.stableID == nil })
        roster.disconnect(b.id)
        precondition(roster.snapshot(roster.visible) { _ in .init() }.first?.stableID == nil)
        roster.suspend()
        roster.connect(b, isHID: true, claimedByGC: false)
        precondition(roster.snapshot(roster.visible) { _ in .init() }.first?.identity == .sameModelCannotTellApart)
        withExtendedLifetime([first, second]) {}
    }
}
