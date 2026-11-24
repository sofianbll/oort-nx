import Darwin
import Foundation

/// One optional rcd per backend. The lock guards process ownership, not concurrent RC requests.
final class RcloneRemoteControl: @unchecked Sendable {
    private static let directoryPrefix = "arcane-rc-"
    private static let temporary = FileManager.default.temporaryDirectory
    private static let curl = URL(fileURLWithPath: "/usr/bin/curl")
    private static let sweptOrphans: Void = reapOrphans(in: temporary)
    private let lock = NSLock()
    private var session: Session?
    private var stopped = false
    private var retryAfter = 0.0

    private struct Session {
        let process: Process
        let executable: URL
        let directory: URL
        let lease: Int32
        let readyBy: Double

        var socket: URL { directory.appendingPathComponent("s") }

        func stop() {
            if process.isRunning { process.terminate() }
            try? FileManager.default.removeItem(at: directory)
            close(lease)
        }
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
        lock.withLock { session.flatMap { $0.process.isRunning ? $0.process.processIdentifier : nil } }
    }

    func call(_ operation: String, _ parameters: [String: Any], executable: URL,
              environment: [String: String], flags: [String], sensitive: Bool = false) async throws -> String? {
        try Task.checkCancellation()
        try RcloneDownload.requireApproved(executable)
        let body = String(decoding: try JSONSerialization.data(withJSONObject: parameters), as: UTF8.self)
        // Sweep happens once off the UI executor, even if multiple reads arrive together.
        _ = await Task.detached(priority: .utility) { Self.sweptOrphans }.value
        try Task.checkCancellation()
        guard let current = try lock.withLock({ () throws -> Session? in
            if stopped { throw CancellationError() }
            if let session, session.process.isRunning, session.executable == executable { return session }
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
              ProcessInfo.processInfo.systemUptime < current.readyBy, lock.withLock({ current.process.isRunning }) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let ready = FileManager.default.fileExists(atPath: socket.path)
        let result: CommandResult?
        do {
            result = ready ? try await SystemCommandRunner().runCancellable(Self.curl,
                Self.request(socket: socket, operation: operation, body: sensitive ? "@-" : body, timeout: "300"),
                environment: [:], input: sensitive ? Data(body.utf8) : nil) : nil
        } catch is CancellationError { throw CancellationError() }
        catch { return nil }
        try lock.withLock {
            if stopped { throw CancellationError() }
            if (!ready || result?.status == 7), session?.process === current.process {
                session?.stop()
                session = nil
                if !ready { backOff() }
            }
        }
        guard let result, result.status == 0, let footer = result.stdout.lastIndex(of: "\n") else { return nil }
        let payload = String(result.stdout[..<footer])
        switch result.stdout[result.stdout.index(after: footer)...] {
        case "200": return payload
        case "404":
            // An older server can also return 404 for an unsupported operation.
            struct Failure: Decodable { let error: String }
            let error = (try? JSONDecoder().decode(Failure.self, from: Data(payload.utf8)))?.error
            if (operation == "operations/list" && error == "error in ListJSON: directory not found")
                || (operation == "operations/stat" && error == "directory not found") {
                throw StorageBackendError.notFound
            }
            return nil
        default: return nil // The CLI preserves existing error classification without exposing the RC body.
        }
    }

    private func backOff() { retryAfter = ProcessInfo.processInfo.systemUptime + 30 }

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

        let process = Process()
        let session = Session(process: process, executable: executable, directory: directory, lease: lease,
                              readyBy: ProcessInfo.processInfo.systemUptime + 2)
        guard session.socket.path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            session.stop()
            return nil
        }
        process.executableURL = launch.url
        process.arguments = ["rcd", "--rc-addr", "unix://\(session.socket.path)", "--rc-no-auth"] + flags
        // Socket activation would override --rc-addr. Do not inherit that or any unfiltered rclone flags.
        process.environment = environment.filter { !["LISTEN_PID", "LISTEN_FDS", "LISTEN_FDNAMES"].contains($0.key) }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); return session }
        catch { session.stop(); return nil }
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
            let result = try? SystemCommandRunner().run(curl,
                request(socket: socket, operation: "core/quit", body: "{}", timeout: "1"),
                environment: [:], currentDirectory: nil)
            // Don't lose a live daemon's address if the quit request timed out.
            if result?.stdout.hasSuffix("\n200") == true || result?.status == 7 {
                if unlink(socket.path) == 0 || errno == ENOENT { _ = rmdir(directory.path) }
            }
        }
    }
}
