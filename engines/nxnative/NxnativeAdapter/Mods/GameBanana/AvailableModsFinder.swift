import Foundation
import NXLibraryCore

/// A GameBanana mod with at least one installable RomFS or ExeFS archive for this game.
public struct AvailableMod: Equatable, Identifiable, Sendable {
    public let id: Int
    /// Position in GameBanana's result order, before compatibility filtering.
    public let rank: Int
    public let name: String
    public let author: String
    public let avatarURL: URL?
    public let images: [URL]
    public let thumbnailURL: URL?
    public let version: String
    public let updated: Date
    public let pageURL: URL
    public let description: String
    public let likes: Int
    public let downloads: Int
    /// The files that work, newest first.
    public let files: [GameBananaFile]
    /// GameBanana's root category for the mod in its game ("Skins", "Maps"…); empty when unknown.
    public let category: String
    public let added: Date?
    /// The author's requirements worth showing (game versions, other mods); never a loader, which hides the mod.
    public let requirements: [GameBananaRequirement]

    public init(id: Int, rank: Int, name: String, author: String, avatarURL: URL?, images: [URL], thumbnailURL: URL?,
                version: String, updated: Date, pageURL: URL, description: String, likes: Int, downloads: Int,
                files: [GameBananaFile], category: String = "", added: Date? = nil,
                requirements: [GameBananaRequirement] = []) {
        self.id = id
        self.rank = rank
        self.name = name
        self.author = author
        self.avatarURL = avatarURL
        self.images = images
        self.thumbnailURL = thumbnailURL
        self.version = version
        self.updated = updated
        self.pageURL = pageURL
        self.description = description
        self.likes = likes
        self.downloads = downloads
        self.files = files
        self.category = category
        self.added = added
        self.requirements = requirements
    }
}

/// Reads a game's mods page by page (most downloaded first) and yields the ones that work, checking each mod's
/// profile and the listing of each of its files. Stops at `want` mods, after `maxScanned` mods, or at the list's end.
/// Hidden mods (obsolete, content-rated, private…) are skipped before their profile is fetched where the index
/// already says so. A mod or file GameBanana cannot describe is skipped; no connection ends the stream.
public struct AvailableModsFinder: Sendable {
    public let client: GameBananaClient
    public let titleID: String
    public let want: Int
    public let maxScanned: Int
    public let perPage: Int
    /// GameBanana mods the player installed for this game: each one the list did not give (left out while an update
    /// waits for approval, or past `want`) is read from its own page at the end, so it never vanishes from the band.
    public let installed: [Int]

    public init(client: GameBananaClient, titleID: String, want: Int = 12, maxScanned: Int = 60, perPage: Int = 20,
                installed: [Int] = []) {
        self.client = client
        self.titleID = titleID
        self.want = want
        self.maxScanned = maxScanned
        self.perPage = perPage
        self.installed = installed
    }

    public func stream(gameID: Int) -> AsyncThrowingStream<AvailableMod, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await load(gameID: gameID) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Yields the popular mods and installed entries; returns whether raising `want` can show more.
    func load(gameID: Int, yield: @Sendable (AvailableMod) async -> Void) async throws -> Bool {
        var shown: Set<Int> = []
        let (rank, hasMore) = try await scan(gameID: gameID) { mod in
            shown.insert(mod.id)
            await yield(mod)
        }
        for (offset, id) in installed.enumerated() where !shown.contains(id) && !Task.isCancelled {
            if let mod = try await check(GameBananaModSummary(id: id, name: ""), rank: rank + offset) {
                shown.insert(id)
                await yield(mod)
            }
        }
        return hasMore
    }

    /// The list, most downloaded first; returns the rank after the last mod it read and whether more may remain.
    private func scan(gameID: Int, yield: (AvailableMod) async -> Void) async throws -> (Int, Bool) {
        var found = 0, scanned = 0, page = 1
        var seen: Set<Int> = []
        while found < want, scanned < maxScanned, !Task.isCancelled {
            let result = try await client.modPage(gameID: gameID, page: page, perPage: perPage)
            let batch = Array(result.records.prefix(maxScanned - scanned))
            let start = scanned
            scanned += batch.count
            let confirmed = try await checks(batch, start: start, seen: &seen)
            let remaining = want - found
            for mod in confirmed.prefix(remaining) {
                await yield(mod)
                found += 1
            }
            let complete = result.isComplete || batch.isEmpty
            if found == want {
                return (scanned, confirmed.count > remaining || (!complete && scanned < maxScanned))
            }
            if complete { break }
            page += 1
        }
        return (scanned, false)
    }

    /// A linked mod must belong to this game, even if its archive would otherwise look compatible.
    public func search(_ query: String, gameID: Int) async throws -> [AvailableMod] {
        if let id = GameBananaAPI.modID(from: query) {
            let mod = try await check(GameBananaModSummary(id: id, name: ""), rank: 0, gameID: gameID)
            return mod.map { [$0] } ?? []
        }
        // shortcut: the first best-match page only; add search paging if narrower queries aren't enough.
        let records = try await client.searchMods(gameID: gameID, query: query)
        var seen: Set<Int> = []
        return try await checks(Array(records.prefix(maxScanned)), seen: &seen, gameID: gameID)
    }

    private func checks(_ batch: [GameBananaModSummary], start: Int = 0, seen: inout Set<Int>,
                        gameID: Int? = nil) async throws -> [AvailableMod] {
        try await withThrowingTaskGroup(of: AvailableMod?.self) { group in
            for (offset, summary) in batch.enumerated() where ModSupport.isVisible(summary) && seen.insert(summary.id).inserted {
                group.addTask { try await check(summary, rank: start + offset, gameID: gameID) }
            }
            var confirmed: [AvailableMod] = []
            for try await mod in group { if let mod { confirmed.append(mod) } }
            return confirmed.sorted { $0.rank < $1.rank }
        }
    }

    private func check(_ summary: GameBananaModSummary, rank: Int, gameID: Int? = nil) async throws -> AvailableMod? {
        try Task.checkCancellation()
        let profile: GameBananaModProfile
        do { profile = try await client.profile(modID: summary.id) } catch GameBananaError.unavailable { return nil }
        guard profile.id == summary.id else { return nil }
        if let gameID, profile.gameID != gameID { return nil }
        guard ModSupport.isVisible(profile) else { return nil }
        var files: [GameBananaFile] = []
        for file in profile.files {
            try Task.checkCancellation()
            do {
                let paths = try await client.archivePaths(fileID: file.id)
                if (try? ModSupport.layout(in: paths, titleID: titleID)) != nil { files.append(file) }
            } catch GameBananaError.unavailable {
                continue
            }
        }
        guard !files.isEmpty else { return nil }
        let images = profile.images.isEmpty ? summary.images : profile.images
        return AvailableMod(
            id: profile.id, rank: rank, name: profile.name.isEmpty ? summary.name : profile.name,
            author: profile.submitter.name.isEmpty ? summary.submitter.name : profile.submitter.name,
            avatarURL: profile.submitter.avatarURL ?? summary.submitter.avatarURL,
            images: Array(images.compactMap(\.url530).prefix(8)),
            thumbnailURL: images.first.flatMap { $0.url220 ?? $0.url530 },
            version: profile.version.isEmpty ? summary.version : profile.version,
            updated: profile.dateUpdated ?? profile.dateAdded ?? summary.dateUpdated ?? summary.dateAdded ?? Date(timeIntervalSince1970: 0),
            pageURL: profile.profileURL ?? summary.profileURL ?? URL(string: "https://gamebanana.com/mods/\(profile.id)")!,
            description: GameBananaAPI.plainText(fromHTML: profile.text),
            likes: max(profile.likes, summary.likes), downloads: profile.downloads,
            files: files.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) },
            category: summary.rootCategory, added: profile.dateAdded ?? summary.dateAdded,
            requirements: ModRequirements.shown(profile.requirements))
    }
}

/// Whether an installed GameBanana mod has a newer file: only when the installed file is gone from the mod and a
/// working file was added after the install. A badge only; updating is a reinstall.
public enum ModUpdateCheck {
    public static func update(for record: ModRecord, in mod: AvailableMod) -> GameBananaFile? {
        guard let installed = record.gameBananaFileID, !mod.files.contains(where: { $0.id == installed }) else { return nil }
        let newer = mod.files.filter { file in
            guard let installedAt = record.installedAt else { return true }
            return (file.dateAdded ?? .distantPast) > installedAt
        }
        return newer.max { ($0.dateAdded ?? .distantPast) < ($1.dateAdded ?? .distantPast) }
    }
}
