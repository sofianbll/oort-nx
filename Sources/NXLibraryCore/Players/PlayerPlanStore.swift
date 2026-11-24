import Foundation

/// One writer per URL. The owner supplies its AppData path and serializes saves off the main thread.
public struct PlayerPlanStore: Sendable {
    public enum InvalidDocument: Error, Equatable {
        case unsupportedVersion(Int), invalidSlotKey(String), commitUncertain
    }

    private static let maximumBytes = 1_048_576
    private let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> PlayerPlan? {
        guard let source = try snapshot() else { return nil }
        return try Self.decode(source.data).plan()
    }

    public func save(_ plan: PlayerPlan) throws {
        let source = try snapshot()
        let previous = try source.map { try Self.decode($0.data) }
        let original = try source.map { try JSONDecoder().decode([String: CatalogJSON].self, from: $0.data) } ?? [:]
        var root = original
        var slots: [String: CatalogJSON] = [:]
        for (number, slot) in plan.slots {
            let key = String(number)
            var fields = Self.members(original["slots"]?[key])
            fields["profileID"] = slot.profileID.map { .string($0.uuidString) }
            if let controller = slot.controller {
                var record = previous?.slots[key]?.controller?.id == controller.id ? Self.members(fields["controller"]) : [:]
                record["id"] = .string(controller.id.uuidString)
                record["stableID"] = controller.stableID.map(CatalogJSON.string)
                record["modelKey"] = controller.modelKey.map(CatalogJSON.string)
                fields["controller"] = .object(record)
            } else {
                fields["controller"] = nil
            }
            slots[key] = .object(fields)
        }
        root["slots"] = .object(slots)
        root["mode"] = .string(plan.mode.rawValue)
        root["version"] = .number(1)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let candidate = try encoder.encode(root)
        guard candidate.count <= Self.maximumBytes else { throw InstallationFileReadError.tooLarge }
        _ = try Self.decode(candidate)

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stage = try CatalogPublication.stage(candidate, in: directory)
        defer { try? FileManager.default.removeItem(at: stage) }
        try CatalogPublication.atomic.publish(stage, url, source != nil) {
            try source?.verifyUnchanged()
        }
        do { try CatalogPublication.atomic.syncDirectory(directory) }
        catch { throw InvalidDocument.commitUncertain }
    }

    private func snapshot() throws -> InstallationFileSnapshot? {
        guard url.isFileURL else { throw URLError(.unsupportedURL) }
        do { return try InstallationFileSnapshot.read(at: url, maximumBytes: Self.maximumBytes) }
        catch let error as POSIXError where error.code == .ENOENT {
            _ = try InstallationFileObservation.absent(at: url)
            return nil
        }
    }

    private static func members(_ value: CatalogJSON?) -> [String: CatalogJSON] {
        if case .object(let members)? = value { return members }
        return [:]
    }

    private static func decode(_ bytes: Data) throws -> Document {
        let document = try JSONDecoder().decode(Document.self, from: bytes)
        _ = try document.plan()
        return document
    }

    private struct Document: Decodable {
        let version: Int
        let mode: PlayerControllerMode
        let slots: [String: PlayerSlot]

        func plan() throws -> PlayerPlan {
            guard version == 1 else { throw InvalidDocument.unsupportedVersion(version) }
            var plan = PlayerPlan(mode: mode)
            for (key, slot) in slots {
                guard let number = Int(key), String(number) == key else { throw InvalidDocument.invalidSlotKey(key) }
                try plan.set(slot, at: number)
            }
            return plan
        }
    }
}
