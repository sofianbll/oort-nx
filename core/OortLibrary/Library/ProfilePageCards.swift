import Foundation

public enum ProfilePageCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case recent, achievements, friends, week, mostPlayed, resume, neverPlayed

    public var id: Self { self }
    public var title: String {
        switch self {
        case .recent: "Recently played"
        case .achievements: "Achievements"
        case .friends: "Friends"
        case .week: "Playtime this week"
        case .mostPlayed: "Most played"
        case .resume: "Pick up again"
        case .neverPlayed: "Never played"
        }
    }

    /// Match Selene's “Pick up again” threshold, using only Arcane's recorded activity.
    public func games(in games: [CatalogGame], activity: [UUID: CarriedPlaytime],
                      week: ActivitySummary, now: Date, calendar: Calendar = .current) -> [CatalogGame] {
        let played = games.filter { activity[$0.id] != nil }
        switch self {
        case .recent:
            return played.sorted { activity[$0.id]!.lastPlayed > activity[$1.id]!.lastPlayed }
        case .mostPlayed:
            return played.sorted { activity[$0.id]!.duration > activity[$1.id]!.duration }
        case .resume:
            guard let cutoff = calendar.date(byAdding: .day, value: -45, to: now) else { return [] }
            return played.filter { activity[$0.id]!.duration >= 3600 && activity[$0.id]!.lastPlayed < cutoff }
                .sorted { activity[$0.id]!.duration > activity[$1.id]!.duration }
        case .neverPlayed:
            return games.filter { activity[$0.id] == nil }.sorted {
                if $0.isInstalledForLibrary != $1.isInstalledForLibrary { return $0.isInstalledForLibrary }
                return ($0.libraryModificationDate ?? .distantPast) > ($1.libraryModificationDate ?? .distantPast)
            }
        case .week:
            let byID = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
            return week.topGames.compactMap { byID[$0] }
        case .friends, .achievements:
            return []
        }
    }
}

public struct ProfilePageCards: Codable, Equatable, Sendable {
    private var order = ProfilePageCard.allCases
    private var hidden: Set<ProfilePageCard> = []

    public init() {}

    public var ordered: [ProfilePageCard] {
        var seen = Set<ProfilePageCard>()
        return (order + ProfilePageCard.allCases).filter { seen.insert($0).inserted }
    }

    public func isEnabled(_ card: ProfilePageCard) -> Bool { !hidden.contains(card) }
    public func visible(hasAccount: Bool) -> [ProfilePageCard] {
        ordered.filter { isEnabled($0) && ($0 != .friends || hasAccount) }
    }

    public mutating func toggle(_ card: ProfilePageCard) {
        if hidden.remove(card) == nil { hidden.insert(card) }
    }

    public mutating func move(_ card: ProfilePageCard, by step: Int) {
        var next = ordered
        guard let from = next.firstIndex(of: card), next.indices.contains(from + step) else { return }
        next.remove(at: from)
        next.insert(card, at: from + step)
        order = next
    }

    /// Width in canvas units; the minimum makes long titles legible without a fixed column count.
    public static func columns(width: CGFloat) -> Int {
        let gap = SeleneTokens.Space.large
        let minimum = SeleneTokens.Space.stageGutter * 2 + SeleneTokens.Space.group * 2
        return max(1, Int((max(0, width) + gap) / (minimum + gap)))
    }

    public static func friendsColumnWidth(available: CGFloat) -> CGFloat? {
        let side = SeleneTokens.Space.transferMeasure / 2
        return available >= side * 3 ? side : nil
    }
}
