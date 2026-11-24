import Foundation
import OSLog
import Darwin

/// The activity queues and history share the profiled, atomic snapshot format.
package final class ActivityQueueFile<Entry: Codable & Sendable>: Sendable {
    private struct DecodedEntry: Decodable {
        let entry: Entry?
        init(from decoder: Decoder) throws { entry = try? Entry(from: decoder) }
    }

    private struct Snapshot: Decodable {
        let version: Int
        let entries: [DecodedEntry]
    }

    private struct WriteSnapshot: Encodable {
        let version = 1
        let entries: [Entry]
    }

    private let file: URL
    private let io = DispatchQueue(label: "local.nxlibrary.activity-queue", qos: .utility)
    private let log = Logger(subsystem: "local.nxlibrary", category: "activity-queue")
    // Only the serial IO queue accesses this flag. Do not erase a file from a newer version
    // or replace an unreadable snapshot with a seemingly valid empty one.
    private let canWrite = OSAllocatedUnfairLock(initialState: true)
    private let reportedSaveFailure = OSAllocatedUnfairLock(initialState: false)

    package init(file: URL) { self.file = file }

    package func load() async -> [Entry] {
        await withCheckedContinuation { continuation in
            io.async {
                do {
                    let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: self.file))
                    if snapshot.version == 1 {
                        continuation.resume(returning: snapshot.entries.compactMap(\.entry))
                        return
                    }
                    self.log.error("Unsupported activity snapshot version")
                    self.canWrite.withLock { $0 = false }
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    // No snapshot has been written in this profile.
                } catch {
                    self.log.error("Could not read the activity snapshot")
                    self.canWrite.withLock { $0 = false }
                }
                continuation.resume(returning: [])
            }
        }
    }

    package func save(_ entries: [Entry], onFailure: (@Sendable () -> Void)? = nil) {
        io.async {
            do {
                try self.write(entries)
            } catch {
                self.log.error("Could not save the activity snapshot")
                if let onFailure, self.reportedSaveFailure.withLock({ reported in
                    defer { reported = true }
                    return !reported
                }) { onFailure() }
            }
        }
    }

    /// Acknowledge publication only after the replacement and its directory entry are synced.
    package func saveDurably(_ entries: [Entry]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            io.async {
                do {
                    try self.write(entries)
                    try Self.synchronize(self.file, flags: O_RDONLY | O_NOFOLLOW)
                    try Self.synchronize(self.file.deletingLastPathComponent(), flags: O_RDONLY | O_DIRECTORY)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func write(_ entries: [Entry]) throws {
        guard canWrite.withLock({ $0 }) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(WriteSnapshot(entries: entries)).write(to: self.file, options: .atomic)
    }

    private static func synchronize(_ url: URL, flags: Int32) throws {
        let descriptor = open(url.path, flags | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    package func flush() async {
        await withCheckedContinuation { continuation in io.async { continuation.resume() } }
    }
}
