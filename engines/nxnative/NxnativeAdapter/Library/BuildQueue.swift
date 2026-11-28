import Foundation

/// The owner revalidates the FIFO head against current game and operation state.
package final class BuildQueue<Value> {
    package enum Decision { case start, wait, skip }
    package typealias Entry = (id: UUID, value: Value)
    package private(set) var entries: [Entry] = []
    package var ids: [UUID] { entries.map(\.id) }

    package init() {}

    @discardableResult
    package func enqueue(_ value: Value, id: UUID, activeID: UUID?) -> Bool {
        guard id != activeID, !ids.contains(id) else { return false }
        entries.append((id, value))
        return true
    }

    package func retryFirst(_ entry: Entry) {
        entries.insert(entry, at: 0)
    }

    @discardableResult
    package func cancel(_ id: UUID) -> Bool {
        remove(id) != nil
    }

    package func remove(_ id: UUID) -> Value? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index).value
    }

    package func takeNext(_ decide: (UUID) -> Decision) -> (id: UUID, value: Value, decision: Decision)? {
        guard let first = entries.first else { return nil }
        let decision = decide(first.id)
        guard decision != .wait else { return nil }
        entries.removeFirst()
        return (first.id, first.value, decision)
    }
}

package struct BuildRequest: Equatable, Codable, Sendable {
    package let id: UUID
    package let gameID: UUID
    package let name: String
    package let arguments: [String]
    package let withoutCache: Bool
    package let rebuild: Bool
    package var localSourcesOnly = false
    package var preferLocalCache = false

    package init(gameID: UUID, name: String, arguments: [String] = [], withoutCache: Bool = false,
                 rebuild: Bool = false) {
        id = UUID()
        self.gameID = gameID
        self.name = name
        self.arguments = arguments
        self.withoutCache = withoutCache
        self.rebuild = rebuild
    }

    package init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(UUID.self, forKey: .id)
        gameID = try fields.decode(UUID.self, forKey: .gameID)
        name = try fields.decode(String.self, forKey: .name)
        arguments = try fields.decode([String].self, forKey: .arguments)
        withoutCache = try fields.decode(Bool.self, forKey: .withoutCache)
        rebuild = try fields.decode(Bool.self, forKey: .rebuild)
        localSourcesOnly = try fields.decodeIfPresent(Bool.self, forKey: .localSourcesOnly) ?? false
        preferLocalCache = try fields.decodeIfPresent(Bool.self, forKey: .preferLocalCache) ?? false
        // These are the only one-off overrides produced by PortingFailureReason.
        guard arguments.count <= 1,
              arguments.allSatisfy({ ["--allow-shader-regressions", "--allow-damaged"].contains($0) }) else {
            throw DecodingError.dataCorruptedError(forKey: .arguments, in: fields, debugDescription: "Invalid porting override")
        }
    }

    package static func restoring(_ entries: [Self]) -> [Self] {
        var games = Set<UUID>(), requests = Set<UUID>()
        return entries.compactMap { entry in
            guard !games.contains(entry.gameID), requests.insert(entry.id).inserted else { return nil }
            games.insert(entry.gameID)
            var restored = entry
            restored.localSourcesOnly = true
            return restored
        }
    }

    package func canResumeAutomatically(_ game: PortedGame, fileManager: FileManager = .default) -> Bool {
        game.id == gameID && GameResourceState.sourcesAvailable(for: game, fileManager: fileManager)
            && (!rebuild || (game.url.pathExtension.lowercased() == "app"
                             && fileManager.fileExists(atPath: game.url.path)))
    }
}
