import Foundation

public struct GameDetailPresentation: Equatable {
    public let title: String
    /// "Nintendo Switch 2" for a Switch 2 title, else "Nintendo Switch".
    public let console: String
    public let eyebrow: String
    public let description: String
    public let descriptionIsEnglishFallback: Bool
    public let descriptionLanguageNote: String?
    /// The store's word on the description's language ("en", "it"), "custom" for the player's own choice, or nil when
    /// the store does not say (Steam). `WikipediaDescriptions.wanted` reads it with the text.
    public let descriptionLanguage: String?
    /// The store's answer in the app language is final (`NintendoStoreMetadata.languageResolved`); until then the
    /// page shows the old text and Wikipedia is not asked, so the text changes once, not twice.
    public let descriptionSettled: Bool
    /// A short store blurb can coexist with a longer description from another source.
    public let descriptionExcerpt: String?
    public let descriptionIsExcerpt: Bool
    public let descriptionSource: String?
    public let genres: [String]
    public let released: String?
    public let developerLine: String?
    public let thisWeek: String
    public let rank: String?
    public let publisher: String?
    public let releaseYear: String?
    public let playtime: String
    public let lastPlayed: String
    public let version: String
    public let size: String
    public let toolchainVerified: Bool
    public let toolchainNote: String?
    public let canPlay: Bool
    public let canRebuild: Bool
    public let sourcesDetached: Bool
    public let hasBaseSource: Bool
    public let storeURL: URL?
    public let hltbURL: URL?
    public let appPath: String
    public let savePath: String

    package static let shortStoreDescriptionLimit = 200

    /// The same text and credits feed Details and Spotlight, including the collapsed view.
    package func aboutDescription(wikipedia: WikipediaDescription?, language: AppLanguage) -> GameAboutDescription {
        let excerpt = descriptionExcerpt
        let sameLanguage = descriptionLanguage == String(language.rawValue.prefix(2))
        let short = excerpt.map { $0.count < Self.shortStoreDescriptionLimit } == true
        let hasLocalLongText = sameLanguage && !descriptionIsExcerpt && description.count >= Self.shortStoreDescriptionLimit
        let wiki = short && hasLocalLongText ? nil : wikipedia
        let full = wiki?.text ?? description
        if let excerpt, short, wiki != nil || sameLanguage, full.count > excerpt.count {
            let text = full.hasPrefix(excerpt) ? full : excerpt + " " + full
            return .init(text: text, sources: ["Nintendo Europe", wiki == nil ? descriptionSource : nil].compactMap { $0 },
                         wikipediaPage: wiki?.pageURL)
        }
        return .init(text: full, preview: excerpt == full ? nil : excerpt,
                     sources: [wiki == nil ? descriptionSource : nil].compactMap { $0 },
                     languageNote: wiki == nil ? descriptionLanguageNote : nil, wikipediaPage: wiki?.pageURL)
    }

    /// Every value of the page, for a source's own entry (`GameDetailPresentation+Porting.swift`).
    package init(title: String, console: String, eyebrow: String, description: String,
                 descriptionIsEnglishFallback: Bool, descriptionLanguageNote: String?, descriptionLanguage: String?,
                 descriptionSettled: Bool, descriptionExcerpt: String? = nil, descriptionIsExcerpt: Bool = false,
                 descriptionSource: String? = nil, genres: [String], released: String?, developerLine: String?,
                 thisWeek: String, rank: String?, publisher: String?, releaseYear: String?, playtime: String,
                 lastPlayed: String, version: String, size: String,
                 toolchainVerified: Bool, toolchainNote: String?, canPlay: Bool, canRebuild: Bool,
                 sourcesDetached: Bool, hasBaseSource: Bool, storeURL: URL?, hltbURL: URL?, appPath: String,
                 savePath: String) {
        self.title = title
        self.console = console
        self.eyebrow = eyebrow
        self.description = description
        self.descriptionIsEnglishFallback = descriptionIsEnglishFallback
        self.descriptionLanguageNote = descriptionLanguageNote
        self.descriptionLanguage = descriptionLanguage
        self.descriptionSettled = descriptionSettled
        self.descriptionExcerpt = descriptionExcerpt
        self.descriptionIsExcerpt = descriptionIsExcerpt
        self.descriptionSource = descriptionSource
        self.genres = genres
        self.released = released
        self.developerLine = developerLine
        self.thisWeek = thisWeek
        self.rank = rank
        self.publisher = publisher
        self.releaseYear = releaseYear
        self.playtime = playtime
        self.lastPlayed = lastPlayed
        self.version = version
        self.size = size
        self.toolchainVerified = toolchainVerified
        self.toolchainNote = toolchainNote
        self.canPlay = canPlay
        self.canRebuild = canRebuild
        self.sourcesDetached = sourcesDetached
        self.hasBaseSource = hasBaseSource
        self.storeURL = storeURL
        self.hltbURL = hltbURL
        self.appPath = appPath
        self.savePath = savePath
    }

    package static func released(_ raw: String?, locale: Locale) -> String? {
        // Release dates are timezone-neutral: parse and format in UTC.
        guard let raw else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(raw.prefix(10))) else { return nil }
        let out = DateFormatter()
        out.locale = locale
        out.timeZone = TimeZone(identifier: "UTC")
        out.dateStyle = .short
        out.timeStyle = .none
        return out.string(from: date)
    }

    /// "#2 of 5" among the visible games with play time, whatever their source.
    package static func rank(id: UUID, name: String, total: TimeInterval, others: [(id: UUID, name: String)],
                     playtimes: [UUID: TimeInterval]) -> String? {
        guard total > 0 else { return nil }
        var entries: [(id: UUID, name: String, time: TimeInterval)] = [(id, name, total)]
        for other in others where other.id != id {
            if let t = playtimes[other.id], t > 0 { entries.append((other.id, other.name, t)) }
        }
        let game = (id: id, name: name)
        entries.sort { a, b in
            if a.time != b.time { return a.time > b.time }
            let c = a.name.localizedCaseInsensitiveCompare(b.name)
            return c != .orderedSame ? c == .orderedAscending : a.id.uuidString < b.id.uuidString
        }
        let position = (entries.firstIndex { $0.id == game.id } ?? 0) + 1
        return "#\(position) of \(entries.count)"
    }

    package static func eyebrow(from name: String) -> String {
        guard !name.isEmpty else { return "" }
        let separators = [":", "™", " – "]
        for separator in separators {
            if let range = name.range(of: separator) {
                let prefix = name[..<range.lowerBound]
                    .replacingOccurrences(of: "™", with: "")
                    .replacingOccurrences(of: "®", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !prefix.isEmpty, prefix != name { return prefix }
            }
        }
        return ""
    }

    package static func hltbURL(for name: String) -> URL? {
        var components = URLComponents(string: "https://howlongtobeat.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: name)]
        return components?.url
    }
}

package struct GameAboutDescription {
    package let text: String
    package var preview: String?
    package let sources: [String]
    package var languageNote: String?
    package var wikipediaPage: URL?

    package func note(showingPreview: Bool) -> String? {
        let credits = showingPreview ? ["Nintendo Europe"] : sources
        let note = (credits.map { L10n.text($0) } + (showingPreview ? [] : [languageNote].compactMap { $0 }))
            .joined(separator: " · ")
        return note.isEmpty ? nil : note
    }
}
