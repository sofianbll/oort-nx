import Foundation

/// One optional rcd per backend. The lock guards process ownership, not concurrent RC requests.
final class RcloneRemoteControl: @unchecked Sendable {
    private static let directoryPrefix = "arcane-rc-"
    private static let gateName = "arcane-rc.lock"
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
    private var launching: RcloneDownload.Launchable?
    private var stopped = false
    private var retryAfter = 0.0

    // Keep the daemon as the group leader, and give the watcher only the pipe's read end.
    // EOF means the owning app is gone (even after SIGKILL); group 0 cannot select a recycled PID.
    private static let watchedLaunch = """
        exec 3<&0
        (IFS= read -r unused <&3; kill -KILL 0) &
        exec "$@" </dev/null 3<&-
        """

    private struct Session {
        let process: BoundedChild
        let executable: URL
        let flags: [String]
        let directory: URL
        let lease: Int32
        let owner: FileHandle
        let log: SearchLog

        var socket: URL { directory.appendingPathComponent("s") }

        func stop() {
            process.stop()
            try? owner.close()
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
            launching = nil
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
            launching = nil
            guard ProcessInfo.processInfo.systemUptime >= retryAfter else { return nil }
            if let (started, launch) = Self.launch(executable: executable, environment: environment, flags: flags) {
                session = started
                launching = launch
            }
            if session == nil { backOff() }
            return session
        }) else { return nil }

        // rcd creates the socket as it starts listening; it has failed only once it exits. Under load rclone 1.75.2
        // took 3.5 to 9.5 s to bind (0.06 s idle), so the start shares the request's budget instead of a timer of its own.
        let socket = current.socket
        let end = ProcessInfo.processInfo.systemUptime + (sensitive ? 300 : 60)
        while !FileManager.default.fileExists(atPath: socket.path),
              ProcessInfo.processInfo.systemUptime < end, lock.withLock({ session?.process === current.process && current.process.status == nil }) {
            do { try await Task.sleep(nanoseconds: 20_000_000) }
            catch { if sensitive { discard(current) }; throw error }
        }
        // curl reads 0 as no limit; its runner still ends the call within the request's budget.
        let remaining = max(end - ProcessInfo.processInfo.systemUptime, 1)
        let ready = FileManager.default.fileExists(atPath: socket.path)
        if ready {
            lock.withLock {
                if session?.process === current.process { launching = nil }
            }
        }
        let result: CommandResult?
        do {
            result = ready ? try await SystemCommandRunner().runCancellable(Self.curl,
                Self.request(socket: socket, operation: operation, body: sensitive ? "@-" : body,
                             timeout: String(format: "%.3f", remaining)),
                environment: [:], input: sensitive ? Data(body.utf8) : nil, seconds: remaining + (sensitive ? 5 : 2)) : nil
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
                launching = nil
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
            launching = nil
        }
    }

    private static func launch(executable: URL, environment: [String: String], flags: [String])
        -> (Session, RcloneDownload.Launchable)? {
        guard let launch = try? RcloneDownload.launchable(executable),
              let (directory, lease) = sessionDirectory(in: temporary) else { return nil }

        let socket = directory.appendingPathComponent("s")
        let log = SearchLog()
        let lifetime = Pipe()
        let owner = lifetime.fileHandleForWriting
        defer { try? log.pipe.fileHandleForWriting.close() }
        defer { try? lifetime.fileHandleForReading.close() }
        if socket.path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path),
           fcntl(owner.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0,
           let process = try? BoundedChild(URL(fileURLWithPath: "/bin/sh"),
               ["-c", watchedLaunch, "oort-rcd", launch.url.path, "rcd", "--rc-addr", "unix://\(socket.path)", "--rc-no-auth"] + flags,
               // Socket activation would override --rc-addr.
               environment: environment.filter { !["LISTEN_PID", "LISTEN_FDS", "LISTEN_FDNAMES"].contains($0.key) },
               input: lifetime.fileHandleForReading, error: log.pipe.fileHandleForWriting) {
            return (Session(process: process, executable: executable, flags: flags, directory: directory, lease: lease,
                            owner: owner, log: log), launch)
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

    /// A new private folder for one rcd, already leased.
    static func sessionDirectory(in temporary: URL) -> (URL, Int32)? {
        // Created and leased in one step for every sweep: unleased and empty, the folder would look orphaned.
        gated(in: temporary) {
            var template = temporary.appendingPathComponent(directoryPrefix + "XXXXXX").path.utf8CString
            guard let directory = template.withUnsafeMutableBufferPointer({ buffer -> URL? in
                guard let path = mkdtemp(buffer.baseAddress!) else { return nil }
                return URL(fileURLWithPath: String(cString: path), isDirectory: true)
            }) else { return nil }
            let lease = claim(directory)
            guard lease >= 0 else { _ = rmdir(directory.path); return nil }
            return (directory, lease)
        }
    }

    /// Runs `body` under the folder's lock shared by every Oort process, which `flock` drops if one dies.
    private static func gated<T>(in temporary: URL, _ body: () -> T?) -> T? {
        let gate = open(temporary.appendingPathComponent(gateName).path, O_RDONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard gate >= 0 else { return nil }
        defer { close(gate) }
        // Only this user's own Oort processes may hold it, each for one create or remove.
        var info = stat()
        guard fstat(gate, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0 else { return nil }
        while flock(gate, LOCK_EX) != 0 { guard errno == EINTR else { return nil } }
        return body()
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
            // A live Arcane instance holds its own lease. If rcd has not bound yet, rmdir prevents it from binding later.
            guard let lease = gated(in: temporary, { () -> Int32? in
                let lease = claim(directory)
                guard lease >= 0 else { return nil }
                if rmdir(directory.path) == 0 { close(lease); return nil }
                return lease
            }) else { continue }
            defer { close(lease) }
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
