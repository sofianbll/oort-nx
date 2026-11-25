import Foundation

/// One writer per URL. The owner supplies its AppData path and serializes saves off the main thread.
public struct PlayerPlanStore: Sendable {
    public enum InvalidDocument: Error, Equatable {
        case unsupportedVersion(Int), invalidSlotKey(String), commitUncertain
    }

    let url: URL

    public init(url: URL) { self.url = url }

    struct Document: Codable {
        let version: Int
        let mode: PlayerControllerMode
        let mergePlayer: Int?
        let slots: [String: PlayerSlot]

        func plan() throws -> PlayerPlan {
            guard version == 1 else { throw InvalidDocument.unsupportedVersion(version) }
            var plan = PlayerPlan(mode: mode)
            try plan.setMergePlayer(mergePlayer)
            for (key, slot) in slots {
                guard let number = Int(key), String(number) == key else { throw InvalidDocument.invalidSlotKey(key) }
                try plan.set(slot, at: number)
            }
            return plan
        }
    }
}

extension PlayerPlan: Codable {
    public init(from decoder: Decoder) throws { self = try PlayerPlanStore.Document(from: decoder).plan() }

    public func encode(to encoder: Encoder) throws {
        let slots = Dictionary(uniqueKeysWithValues: self.slots.map { (String($0.key), $0.value) })
        try PlayerPlanStore.Document(version: 1, mode: mode, mergePlayer: mergePlayer, slots: slots).encode(to: encoder)
    }
}
