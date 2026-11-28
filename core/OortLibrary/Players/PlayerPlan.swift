import Foundation

public enum PlayerControllerMode: String, Codable, CaseIterable, Sendable {
    case inOrder, pressToJoin, merge
}

public enum PlayerProfileAccess: Equatable {
    case guest, missing, locked, ready(LocalProfile)
}

public struct PlayerSlot: Codable, Equatable, Sendable {
    public var profileID: UUID?
    public var controller: RememberedPlayerController?

    public init(profileID: UUID? = nil, controller: RememberedPlayerController? = nil) {
        self.profileID = profileID
        self.controller = controller
    }

    public func profileAccess(in profiles: [LocalProfile], unlockedProfileIDs: Set<UUID> = []) -> PlayerProfileAccess {
        guard let profileID else { return .guest }
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return .missing }
        guard !profile.isLocked || unlockedProfileIDs.contains(profileID) else { return .locked }
        return .ready(profile)
    }
}

public struct PlayerPlan: Equatable, Sendable {
    public enum InvalidSlot: Error, Equatable { case outOfRange(Int) }
    public static let maximumPlayers = 8
    public var mode: PlayerControllerMode
    public private(set) var mergePlayer: Int?
    public var mergeTarget: Int { mergePlayer ?? 1 }
    public private(set) var slots: [Int: PlayerSlot] = [:]

    public init(mode: PlayerControllerMode = .pressToJoin) { self.mode = mode }

    public func slot(_ number: Int) -> PlayerSlot? { slots[number] }

    public mutating func setMergePlayer(_ number: Int?) throws {
        if let number, !(1...Self.maximumPlayers).contains(number) { throw InvalidSlot.outOfRange(number) }
        mergePlayer = number == 1 ? nil : number
    }

    public mutating func set(_ slot: PlayerSlot, at number: Int) throws {
        guard (1...Self.maximumPlayers).contains(number) else { throw InvalidSlot.outOfRange(number) }
        slots[number] = slot
    }

    public mutating func remove(at number: Int) { slots[number] = nil }
}
