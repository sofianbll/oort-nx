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
        hashes()
        gameControllerTwins()
        mixedSourcesAndWake()
        dualSourceTwins()
        repeatedHardwareID()
        print("Controller identity: hash privacy, twins, deduplication, activity, output routing, sleep and hot plug passed")
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
        gc.add(a)
        hid.add(h, claimed: true)
        let row = service.connectedControllers[0]
        precondition(service.connectedControllers.count == 1 && row.stableID == "synthetic")
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
        precondition(service.menuHoldStartedAt != nil)
        service.suspendControllers()
        precondition(service.connectedControllers.isEmpty && !service.isGamepadConnected && service.menuHoldStartedAt == nil)
        hid.onEvent?(.buttonPressed(h.id))
        precondition(pulses == [row.id])
        precondition(!service.identify(row.id))
        service.resumeControllers()
        precondition(service.connectedControllers.count == 2 && service.isGamepadConnected)
        let resumed = service.connectedControllers.first { $0.stableID == "synthetic" }
        precondition(resumed?.stableID == row.stableID && resumed?.id != row.id)
        precondition(!service.identify(row.id))
        gc.preferredID = nil
        gc.remove(a)
        precondition(service.activeControllerName == h.name && hid.selected == h.id)
        hid.onEvent?(.buttonPressed(h.id))
        precondition(pulses.last == resumed?.id)
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
