import Foundation

/// One download the player asked for.
public struct ShelfJob: Equatable, Sendable, Codable, Identifiable {
    public enum State: String, Codable, Sendable { case waiting, running, paused, failed, ready }

    public let build: ShelfBuild
    public var state: State
    /// Why it stopped, or what it waits for: a `ShelfError` code.
    public var reason: String?
    /// Bytes to have free, when there was no room.
    public var needed: Int64?
    public var received: Int64

    public var id: String { build.titleID }

    public init(_ build: ShelfBuild) { (self.build, state, received) = (build, .waiting, 0) }
}

/// The downloads in the order they were asked for, kept on the device so that nothing is lost when the app ends. One runs at a time.
public struct ShelfQueue: Sendable {
    public private(set) var jobs: [ShelfJob] = []
    private let file: URL
    private let keepOutOfBackup: @Sendable (URL) throws -> Void

    /// A job that was running when the app ended waits its turn again.
    public init(file: URL, keepOutOfBackup: @escaping @Sendable (URL) throws -> Void) {
        (self.file, self.keepOutOfBackup) = (file, keepOutOfBackup)
        guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([ShelfJob].self, from: data) else { return }
        var seen: Set<String> = []
        jobs = saved.filter { seen.insert($0.id).inserted }
        for index in jobs.indices where jobs[index].state == .running { jobs[index].state = .waiting }
    }

    public subscript(id: String) -> ShelfJob? { jobs.first { $0.id == id } }
    public var next: ShelfJob? { jobs.contains { $0.state == .running } ? nil : jobs.first { $0.state == .waiting } }

    /// Asking again for a title replaces what was asked before.
    public mutating func add(_ build: ShelfBuild) {
        jobs.removeAll { $0.id == build.titleID }
        jobs.append(ShelfJob(build))
        save()
    }

    public mutating func set(_ id: String, _ state: ShelfJob.State, reason: ShelfError? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        (jobs[index].state, jobs[index].reason) = (state, reason?.code)
        if case .noSpace(let needed) = reason, needed > 0 { jobs[index].needed = needed } else { jobs[index].needed = nil }
        save()
    }

    /// Kept in memory only: the files on the device say the rest.
    public mutating func progress(_ id: String, _ received: Int64) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].received = received
    }

    public mutating func remove(_ id: String) {
        jobs.removeAll { $0.id == id }
        save()
    }

    public mutating func removeAll() {
        jobs = []
        try? FileManager.default.removeItem(at: file)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        try? keepOutOfBackup(file)
    }
}

extension ShelfError {
    /// Nothing is wrong with the game or the device: the download waits and tries again by itself.
    public var waits: Bool {
        switch self {
        case .offline, .networkNotAllowed, .interrupted, .server, .busy: true
        default: false
        }
    }
}
