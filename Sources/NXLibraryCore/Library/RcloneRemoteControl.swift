import Darwin
import Foundation

/// One optional rcd per backend. The lock guards process ownership, not concurrent RC requests.
final class RcloneRemoteControl: @unchecked Sendable {
    private static let directoryPrefix = "arcane-rc-"
    private static let temporary: URL = {
        if let path = ProcessInfo.processInfo.environment["TMPDIR"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }()
    private static let curl = URL(fileURLWithPath: "/usr/bin/curl")
    private static let sweep = Task.detached(priority: .utility) { reapOrphans(in: temporary) }
    private let lock = NSLock()
    private var session: Session?
    private var stopped = false
    private var retryAfter = 0.0

    private struct Session {
        let process: BoundedChild
        let executable: URL
        let flags: [String]
        let directory: URL
        let lease: Int32
        let readyBy: Double
        let log: SearchLog

        var socket: URL { directory.appendingPathComponent("s") }

        func stop() {
            process.stop()
            try? FileManager.default.removeItem(at: directory)
            close(lease)
        }
    }

    /// Reads what rclone writes for one fact, and keeps nothing else of it: a search Drive did not finish.
    private final class SearchLog: @unchecked Sendable {
        private let lock = NSLock()
        private var tail = Data()
        private var found = false
        private static let marker = Data("search result INCOMPLETE".utf8)
        let pipe = Pipe()

        init() {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty, let self else { handle.readabilityHandler = nil; return }
                self.lock.withLock {
                    let seen = self.tail + chunk
                    if seen.range(of: Self.marker) != nil { self.found = true }
                    self.tail = Data(seen.suffix(Self.marker.count - 1))
                }
            }
        }

        deinit { pipe.fileHandleForReading.readabilityHandler = nil }
        var sawIncompleteSearch: Bool { lock.withLock { found } }
    }

    deinit { stop() }

    func stop() {
        lock.withLock {
            stopped = true
            session?.stop()
            session = nil
        }
    }

    var processID: Int32? {
        lock.withLock { session.flatMap { $0.process.status == nil ? $0.process.pid : nil } }
    }

    /// Whether Drive left anything out of a search since this rclone started.
    var sawIncompleteSearch: Bool { lock.withLock { session?.log.sawIncompleteSearch ?? false } }

    func call(_ operation: String, _ parameters: [String: Any], executable: URL,
              environment: [String: String], flags: [String], sensitive: Bool = false) async throws -> String? {
        guard let (payload, status) = try await request(operation, JSONSerialization.data(withJSONObject: parameters),
            executable: executable, environment: environment, flags: flags, sensitive: sensitive) else { return nil }
        switch status {
        case "200": return payload
        case "404":
            // An older server can also return 404 for an unsupported operation.
            let error = Self.error(in: payload)
            if (operation == "operations/list" && error == "error in ListJSON: directory not found")
                || (operation == "operations/stat" && error == "directory not found") {
                throw StorageBackendError.notFound
            }
            return nil
        default: return nil // The CLI preserves existing error classification without exposing the RC body.
        }
    }

    /// Like `call`, for a listing: a failure of Drive is classified here, since a command would only meet it again.
    func read(_ operation: String, _ parameters: Data, executable: URL,
              environment: [String: String], flags: [String]) async throws -> String? {
        guard let (payload, status) = try await request(operation, parameters, executable: executable,
                                                        environment: environment, flags: flags, sensitive: false) else { return nil }
        if status == "200" { return payload }
        if let error = Self.error(in: payload), let failure = CloudLibraryFailure.rclone(error, status: 1) { throw failure }
        return nil
    }

    private static func error(in payload: String) -> String? {
        struct Failure: Decodable { let error: String }
        return (try? JSONDecoder().decode(Failure.self, from: Data(payload.utf8)))?.error
    }

    private func request(_ operation: String, _ parameters: Data, executable: URL, environment: [String: String],
                         flags: [String], sensitive: Bool) async throws -> (payload: String, status: Substring)? {
        try Task.checkCancellation()
        try RcloneDownload.requireApproved(executable)
        let body = String(decoding: parameters, as: UTF8.self)
        // Sweep happens once off the UI executor without delaying a request or its cancellation.
        _ = Self.sweep
        try Task.checkCancellation()
        guard let current = try lock.withLock({ () throws -> Session? in
            if stopped { throw CancellationError() }
            if let session, session.process.status == nil, session.executable == executable, session.flags == flags { return session }
            session?.stop()
            session = nil
            guard ProcessInfo.processInfo.systemUptime >= retryAfter else { return nil }
            session = Self.launch(executable: executable, environment: environment, flags: flags)
            if session == nil { backOff() }
            return session
        }) else { return nil }

        // rcd creates the socket as it starts listening. Wait briefly without serializing readers.
        let socket = current.socket
        while !FileManager.default.fileExists(atPath: socket.path),
              ProcessInfo.processInfo.systemUptime < current.readyBy, lock.withLock({ session?.process === current.process && current.process.status == nil }) {
            do { try await Task.sleep(nanoseconds: 20_000_000) }
            catch { if sensitive { discard(current) }; throw error }
        }
        let ready = FileManager.default.fileExists(atPath: socket.path)
        let result: CommandResult?
        do {
            result = ready ? try await SystemCommandRunner().runCancellable(Self.curl,
                Self.request(socket: socket, operation: operation, body: sensitive ? "@-" : body,
                             timeout: sensitive ? "300" : "60"),
                environment: [:], input: sensitive ? Data(body.utf8) : nil, seconds: sensitive ? 305 : 62) : nil
        } catch is CancellationError {
            if sensitive || operation == "operations/copyfile" { discard(current) }
            throw CancellationError()
        }
        catch { discard(current); return nil }
        try lock.withLock {
            if stopped { throw CancellationError() }
            if (!ready || result?.status == 7 || result?.status == 28), session?.process === current.process {
                session?.stop()
                session = nil
                if !ready { backOff() }
            }
        }
        guard let result, result.status == 0, let footer = result.stdout.lastIndex(of: "\n") else { return nil }
        return (String(result.stdout[..<footer]), result.stdout[result.stdout.index(after: footer)...])
    }

    private func backOff() { retryAfter = ProcessInfo.processInfo.systemUptime + 30 }

    private func discard(_ current: Session) {
        lock.withLock {
            guard session?.process === current.process else { return }
            session?.stop()
            session = nil
        }
    }

    private static func launch(executable: URL, environment: [String: String], flags: [String]) -> Session? {
        guard let launch = try? RcloneDownload.launchable(executable) else { return nil }
        defer { withExtendedLifetime(launch) {} }
        var template = temporary.appendingPathComponent(directoryPrefix + "XXXXXX").path.utf8CString
        guard let directory = template.withUnsafeMutableBufferPointer({ buffer -> URL? in
            guard let path = mkdtemp(buffer.baseAddress!) else { return nil }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }) else { return nil }
        let lease = claim(directory)
        guard lease >= 0 else { _ = rmdir(directory.path); return nil }

        let socket = directory.appendingPathComponent("s")
        let log = SearchLog()
        defer { try? log.pipe.fileHandleForWriting.close() }
        if socket.path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path),
           let process = try? BoundedChild(launch.url, ["rcd", "--rc-addr", "unix://\(socket.path)", "--rc-no-auth"] + flags,
               // Socket activation would override --rc-addr.
               environment: environment.filter { !["LISTEN_PID", "LISTEN_FDS", "LISTEN_FDNAMES"].contains($0.key) },
               error: log.pipe.fileHandleForWriting) {
            return Session(process: process, executable: executable, flags: flags, directory: directory, lease: lease,
                           readyBy: ProcessInfo.processInfo.systemUptime + 2, log: log)
        }
        close(lease)
        try? FileManager.default.removeItem(at: directory)
        return nil
    }

    private static func request(socket: URL, operation: String, body: String, timeout: String) -> [String] {
        ["-q", "--silent", "--noproxy", "*", "--unix-socket", socket.path, "--connect-timeout", "1",
         "--max-time", timeout, "--header", "Content-Type: application/json", "--data-binary", body,
         "--write-out", "\n%{http_code}", "http://localhost/\(operation)"]
    }

    private static func claim(_ directory: URL) -> Int32 {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return -1 }
        var info = stat()
        if fstat(fd, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700,
           flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
        close(fd)
        return -1
    }

    static func reapOrphans(in temporary: URL) {
        let fm = FileManager.default
        for directory in (try? fm.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? [] {
            let name = directory.lastPathComponent
            guard name.hasPrefix(directoryPrefix), name.utf8.count == directoryPrefix.utf8.count + 6 else { continue }
            let lease = claim(directory)
            guard lease >= 0 else { continue } // A live Arcane instance holds its own lease.
            defer { close(lease) }
            // If rcd has not bound yet, rmdir atomically prevents it from binding later.
            if rmdir(directory.path) == 0 { continue }
            let socket = directory.appendingPathComponent("s")
            var info = stat()
            guard lstat(socket.path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK else { continue }
            let result = try? SystemCommandRunner.runBounded(curl,
                request(socket: socket, operation: "core/quit", body: "{}", timeout: "1"),
                seconds: 2)
            // Don't lose a live daemon's address if the quit request timed out.
            if result?.stdout.hasSuffix("\n200") == true || result?.status == 7 {
                if unlink(socket.path) == 0 || errno == ENOENT { _ = rmdir(directory.path) }
            }
        }
    }
}
