import Foundation
import Combine

public final class PlaySessionStore: ObservableObject, PlayHistory {
    /// Recent sessions, at most `maxSessions` (running sessions are never dropped).
    @Published private var history: [PlaySession] = []
    @Published public var profileID: UUID?
    public var sessions: [PlaySession] { history.filter { $0.profileID == profileID } }
    public func hasScopedSessions(for gameIDs: Set<UUID>) -> Bool {
        history.contains { $0.profileID != nil && gameIDs.contains($0.gameID) }
            || archive.contains { owner, totals in owner != nil && totals.keys.contains(where: gameIDs.contains) }
    }
    /// Play time and last start of sessions trimmed from `sessions`, per game,
    /// so totals and last-played survive trimming.
    @Published private var archive: [UUID?: [UUID: CarriedPlaytime]] = [:]
    public var carried: [UUID: CarriedPlaytime] { archive[profileID] ?? [:] }
    /// Another launcher's own total for a game (Steam's), with when it was seen. Not persisted here.
    @Published private var legacyExternal: [UUID: ExternalPlaytime] = [:]
    public var external: [UUID: ExternalPlaytime] { profileID == nil ? legacyExternal : [:] }
    /// When each game's external value was seen, kept while its total is hidden (source off, another
    /// account, launch), so trimming still keeps the part after it.
    public private(set) var trimReferences: [UUID: Date] = [:]
    public static let maxSessions = 200
    /// Each game whose session just started (not a duplicate start).
    public let starts = PassthroughSubject<UUID, Never>()
    public private(set) var loadError: String?

    /// Legacy recent sessions, read only when no unified state exists.
    public let fileURL: URL
    /// Per-game carried totals, beside `fileURL` (`play-sessions-totals.json`).
    public var totalsURL: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + "-totals.json")
    }
    var stateURL: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + "-state.json")
    }
    private let fileManager: FileManager
    private let now: () -> Date
    private var historyReadFailed = false
    private var launchOwners: [UUID: UUID?] = [:]

    public init(fileURL: URL = PlaySessionStore.defaultURL(),
                fileManager: FileManager = .default,
                now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
        load()
        historyReadFailed = loadError != nil
    }

    public static func defaultURL() -> URL {
        AppData.supportRoot.appendingPathComponent("play-sessions.json")
    }

    /// A session for a game of any integration. `sourceID` is the source's identity (a Switch title ID, or a
    /// qualified one such as "steam-570", never a made-up Nintendo title ID); `bundleID` is the app that runs it, when
    /// there is one. A restart closes an open session at its last heartbeat. A game found already running when its
    /// owner starts watching is not a new start: `announces: false` keeps it off `starts`.
    @discardableResult
    public func start(gameID: UUID, sourceID: String, bundleID: String? = nil, announces: Bool = true) -> Bool {
        if isRunning(gameID: gameID) { return false }
        let owner = launchOwners.removeValue(forKey: gameID) ?? profileID
        let date = now()
        history.append(PlaySession(gameID: gameID, titleID: sourceID, bundleID: bundleID,
                                   startedAt: date, lastHeartbeatAt: date, profileID: owner))
        trim()
        save()
        if announces && owner == profileID { starts.send(gameID) }
        return true
    }

    /// The profile who pressed Play, even if the app's process is only detected after a profile switch.
    public func expectStart(gameID: UUID) { launchOwners.updateValue(profileID, forKey: gameID) }
    public func abandonStart(gameID: UUID) { launchOwners.removeValue(forKey: gameID) }

    public func heartbeat(for gameID: UUID) {
        guard let index = history.lastIndex(where: { $0.gameID == gameID && $0.isActive }) else { return }
        history[index].lastHeartbeatAt = now()
        save()
    }

    /// Ends the game's running sessions and returns them, ended.
    @discardableResult
    public func end(gameID: UUID) -> [PlaySession] {
        let date = now()
        var ended: [PlaySession] = []
        for index in history.indices where history[index].gameID == gameID && history[index].isActive {
            history[index].endedAt = date
            history[index].lastHeartbeatAt = date
            ended.append(history[index])
        }
        if !ended.isEmpty { save() }
        return ended.filter { $0.profileID == profileID }
    }

    /// Ends the game's running sessions and returns them, ended.
    @discardableResult
    public func end(bundleID: String?, preserving gameIDs: Set<UUID> = []) -> [PlaySession] {
        guard let bundleID else { return [] }
        let date = now()
        var ended: [PlaySession] = []
        for index in history.indices
        where history[index].bundleID == bundleID && history[index].isActive && !gameIDs.contains(history[index].gameID) {
            history[index].endedAt = date
            history[index].lastHeartbeatAt = date
            ended.append(history[index])
        }
        if !ended.isEmpty { save() }
        return ended.filter { $0.profileID == profileID }
    }

    public func reconcile(runningBundleIDs: Set<String>) {
        let date = now()
        var changed = false
        for index in history.indices where history[index].isActive {
            if let bundleID = history[index].bundleID,
               runningBundleIDs.contains(bundleID) {
                history[index].lastHeartbeatAt = date
                changed = true
            } else {
                history[index].endedAt = history[index].lastHeartbeatAt
                changed = true
            }
        }
        if changed { save() }
    }

    /// Sets the external totals; publishes only a change.
    public func setExternal(_ values: [UUID: ExternalPlaytime]) {
        if values != legacyExternal { legacyExternal = values }
    }

    public func setTrimReferences(_ values: [UUID: Date]) { trimReferences = values }

    /// With an external total: that total plus the part of this store's sessions after it was seen
    /// (it already counts what came before), including trimmed sessions' part after that same value.
    /// Without one: carried time plus every session.
    public func totalDuration(for gameID: UUID) -> TimeInterval {
        totalDuration(for: gameID, with: external[gameID])
    }

    /// The total under a given external value (nil: none), whatever is published.
    public func totalDuration(for gameID: UUID, with external: ExternalPlaytime?) -> TimeInterval {
        duration(for: gameID, owner: profileID, external: profileID == nil ? external : nil)
    }

    public func originalDuration(for gameID: UUID, with external: ExternalPlaytime?) -> TimeInterval {
        duration(for: gameID, owner: nil, external: external)
    }

    private func duration(for gameID: UUID, owner: UUID?, external: ExternalPlaytime?) -> TimeInterval {
        let date = now()
        let own = history.filter { $0.gameID == gameID && $0.profileID == owner }
        let folded = archive[owner]?[gameID]
        guard let base = external else {
            return own.reduce(folded?.duration ?? 0) { total, session in
                total + max(0, (session.endedAt ?? date).timeIntervalSince(session.startedAt))
            }
        }
        let trimmed = folded.flatMap { $0.externalSince == base.since ? $0.afterExternal : nil } ?? 0
        return own.reduce(base.duration + trimmed) { total, session in
            let end = min(session.endedAt ?? date, date)
            return total + max(0, end.timeIntervalSince(max(session.startedAt, base.since)))
        }
    }

    public func lastPlayed(for gameID: UUID) -> Date? {
        let recent = history.lazy.filter { $0.gameID == gameID && $0.profileID == self.profileID }.map(\.startedAt).max()
        return [recent, carried[gameID]?.lastPlayed, external[gameID]?.lastPlayed].compactMap { $0 }.max()
    }

    /// Arcane-recorded activity only, including sessions folded out of the recent file.
    public func profileActivity(at date: Date) -> [UUID: CarriedPlaytime] {
        sessions.reduce(into: carried) { result, session in
            var entry = result[session.gameID] ?? CarriedPlaytime(duration: 0, lastPlayed: session.startedAt)
            entry.duration += max(0, min(session.endedAt ?? date, date).timeIntervalSince(session.startedAt))
            entry.lastPlayed = max(entry.lastPlayed, session.startedAt)
            result[session.gameID] = entry
        }
    }

    public func isRunning(gameID: UUID) -> Bool {
        history.contains { $0.gameID == gameID && $0.isActive }
    }

    /// Drops the oldest ended sessions beyond `maxCount`, folding each into `carried`.
    private func trim(maxCount: Int = PlaySessionStore.maxSessions) {
        let excess = history.count - maxCount
        guard excess > 0 else { return }
        let dropped = history.filter { !$0.isActive }
            .sorted { $0.startedAt < $1.startedAt }
            .prefix(excess)
        guard !dropped.isEmpty else { return }
        for session in dropped {
            var entry = archive[session.profileID]?[session.gameID] ?? CarriedPlaytime(duration: 0, lastPlayed: session.startedAt)
            entry.duration += session.duration ?? 0
            entry.lastPlayed = max(entry.lastPlayed, session.startedAt)
            // The part after an external value was seen is not in that value yet: keep it, tied to that value.
            if session.profileID == nil, let since = legacyExternal[session.gameID]?.since ?? trimReferences[session.gameID] {
                if entry.externalSince != since { entry.externalSince = since; entry.afterExternal = 0 }
                let end = session.endedAt ?? session.lastHeartbeatAt
                entry.afterExternal += max(0, end.timeIntervalSince(max(session.startedAt, since)))
            }
            archive[session.profileID, default: [:]][session.gameID] = entry
        }
        let droppedIDs = Set(dropped.map(\.id))
        history.removeAll { droppedIDs.contains($0.id) }
    }

    private func save() {
        guard !historyReadFailed else { return }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let entries = archive.flatMap { profileID, values in
                values.map { CarriedEntry(gameID: $0.key, playtime: $0.value, profileID: profileID) }
            }.sorted { ($0.profileID?.uuidString ?? "", $0.gameID.uuidString) < ($1.profileID?.uuidString ?? "", $1.gameID.uuidString) }
            try JSONEncoder().encode(SessionHistoryState(sessions: history, totals: entries))
                .write(to: stateURL, options: .atomic)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func load() {
        do {
            let state = try JSONDecoder().decode(SessionHistoryState.self, from: Data(contentsOf: stateURL))
            history = state.sessions
            loadTotals(state.totals)
            return
        } catch CocoaError.fileReadNoSuchFile {
            // Import the older split files below without changing them.
        } catch {
            loadError = error.localizedDescription
            return
        }
        do {
            history = try JSONDecoder().decode([PlaySession].self, from: Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            // New store.
        } catch {
            loadError = error.localizedDescription
        }
        do {
            loadTotals(try JSONDecoder().decode([CarriedEntry].self, from: Data(contentsOf: totalsURL)))
        } catch CocoaError.fileReadNoSuchFile {
            // Nothing was trimmed since carried totals began.
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadTotals(_ entries: [CarriedEntry]) {
        for entry in entries where archive[entry.profileID]?[entry.gameID] == nil {
            archive[entry.profileID, default: [:]][entry.gameID] = entry.playtime
        }
    }
}

/// A game's total as another launcher keeps it, and when Arcane first saw that value.
public struct ExternalPlaytime: Equatable, Sendable {
    public let duration: TimeInterval
    public let lastPlayed: Date?
    public let since: Date

    public init(duration: TimeInterval, lastPlayed: Date?, since: Date) {
        self.duration = duration
        self.lastPlayed = lastPlayed
        self.since = since
    }
}

/// Play time folded out of the recent-session list for one game. `afterExternal` is the part of it after
/// the external value seen at `externalSince` (Steam's), which that value does not count yet.
public struct CarriedPlaytime: Codable, Equatable {
    public var duration: TimeInterval
    public var lastPlayed: Date
    public var externalSince: Date?
    public var afterExternal: TimeInterval

    public init(duration: TimeInterval, lastPlayed: Date, externalSince: Date? = nil, afterExternal: TimeInterval = 0) {
        self.duration = duration
        self.lastPlayed = lastPlayed
        self.externalSince = externalSince
        self.afterExternal = afterExternal
    }

    private enum CodingKeys: String, CodingKey { case duration, lastPlayed, externalSince, afterExternal }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        lastPlayed = try c.decode(Date.self, forKey: .lastPlayed)
        externalSince = try c.decodeIfPresent(Date.self, forKey: .externalSince)
        afterExternal = try c.decodeIfPresent(TimeInterval.self, forKey: .afterExternal) ?? 0
    }
}

struct SessionHistoryState: Codable {
    static let filename = "play-sessions-state.json"
    var sessions: [PlaySession]
    var totals: [CarriedEntry]
}

struct CarriedEntry: Codable {
    var gameID: UUID
    var playtime: CarriedPlaytime
    var profileID: UUID? = nil
}
