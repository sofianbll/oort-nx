import Foundation
import NXLibraryCore

struct ControllerIdentity: Equatable {
    let id: ObjectIdentifier
    let name: String?
    let brand: GamepadBrand
    var symbols: [PromptButton: String] = [:]
    var stableID: String? = nil
    var supportsNavigation = true

    var modelKey: String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name.lowercased()
    }
}

struct ControllerStatus: Equatable {
    var batteryLevel: Float?
    var isCharging: Bool?
    var canIdentifyWithLights = false
    var canIdentifyWithRumble = false
}

struct ConnectedController: Identifiable, Equatable {
    let id: String
    let name: String?
    let kind: GamepadBrand
    let modelKey: String?
    let identity: Identity
    let status: ControllerStatus

    enum Identity: Equatable {
        case hardware(String)
        case sameModelCannotTellApart
    }

    var stableID: String? {
        if case let .hardware(id) = identity { return id }
        return nil
    }
}

enum ControllerSourceEvent {
    case connected(ControllerIdentity, claimedByGC: Bool = false)
    case disconnected(ObjectIdentifier)
    case input(ObjectIdentifier, ControllerInputChange)
    case buttonPressed(ObjectIdentifier)
}

/// Sources are started and stopped on the main thread and deliver events there.
protocol ControllerSource: AnyObject {
    var onEvent: ((ControllerSourceEvent) -> Void)? { get set }
    func start()
    func stop()
    func refresh()
    var preferredID: ObjectIdentifier? { get }
    /// Pads the source reads at once: the one that takes over, and only that, is announced here.
    func prefer(_ id: ObjectIdentifier)
    @discardableResult func select(_ id: ObjectIdentifier?) -> Bool
    func observe(_ ids: Set<ObjectIdentifier>)
    func status(_ id: ObjectIdentifier) -> ControllerStatus
    func identify(_ id: ObjectIdentifier) -> Bool
}

extension ControllerSource {
    func refresh() {}
    var preferredID: ObjectIdentifier? { nil }
    func prefer(_ id: ObjectIdentifier) {}
    func select(_ id: ObjectIdentifier?) -> Bool { false }
    func observe(_ ids: Set<ObjectIdentifier>) {}
    func status(_ id: ObjectIdentifier) -> ControllerStatus { .init() }
    func identify(_ id: ObjectIdentifier) -> Bool { false }
}
