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
           let name = wireName(profile.name) {
            values[nicknameKey] = name
        }
        return values
    }

    public static func wireName(_ value: String) -> String? {
        guard !value.utf8.contains(0) else { return nil }
        var bytes = 0
        let name = value.prefix { character in
            bytes += String(character).utf8.count
            return bytes <= 32
        }
        return name.isEmpty ? nil : String(name)
    }
}
