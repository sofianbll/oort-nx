import Foundation
import NXLibraryCore

/// What one visit of the assistant has read. The same read shares one answer for a minute, and one process while it runs.
/// Only reads for the screen go through it: `CloudDriveFolders` refuses to write, move or check access with it.
public actor CloudDriveReads {
    private struct Answer {
        let id = UUID()
        let task: Task<CommandResult, Error>
        var readers = 0
        var endedAt: ContinuousClock.Instant?
    }

    private let lifetime: Duration
    private var answers: [[String]: Answer] = [:]

    public init(lifetime: Duration = .seconds(60)) { self.lifetime = lifetime }

    /// Another account, a folder just created or moved, or the player's own Refresh.
    public func clear() {
        // A read still running answers those who wait for it, but nobody else.
        answers = [:]
    }

    static func isRead(_ arguments: [String]) -> Bool {
        switch arguments.first {
        case "lsjson", "listremotes", "about": true
        case "config": ["redacted", "file"].contains(arguments.dropFirst().first)
        default: false
        }
    }

    package func run(_ executable: URL, _ arguments: [String], _ environment: [String: String],
                     using run: @escaping RcloneConfiguration.Run) async throws -> CommandResult {
        guard Self.isRead(arguments) else { throw StorageBackendError.invalidConfiguration }
        try Task.checkCancellation()
        // The arguments name the account's connection, its configuration and the folder.
        let key = [executable.path] + arguments
        if let known = answers[key], let end = known.endedAt, end.duration(to: .now) >= lifetime { answers[key] = nil }
        var answer = answers[key] ?? Answer(task: Task { try await run(executable, arguments, environment) })
        answer.readers += 1
        answers[key] = answer
        let id = answer.id, task = answer.task
        let result = await withTaskCancellationHandler { await task.result } onCancel: {
            Task { await self.leave(key, id) }
        }
        try Task.checkCancellation()
        finish(key, id, kept: (try? result.get())?.status == 0)
        return try result.get()
    }

    /// The last reader gone, nothing needs the process.
    private func leave(_ key: [String], _ id: UUID) {
        guard var answer = answers[key], answer.id == id, answer.endedAt == nil else { return }
        answer.readers -= 1
        if answer.readers > 0 { answers[key] = answer; return }
        answers[key] = nil
        answer.task.cancel()
    }

    private func finish(_ key: [String], _ id: UUID, kept: Bool) {
        guard answers[key]?.id == id else { return }
        // A refusal or an interruption is asked again.
        if kept { if answers[key]?.endedAt == nil { answers[key]?.endedAt = .now } } else { answers[key] = nil }
    }
}
