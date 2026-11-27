import Foundation

/// The last searches that led to a game, for one profile and on this Mac only.
public struct RecentSearches {
    public static let limit = 4
    static let storageKey = "NXLibrary_RecentSearches"

    private let defaults: UserDefaults
    private let profile: String

    public init(defaults: UserDefaults, profile: UUID?) {
        self.defaults = defaults
        self.profile = profile?.uuidString ?? "default"
    }

    public var list: [String] { Array((stored[profile] ?? []).prefix(Self.limit)) }

    /// The newest first; the same words, whatever their case or accents, are kept once.
    public func record(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 64 else { return }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        save([query] + list.filter { $0.compare(query, options: options) != .orderedSame })
    }

    public func clear() { save([]) }

    private var stored: [String: [String]] { defaults.dictionary(forKey: Self.storageKey) as? [String: [String]] ?? [:] }

    private func save(_ queries: [String]) {
        var all = stored
        all[profile] = queries.isEmpty ? nil : Array(queries.prefix(Self.limit))
        if all.isEmpty { defaults.removeObject(forKey: Self.storageKey) } else { defaults.set(all, forKey: Self.storageKey) }
    }
}
