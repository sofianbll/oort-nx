import Foundation

public struct RememberedPlayerController: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let stableID: String?
    public let modelKey: String?

    public init(id: UUID = UUID(), stableID: String? = nil, modelKey: String? = nil) {
        self.id = id
        self.stableID = stableID
        self.modelKey = modelKey
    }
}

public struct ConnectedPlayerController: Equatable, Identifiable, Sendable {
    public let id: String
    public let stableID: String?
    public let modelKey: String?

    public init(id: String, stableID: String? = nil, modelKey: String? = nil) {
        self.id = id
        self.stableID = stableID
        self.modelKey = modelKey
    }
}

public enum PlayerControllerStatus: Equatable, Sendable {
    case inactive, unassigned, disconnected, connected(String), needsConfirmation([String])
}

public struct PlayerControllerResolution: Equatable, Sendable {
    public let slots: [Int: PlayerControllerStatus]
    public let unassignedControllerIDs: [String]
}

extension PlayerPlan {
    public func resolveControllers(_ connected: [ConnectedPlayerController],
                                   confirmed: [Int: String] = [:]) -> PlayerControllerResolution {
        let observations = Dictionary(grouping: connected, by: \.id)
        let active = slots.filter { mode != .merge || $0.key == mergeTarget }
        let liveConfirmations = confirmed.filter { active[$0.key] != nil && observations[$0.value]?.count == 1 }
        let confirmationsPerController = Dictionary(grouping: liveConfirmations.values, by: { $0 })
        var assigned = liveConfirmations.filter { confirmationsPerController[$0.value]?.count == 1 }
        var claimed = Set(assigned.values)

        let allRememberedKeys = slots.values.compactMap { $0.controller?.stableID }.filter { !$0.isEmpty }
        let connectedByKey = Dictionary(grouping: connected.filter { $0.stableID?.isEmpty == false }, by: \.stableID)
        for (number, slot) in active where assigned[number] == nil {
            guard let key = slot.controller?.stableID, !key.isEmpty,
                  allRememberedKeys.filter({ $0 == key }).count == 1,
                  let matches = connectedByKey[key], matches.count == 1,
                  let match = matches.first, observations[match.id]?.count == 1,
                  claimed.insert(match.id).inserted else { continue }
            assigned[number] = match.id
        }

        let unclaimed = connected.filter { !claimed.contains($0.id) }
        let statuses = slots.mapValues { _ in PlayerControllerStatus.inactive }.merging(
            active.reduce(into: [Int: PlayerControllerStatus]()) { result, entry in
                let (number, slot) = entry
                if let id = assigned[number] {
                    result[number] = .connected(id)
                } else if let saved = slot.controller {
                    let candidates = unclaimed.filter { $0.couldBe(saved) }.map(\.id)
                    result[number] = candidates.isEmpty ? .disconnected : .needsConfirmation(Self.unique(candidates))
                } else {
                    result[number] = .unassigned
                }
            }
        ) { _, status in status }
        return .init(slots: statuses, unassignedControllerIDs: Self.unique(unclaimed.map(\.id)))
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

private extension ConnectedPlayerController {
    func couldBe(_ saved: RememberedPlayerController) -> Bool {
        if let stableID, !stableID.isEmpty, let key = saved.stableID, !key.isEmpty {
            return key == stableID
        }
        // A model can suggest candidates but never establishes identity.
        return modelKey?.isEmpty == false && modelKey == saved.modelKey
    }
}
