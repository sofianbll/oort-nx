import Foundation

/// Definitions ship with Arcane; a rule names a metric, never a file or an offset.
public struct LocalAchievementPack: Decodable, Sendable {
    public enum Metric: String, Codable, CaseIterable, Sendable {
        case seashells, heartPieces
    }

    public struct Rule: Decodable, Sendable {
        public enum Comparison: String, Decodable, Sendable { case gte }
        let metric: Metric
        let op: Comparison
        let threshold: Int
    }

    public struct Definition: Decodable, Sendable {
        let id: String
        let title: [String: String]
        let description: [String: String]
        let icon: String
        let rule: Rule
    }

    public enum Reader: String, Decodable, Sendable { case linksAwakening }

    public let schemaVersion: Int
    public let titleID: String
    public let gameVersion: String
    public let reader: Reader
    public let achievements: [Definition]

    public static let linksAwakening: Self? = {
        guard let url = L10n.resources()?.url(forResource: "achievements-01006BB00C6F0000", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let pack = try? JSONDecoder().decode(Self.self, from: data),
              pack.schemaVersion == 1, !pack.achievements.isEmpty,
              Set(pack.achievements.map(\.id)).count == pack.achievements.count,
              pack.achievements.allSatisfy({ item in
                  item.rule.threshold > 0 && AppLanguage.allCases.filter { $0 != .automatic }.allSatisfy {
                      item.title[$0.rawValue]?.isEmpty == false && item.description[$0.rawValue]?.isEmpty == false
                  }
              }) else { return nil }
        return pack
    }()

    public func matches(titleID: String?, gameVersion: String?) -> Bool {
        self.titleID == titleID?.uppercased() && self.gameVersion == gameVersion
    }

    public func summary(_ state: LocalAchievementProgress?, language: AppLanguage) -> AchievementSummary {
        AchievementSummary(rows: achievements.map { item in
            let count = state?.counts[item.rule.metric].map { min($0, item.rule.threshold) }
            return AchievementRow(id: item.id,
                name: item.title[language.rawValue] ?? item.title["en"] ?? item.id,
                description: item.description[language.rawValue] ?? item.description["en"] ?? "",
                icon: item.icon, unlockedAt: state?.unlockDates[item.id], percent: nil, isMasked: false,
                progress: count.map { AchievementRow.Progress(current: $0, target: item.rule.threshold) })
        })
    }
}

public struct LocalAchievementProgress: Codable, Sendable {
    public private(set) var counts: [LocalAchievementPack.Metric: Int] = [:]
    public private(set) var unlockDates: [String: Date] = [:]

    public init() {}

    /// Highest confirmed count for each metric; slots are never added together.
    public mutating func record(_ observed: [LocalAchievementPack.Metric: Int], in pack: LocalAchievementPack,
                                at date: Date) -> [String] {
        for (metric, count) in observed { counts[metric] = max(count, counts[metric] ?? 0) }
        return pack.achievements.compactMap { item in
            guard unlockDates[item.id] == nil, let count = counts[item.rule.metric] else { return nil }
            switch item.rule.op {
            case .gte: guard count >= item.rule.threshold else { return nil }
            }
            unlockDates[item.id] = date
            return item.id
        }
    }
}

/// Only Arcane's derived progress is persisted, under its own profile and schema key.
public struct LocalAchievementStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    private func key(_ pack: LocalAchievementPack, profile: UUID) -> String {
        "localAchievements.\(pack.schemaVersion).\(pack.titleID).\(pack.gameVersion).\(profile.uuidString)"
    }

    public func progress(for pack: LocalAchievementPack, profile: UUID) -> LocalAchievementProgress? {
        defaults.data(forKey: key(pack, profile: profile)).flatMap {
            try? JSONDecoder().decode(LocalAchievementProgress.self, from: $0)
        }
    }

    public func record(_ counts: [LocalAchievementPack.Metric: Int], in pack: LocalAchievementPack,
                       profile: UUID, at date: Date) -> [String] {
        var result = progress(for: pack, profile: profile) ?? LocalAchievementProgress()
        let unlocked = result.record(counts, in: pack, at: date)
        guard let data = try? JSONEncoder().encode(result) else { return [] }
        defaults.set(data, forKey: key(pack, profile: profile))
        return unlocked
    }
}
