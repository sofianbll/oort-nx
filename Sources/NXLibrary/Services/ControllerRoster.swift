import Foundation

/// Separate from menu arbitration: this roster never decides which pad navigates.
struct ControllerRoster {
    struct Entry {
        let connectionID = UUID().uuidString
        var controller: ControllerIdentity
        var isHID: Bool
        var claimedByGC: Bool
    }

    private(set) var entries: [Entry] = []
    private var ambiguousHardwareIDs: Set<String> = []

    mutating func connect(_ controller: ControllerIdentity, isHID: Bool, claimedByGC: Bool) {
        if let index = entries.firstIndex(where: { $0.controller.id == controller.id }) {
            entries[index].controller = controller
        } else {
            entries.append(Entry(controller: controller, isHID: isHID, claimedByGC: claimedByGC))
        }
        if let id = controller.stableID, entries.lazy.filter({ $0.controller.stableID == id }).dropFirst().first != nil {
            ambiguousHardwareIDs.insert(id)
        }
    }

    mutating func disconnect(_ id: ObjectIdentifier) {
        entries.removeAll { $0.controller.id == id }
    }

    mutating func suspend() { entries.removeAll() }

    var visible: [Entry] {
        let named = entries.compactMap { entry in entry.controller.modelKey.map { ($0, entry) } }
        var hidden: Set<ObjectIdentifier> = []
        for group in Dictionary(grouping: named, by: { $0.0 }).values {
            let gc = group.map(\.1).filter { !$0.isHID }
            let hid = group.map(\.1).filter(\.claimedByGC)
            // shortcut: GameController has no public HID instance identifier. Collapse only
            // a complete same-model group and never transfer an identity or output to a guessed twin.
            guard !gc.isEmpty, gc.count == hid.count else { continue }
            let keepHID = hid.contains { $0.controller.stableID.map { !ambiguousHardwareIDs.contains($0) } ?? false }
            hidden.formUnion((keepHID ? gc : hid).map(\.controller.id))
        }
        return entries.filter { !hidden.contains($0.controller.id) }
    }

    func snapshot(_ visible: [Entry], status: (Entry) -> ControllerStatus) -> [ConnectedController] {
        return visible.map { entry in
            let pad = entry.controller
            let strong = pad.stableID.flatMap { ambiguousHardwareIDs.contains($0) ? nil : $0 }
            return ConnectedController(id: entry.connectionID, name: pad.name, kind: pad.brand, modelKey: pad.modelKey,
                                       identity: strong.map(ConnectedController.Identity.hardware) ?? .sameModelCannotTellApart,
                                       status: status(entry))
        }
    }
}
