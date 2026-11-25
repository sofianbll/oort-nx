import CryptoKit
import Foundation
import OortCore

struct DriveReply: Sendable {
    let status: Int
    let headers: [String: String]

    func header(_ name: String) -> String? { headers[name.lowercased()] }
}

protocol DriveTransport: Sendable {
    /// Puts the answer's body in `file`, a new file, and stops as soon as it passes `limit` bytes.
    func send(_ request: URLRequest, to file: URL, limit: Int64) async throws -> DriveReply
    /// It left a request waiting a moment ago: another way is better for now.
    var rests: Bool { get }
}

extension DriveTransport {
    var rests: Bool { false }
}

/// Download tasks with a delegate and nothing else: the only shape a background session accepts, so a foreground session takes the same path.
///
/// In the background the system goes on without the app. An answer that comes after the app was ended is kept in `inbox` under the name of
/// what was asked (never the credential), and the next `send` of the same request takes it; its size, its range and its SHA-256 are checked
/// as if it had just come.
public final class DriveSession: NSObject, DriveTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct Job {
        let file: URL
        let limit: Int64
        let done: CheckedContinuation<DriveReply, any Error>
        var failure: (any Error)?
    }
    private struct Kept: Codable { let status: Int, headers: [String: String] }
    /// What a task is for, in the name the system gives back after a relaunch.
    private struct Label: Codable { let key: String, limit: Int64 }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]
    private let configuration: URLSessionConfiguration
    private let inbox: URL?
    private let allowsMeteredNetwork: @Sendable () -> Bool
    private let received: @Sendable (Int64) -> Void
    private var moved = 0
    private var restsUntil = Date.distantPast
    private var eventsDone: (@Sendable () -> Void)?
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    /// Nothing is kept: no cookies, no cache, no stored credential.
    static func foreground() -> URLSessionConfiguration { .ephemeral }

    convenience init(allowsMeteredNetwork: @escaping @Sendable () -> Bool) {
        self.init(configuration: Self.foreground(), inbox: nil, allowsMeteredNetwork: allowsMeteredNetwork)
    }

    convenience init(configuration: URLSessionConfiguration = DriveSession.foreground(), allowsMeteredNetwork: Bool = false) {
        self.init(configuration: configuration, inbox: nil, allowsMeteredNetwork: { allowsMeteredNetwork })
    }

    /// The session the system runs for the app. `received`: bytes of the task under way, as they come.
    public static func background(identifier: String, inbox: URL, allowsMeteredNetwork: @escaping @Sendable () -> Bool,
                                  received: @escaping @Sendable (Int64) -> Void) -> DriveSession {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return DriveSession(configuration: configuration, inbox: inbox, allowsMeteredNetwork: allowsMeteredNetwork, received: received)
    }

    init(configuration: URLSessionConfiguration, inbox: URL?, allowsMeteredNetwork: @escaping @Sendable () -> Bool,
         received: @escaping @Sendable (Int64) -> Void = { _ in }) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = inbox == nil ? 30 : 120
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        (self.configuration, self.inbox, self.allowsMeteredNetwork, self.received) = (configuration, inbox, allowsMeteredNetwork, received)
    }

    func close() { session.invalidateAndCancel() }

    /// Connects to what the system did while the app was away; `done` is called when every answer has been put in its place.
    public func reconnect(_ done: @escaping @Sendable () -> Void) {
        lock.withLock { eventsDone = done }
        _ = session
    }

    /// Stops everything and forgets the answers that were kept.
    public func abandon() async {
        for task in await session.allTasks { task.cancel() }
        if let inbox { try? FileManager.default.removeItem(at: inbox) }
    }

    /// How many ticks of five seconds without a byte, while the app runs, before a background task is given up for a foreground one: the
    /// system's downloader can leave a task of an earlier run waiting for ever.
    static let patience = 4
    static let rest: TimeInterval = 600
    var rests: Bool { lock.withLock { restsUntil } > Date() }

    func send(_ request: URLRequest, to file: URL, limit: Int64) async throws -> DriveReply {
        let request = limited(request)
        let key = inbox == nil ? "" : Self.key(request)
        if inbox != nil {
            if let reply = try take(key, to: file) { return reply }
            // The same range, still on its way since before the app was ended: its answer will be kept, then taken.
            if let running = await session.allTasks.first(where: { label($0)?.key == key && lock.withLock { [id = $0.taskIdentifier] in jobs[id] == nil } }) {
                return try await follow(running, file: file, limit: limit, key: key)
            }
        }
        try Task.checkCancellation()
        let task = session.downloadTask(with: request)
        if inbox != nil { task.taskDescription = (try? JSONEncoder().encode(Label(key: key, limit: limit))).map { String(decoding: $0, as: UTF8.self) } }
        return try await follow(task, file: file, limit: limit, key: key)
    }

    func limited(_ request: URLRequest) -> URLRequest {
        var request = request
        let metered = allowsMeteredNetwork()
        request.allowsCellularAccess = metered
        request.allowsExpensiveNetworkAccess = metered
        return request
    }

    func keep(_ location: URL, _ reply: DriveReply, request: URLRequest, limit: Int64) {
        keep(location, reply, label: Label(key: Self.key(request), limit: limit))
    }

    private func follow(_ task: URLSessionTask, file: URL, limit: Int64, key: String) async throws -> DriveReply {
        let watch = inbox == nil ? nil : Task { [weak self, weak task] in
            var seen = -1, still = 0
            while !Task.isCancelled, still < Self.patience {
                try await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let now = lock.withLock { moved }
                still = now == seen ? still + 1 : 0
                seen = now
            }
            guard !Task.isCancelled, let self, let task else { return }
            lock.withLock { restsUntil = Date(timeIntervalSinceNow: Self.rest) }
            fail(task, ShelfError.interrupted)
            task.cancel()
        }
        defer { watch?.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { done in
                lock.withLock { jobs[task.taskIdentifier] = Job(file: file, limit: limit, done: done) }
                // It may have ended between being seen and being followed.
                if task.state == .completed, let job = lock.withLock({ jobs.removeValue(forKey: task.taskIdentifier) }) {
                    do { job.done.resume(with: .success(try take(key, to: file) ?? { throw ShelfError.interrupted }())) }
                    catch { job.done.resume(throwing: error) }
                } else { task.resume() }
            }
        } onCancel: { task.cancel() }
    }

    private static func key(_ request: URLRequest) -> String {
        let text = (request.url?.path ?? "") + "\n" + (request.value(forHTTPHeaderField: "Range") ?? "")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func label(_ task: URLSessionTask) -> Label? {
        task.taskDescription.flatMap { try? JSONDecoder().decode(Label.self, from: Data($0.utf8)) }
    }

    /// An answer kept for a process that is gone.
    private func take(_ key: String, to file: URL) throws -> DriveReply? {
        guard let inbox else { return nil }
        let note = inbox.appendingPathComponent(key + ".json"), body = inbox.appendingPathComponent(key + ".body")
        defer { for one in [note, body] { try? FileManager.default.removeItem(at: one) } }
        guard let data = try? Data(contentsOf: note), let kept = try? JSONDecoder().decode(Kept.self, from: data), kept.status == 206,
              FileManager.default.fileExists(atPath: body.path) else { return nil }
        try FileManager.default.moveItem(at: body, to: file)
        return DriveReply(status: kept.status, headers: kept.headers)
    }

    private func keep(_ location: URL, _ reply: DriveReply, label: Label) {
        guard let inbox, reply.status == 206 else { return }
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? .max
        guard size <= label.limit else { return }
        try? fm.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var folder = inbox, values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        let body = inbox.appendingPathComponent(label.key + ".body")
        try? fm.removeItem(at: body)
        guard (try? fm.moveItem(at: location, to: body)) != nil else { return }
        try? JSONEncoder().encode(Kept(status: reply.status, headers: reply.headers)).write(to: inbox.appendingPathComponent(label.key + ".json"))
    }

    private func fail(_ task: URLSessionTask, _ error: any Error) {
        lock.withLock { if jobs[task.taskIdentifier]?.failure == nil { jobs[task.taskIdentifier]?.failure = error } }
    }

    public func urlSession(_ session: URLSession, downloadTask task: URLSessionDownloadTask, didWriteData: Int64, totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        lock.withLock { moved += 1 }
        received(totalBytesWritten)
        guard let limit = lock.withLock({ jobs[task.taskIdentifier]?.limit }) ?? label(task)?.limit, totalBytesWritten > limit else { return }
        fail(task, ShelfError.badResponse)
        task.cancel()
    }

    public func urlSession(_ session: URLSession, downloadTask task: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let job = lock.withLock({ jobs[task.taskIdentifier] }) else {
            if let label = label(task), let reply = Self.reply(task) { keep(location, reply, label: label) }
            return
        }
        // The temporary file is gone when this returns.
        do {
            let size = try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber
            if size.map({ $0.int64Value > job.limit }) ?? true { fail(task, ShelfError.badResponse) }
            else { try FileManager.default.moveItem(at: location, to: job.file) }
        } catch { fail(task, error as NSError) }
    }

    /// A redirection would carry the credential elsewhere: the answer is given back as it is, and refused. A background session follows
    /// them without asking; the address it ended on is then refused below.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) async -> URLRequest? { nil }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let job = lock.withLock({ jobs.removeValue(forKey: task.taskIdentifier) }) else { return }
        if let failure = job.failure ?? error { return job.done.resume(throwing: Self.translate(failure)) }
        guard let reply = Self.reply(task) else { return job.done.resume(throwing: ShelfError.badResponse) }
        job.done.resume(returning: reply)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let done = lock.withLock { let done = eventsDone; eventsDone = nil; return done }
        done?()
    }

    private static func reply(_ task: URLSessionTask) -> DriveReply? {
        guard let response = task.response as? HTTPURLResponse, response.url == task.originalRequest?.url else { return nil }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields { headers["\(key)".lowercased()] = "\(value)" }
        return DriveReply(status: response.statusCode, headers: headers)
    }

    /// `URLError` names the address it failed on: it is never passed on.
    static func translate(_ error: any Error) -> any Error {
        if error is ShelfError { return error }
        let cocoa = error as NSError
        let posix = (cocoa.userInfo[NSUnderlyingErrorKey] as? NSError) ?? cocoa
        if posix.domain == NSPOSIXErrorDomain && posix.code == 28 { return ShelfError.noSpace(needed: 0) }
        guard let code = (error as? URLError)?.code else { return ShelfError.localFile }
        switch code {
        case .cancelled: return CancellationError()
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive: return ShelfError.offline
        case .timedOut, .networkConnectionLost, .resourceUnavailable, .backgroundSessionWasDisconnected: return ShelfError.interrupted
        case .cannotCreateFile, .cannotOpenFile, .cannotCloseFile, .cannotWriteToFile, .cannotRemoveFile, .cannotMoveFile: return ShelfError.localFile
        default: return ShelfError.badResponse
        }
    }
}
