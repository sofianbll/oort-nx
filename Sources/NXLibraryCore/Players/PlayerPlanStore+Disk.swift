import Foundation

// Reading and writing the file takes POSIX snapshots and the atomic catalog publication, so this half stays with Darwin.
extension PlayerPlanStore {
    static let maximumBytes = 1_048_576

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
        root["mergePlayer"] = plan.mergePlayer.map { .number(Decimal($0)) }
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

    func snapshot() throws -> InstallationFileSnapshot? {
        guard url.isFileURL else { throw URLError(.unsupportedURL) }
        do { return try InstallationFileSnapshot.read(at: url, maximumBytes: Self.maximumBytes) }
        catch let error as POSIXError where error.code == .ENOENT {
            _ = try InstallationFileObservation.absent(at: url)
            return nil
        }
    }

    static func members(_ value: CatalogJSON?) -> [String: CatalogJSON] {
        if case .object(let members)? = value { return members }
        return [:]
    }

    static func decode(_ bytes: Data) throws -> Document {
        let document = try JSONDecoder().decode(Document.self, from: bytes)
        _ = try document.plan()
        return document
    }
}
