import Foundation

/// The people and projects Oort NX owes something to, as `design/credits.json` lists them for every system.
/// `scripts/generate_credits.py` copies that file into each app; nothing here is written by hand twice.
public struct Credits: Decodable, Sendable {
    public typealias Words = [String: String]

    public enum System: String, Sendable { case mac, windows, linux, ios, android, site }

    public struct Category: Decodable, Identifiable, Sendable {
        public let id: String
        public let glyph: String
        public let title: Words
    }

    public struct Icon: Decodable, Sendable {
        public let allowed: Bool
        public let asset: String?
    }

    public struct Credit: Decodable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let author: String
        public let role: String
        /// SPDX; nil when the project states none.
        public let license: String?
        public let url: URL
        public let category: String
        public let use: String
        /// A glyph of its own, else its category's.
        public let glyph: String?
        public let systems: [String]
        /// Nil when its picture may not be shown: the category's glyph stands in.
        public let icon: Icon?
        public let includes: [String]?

        /// The picture that may be shown for it, if any.
        public var picture: String? { icon?.allowed == true ? icon?.asset : nil }
    }

    public struct Legal: Decodable, Identifiable, Sendable {
        public let id: String
        public let systems: [String]
        public let text: Words
    }

    public struct Group: Identifiable, Sendable {
        public let category: Category
        public let credits: [Credit]
        public var id: String { category.id }
    }

    /// The cards every system shows first, in this order, whatever it uses of them.
    public let base: [String]
    /// The most columns a grid of cards has.
    public let columns: Int
    public let labels: [String: Words]
    public let categories: [Category]
    public let roles: [String: Words]
    public let legal: [Legal]
    public let credits: [Credit]

    public init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(Credits.self, from: Data(contentsOf: url))
    }

    public var baseGroup: Group? {
        let own = base.compactMap { id in credits.first { $0.id == id } }
        return own.first.flatMap { first in categories.first { $0.id == first.category } }.map { Group(category: $0, credits: own) }
    }

    /// How many columns a group takes where `fitting` fit: the six cards fill a grid, every other group is a list.
    public func columns(for group: Group, fitting: Int) -> Int {
        guard group.credits.map(\.id) == base else { return 1 }
        let fitting = min(max(fitting, 1), columns)
        return base.count % fitting == 0 ? fitting : 1
    }

    /// Every other credit one system shows, in the order of the file; an empty category is left out.
    public func groups(for system: System) -> [Group] {
        categories.compactMap { category in
            let own = credits.filter { $0.category == category.id && $0.systems.contains(system.rawValue) && !base.contains($0.id) }
            return own.isEmpty ? nil : Group(category: category, credits: own)
        }
    }

    public func statements(for system: System, in language: String) -> [String] {
        legal.filter { $0.systems.contains(system.rawValue) }.map { Self.words($0.text, in: language) }
    }

    public func role(of credit: Credit, in language: String) -> String { Self.words(roles[credit.role] ?? [:], in: language) }

    public func label(_ key: String, in language: String) -> String { Self.words(labels[key] ?? [:], in: language) }

    /// Author and licence, the second line of every card. A service has an owner, not a licence.
    public func byline(of credit: Credit, in language: String) -> String {
        let terms = credit.license ?? label(credit.use == "service" ? "online" : "unlisted", in: language)
        return credit.author == credit.name ? terms : "\(credit.author) · \(terms)"
    }

    /// The words in a language such as `pt-BR`, else in the same base language, else in English.
    public static func words(_ words: Words, in language: String) -> String {
        words[language] ?? words.first { $0.key.prefix(2) == language.prefix(2) }?.value ?? words["en"] ?? ""
    }
}
