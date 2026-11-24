import Foundation

public struct PlayerLaunchCapabilities: Equatable, Sendable {
    public let pressToJoin: Bool
    public let merge: Bool
    public let nickname: Bool

    public init(pressToJoin: Bool = false, merge: Bool = false, nickname: Bool = false) {
        self.pressToJoin = pressToJoin
        self.merge = merge
        self.nickname = nickname
    }
}

public enum PlayerLaunchNetworkMode: Equatable, Sendable {
    case offline, local, nextendo, automatic
}

public enum PlayerLaunchEnvironment {
    public static let pressToJoinKey = "DM_PAD_PRESS_TO_JOIN"
    public static let mergeKey = "DM_PAD_MERGE"
    public static let nicknameKey = "DM_NICK"

    public static func values(plan: PlayerPlan?, capabilities: PlayerLaunchCapabilities,
                              networkMode: PlayerLaunchNetworkMode, envFileKeys: Set<String>,
                              profiles: [LocalProfile] = [], unlockedProfileIDs: Set<UUID> = []) -> [String: String] {
        guard let plan else { return [:] }
        var values: [String: String] = [:]
        if envFileKeys.isDisjoint(with: [pressToJoinKey, mergeKey]) {
            switch plan.mode {
            case .pressToJoin where capabilities.pressToJoin: values[pressToJoinKey] = "1"
            case .merge where capabilities.merge: values[mergeKey] = "1"
            default: break
            }
        }
        if capabilities.nickname, networkMode == .offline || networkMode == .local,
           !envFileKeys.contains(nicknameKey),
           case let .ready(profile)? = plan.slot(1)?.profileAccess(in: profiles, unlockedProfileIDs: unlockedProfileIDs),
           !profile.name.utf8.contains(0) {
            var name = ""
            for character in profile.name {
                guard name.utf8.count + String(character).utf8.count <= 32 else { break }
                name.append(character)
            }
            if !name.isEmpty { values[nicknameKey] = name }
        }
        return values
    }
}
