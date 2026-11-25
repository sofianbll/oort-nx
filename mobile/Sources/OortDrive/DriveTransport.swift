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
}

/// Download tasks with a delegate and nothing else: the only shape a background session accepts, so `.background` takes the same path.
final class DriveSession: NSObject, DriveTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct Job {
        let file: URL
        let limit: Int64
        let done: CheckedContinuation<DriveReply, any Error>
        var failure: (any Error)?
    }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]
    private let configuration: URLSessionConfiguration
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    /// Nothing is kept: no cookies, no cache, no stored credential.
    static func foreground() -> URLSessionConfiguration { .ephemeral }

    init(configuration: URLSessionConfiguration = DriveSession.foreground(), allowsMeteredNetwork: Bool = false) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.allowsCellularAccess = allowsMeteredNetwork
        configuration.allowsExpensiveNetworkAccess = allowsMeteredNetwork
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        self.configuration = configuration
    }

    func close() { session.invalidateAndCancel() }

    func send(_ request: URLRequest, to file: URL, limit: Int64) async throws -> DriveReply {
        let task = session.downloadTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { done in
                lock.withLock { jobs[task.taskIdentifier] = Job(file: file, limit: limit, done: done) }
                task.resume()
            }
        } onCancel: { task.cancel() }
    }

    private func fail(_ task: URLSessionTask, _ error: any Error) {
        lock.withLock { if jobs[task.taskIdentifier]?.failure == nil { jobs[task.taskIdentifier]?.failure = error } }
    }

    func urlSession(_ session: URLSession, downloadTask task: URLSessionDownloadTask, didWriteData: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let limit = lock.withLock({ jobs[task.taskIdentifier]?.limit }), totalBytesWritten > limit else { return }
        fail(task, ShelfError.badResponse)
        task.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask task: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let job = lock.withLock({ jobs[task.taskIdentifier] }) else { return }
        // The temporary file is gone when this returns.
        do {
            let size = try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber
            if size.map({ $0.int64Value > job.limit }) ?? true { fail(task, ShelfError.badResponse) }
            else { try FileManager.default.moveItem(at: location, to: job.file) }
        } catch { fail(task, error as NSError) }
    }

    /// A redirection would carry the credential elsewhere: the answer is given back as it is, and refused.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let job = lock.withLock({ jobs.removeValue(forKey: task.taskIdentifier) }) else { return }
        if let failure = job.failure ?? error { return job.done.resume(throwing: Self.translate(failure)) }
        guard let response = task.response as? HTTPURLResponse else { return job.done.resume(throwing: ShelfError.badResponse) }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields { headers["\(key)".lowercased()] = "\(value)" }
        job.done.resume(returning: DriveReply(status: response.statusCode, headers: headers))
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
