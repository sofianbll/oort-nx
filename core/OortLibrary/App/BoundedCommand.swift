import Darwin
import Foundation

/// The leader stays unreaped until the group is stopped, so its group ID cannot be recycled.
final class BoundedChild: @unchecked Sendable {
    private static let live = Live()
    private final class Live: @unchecked Sendable {
        let lock = NSLock()
        var children: [pid_t: BoundedChild] = [:]
        var quitting = false
    }

    let pid: pid_t

    init(_ executable: URL, _ arguments: [String], environment: [String: String]?,
         directory: URL? = nil, input: FileHandle? = nil,
         output: FileHandle? = nil, error: FileHandle? = nil) throws {
        var actions: posix_spawn_file_actions_t?
        try checkPOSIX(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        var attributes: posix_spawnattr_t?
        try checkPOSIX(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try checkPOSIX(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        try checkPOSIX(posix_spawnattr_setpgroup(&attributes, 0))
        if let directory { try checkPOSIX(posix_spawn_file_actions_addchdir(&actions, directory.path)) }
        for (index, handle) in [input, output, error].enumerated() {
            let fd = Int32(index)
            if let handle {
                try checkPOSIX(posix_spawn_file_actions_adddup2(&actions, handle.fileDescriptor, fd))
            } else {
                try checkPOSIX(posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0))
            }
        }
        var args = ([executable.path] + arguments).map { strdup($0) }
        var env = (environment ?? ProcessInfo.processInfo.environment).map { strdup("\($0.key)=\($0.value)") }
        defer { (args + env).forEach { free($0) } }
        guard !args.contains(nil), !env.contains(nil) else { throw POSIXError(.ENOMEM) }
        args.append(nil)
        env.append(nil)
        var child: pid_t = 0
        let registry = Self.live
        registry.lock.lock()
        defer { registry.lock.unlock() }
        guard !registry.quitting else { throw CancellationError() }
        try checkPOSIX(posix_spawn(&child, executable.path, &actions, &attributes, &args, &env))
        pid = child
        registry.children[child] = self
    }

    var status: Int32? {
        Self.live.lock.withLock {
            guard Self.live.children[pid] === self else { return nil }
            var info = siginfo_t()
            guard waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT | WNOHANG) == 0, info.si_pid != 0 else { return nil }
            switch info.si_code {
            case CLD_EXITED: return info.si_status
            case CLD_KILLED, CLD_DUMPED: return 128 + info.si_status
            default: return nil
            }
        }
    }

    func stop() {
        let registry = Self.live
        registry.lock.withLock {
            if registry.children[pid] === self {
                registry.children.removeValue(forKey: pid)
                stopGroup()
            }
        }
    }

    static func stopAll() {
        live.lock.withLock {
            live.quitting = true
            for child in live.children.values { child.stopGroup() }
            live.children.removeAll()
        }
    }

    private func stopGroup() {
        kill(-pid, SIGKILL)
        let child = pid
        DispatchQueue.global(qos: .utility).async {
            while waitpid(child, nil, 0) == -1 && errno == EINTR {}
        }
    }
}

private func checkPOSIX(_ error: Int32) throws {
    if error != 0 { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO) }
}

package struct CommandDeadline: Error {}

struct BoundedCommandRunner: CommandRunning, Sendable {
    // macOS can close the streams after the leader exits under load. Bound an open pipe, not normal exit latency.
    private static let postExitDrainSafetyLimit = 3.0

    let seconds: Double
    let cancellation: CommandCancellation

    func run(_ executable: URL, _ arguments: [String], environment: [String: String]?,
             currentDirectory: URL?) throws -> CommandResult {
        try run(executable, arguments, environment: environment, currentDirectory: currentDirectory, input: nil)
    }

    func run(_ executable: URL, _ arguments: [String], environment: [String: String]?,
             currentDirectory: URL? = nil, input: Data?, output: FileHandle? = nil,
             onStderr: ((String) -> Void)? = nil, activity: ((String) -> [Int64]?)? = nil) throws -> CommandResult {
        try cancellation.check()
        let stdin = try input.map { _ in try Self.commandPipe() }
        let stdout = output == nil ? try Self.commandPipe() : nil
        let stderr = try Self.commandPipe()
        let writeEnd = stdin?.fileHandleForWriting
        if let writeEnd, fcntl(writeEnd.fileDescriptor, F_SETNOSIGPIPE, 1) != 0 { try checkPOSIX(errno) }
        let child = try BoundedChild(executable, arguments, environment: environment, directory: currentDirectory,
            input: stdin?.fileHandleForReading, output: output ?? stdout?.fileHandleForWriting, error: stderr.fileHandleForWriting)
        defer { child.stop() }
        try stdin?.fileHandleForReading.close()
        try stdout?.fileHandleForWriting.close()
        try stderr.fileHandleForWriting.close()
        defer { try? writeEnd?.close() }
        var fds = [stdout?.fileHandleForReading, stderr.fileHandleForReading, writeEnd].enumerated().map {
            pollfd(fd: $0.element?.fileDescriptor ?? -1, events: Int16($0.offset == 2 ? POLLOUT : POLLIN), revents: 0)
        }
        for fd in fds.map(\.fd) where fd >= 0 {
            if fcntl(fd, F_SETFL, O_NONBLOCK) != 0 { try checkPOSIX(errno) }
        }
        var offset = 0
        var collected = [Data(), Data()]
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        var lines = LineBuffer()
        var unterminated = 0
        var lastActivity: [Int64]?
        let now = { ProcessInfo.processInfo.systemUptime }
        var deadline = now() + seconds
        var drainDeadline: Double?
        while true {
            try cancellation.check()
            if let status = child.status {
                if fds[0].fd < 0 && fds[1].fd < 0 {
                    if let onStderr { lines.finish().forEach(onStderr) }
                    return .init(status: status, stdout: String(decoding: collected[0], as: UTF8.self),
                                 stderr: String(decoding: collected[1], as: UTF8.self))
                }
                if drainDeadline == nil { drainDeadline = now() + Self.postExitDrainSafetyLimit }
            }
            let instant = now()
            guard instant < deadline else { throw CommandDeadline() }
            let drainLimitReached = drainDeadline.map { instant >= $0 } ?? false
            // Nothing more to read: only the exit is awaited, a moment away.
            let interval: Int32 = drainLimitReached ? 0 : fds[0].fd < 0 && fds[1].fd < 0 ? 1 : 50
            if poll(&fds, nfds_t(fds.count), interval) < 0 {
                if errno == EINTR { continue }
                try checkPOSIX(errno)
            }
            // Drain buffered data from closed pipes even if the reader was rescheduled after the limit.
            if drainLimitReached, fds.prefix(2).contains(where: { $0.fd >= 0 && $0.revents & Int16(POLLHUP) == 0 }) {
                throw CommandDeadline()
            }
            for index in 0..<2 where fds[index].fd >= 0 && fds[index].revents != 0 {
                let count = read(fds[index].fd, &buffer, buffer.count)
                if count == 0 { fds[index].fd = -1; continue }
                if count < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    try checkPOSIX(errno)
                }
                let chunk = Data(buffer.prefix(count))
                // On long transfers the progress lines matter, not an unbounded history of repeated stats.
                if index == 0, collected[0].count + count > 128 * 1024 * 1024 { throw POSIXError(.EFBIG) }
                if index == 1, collected[1].count >= 1024 * 1024 { collected[1].removeFirst(512 * 1024) }
                collected[index].append(chunk)
                if index == 1, onStderr != nil || activity != nil {
                    if let newline = chunk.lastIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                        unterminated = chunk.count - newline - 1
                    } else { unterminated += chunk.count }
                    guard unterminated <= 1024 * 1024 else { throw POSIXError(.EFBIG) }
                    for line in lines.append(chunk) {
                        if let next = activity?(line), next != lastActivity {
                            lastActivity = next
                            deadline = now() + seconds
                        }
                        onStderr?(line)
                    }
                }
            }
            if let input, fds[2].fd >= 0, fds[2].revents != 0 {
                let count = input.withUnsafeBytes { bytes in
                    write(fds[2].fd, bytes.baseAddress?.advanced(by: offset), min(16 * 1024, bytes.count - offset))
                }
                if count > 0 { offset += count }
                if offset == input.count || (count < 0 && errno == EPIPE) {
                    fds[2].fd = -1
                    try writeEnd?.close()
                } else if count < 0 && errno != EINTR && errno != EAGAIN { try checkPOSIX(errno) }
            }
        }
    }

    static func commandPipe() throws -> Pipe {
        let pipe = Pipe()
        // Only the descriptors the child explicitly duplicates onto stdin/stdout/stderr may survive exec.
        for end in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
            let fd = end.fileDescriptor
            if fcntl(fd, F_SETFD, FD_CLOEXEC) != 0 { try checkPOSIX(errno) }
        }
        return pipe
    }
}
