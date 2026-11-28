#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
import CSystem
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension OortSystem {
    static func streamingTask(for request: URLRequest, session: URLSession, delegate: URLSessionDataDelegate)
        -> (URLSessionDataTask, URLSession?) {
        #if canImport(Darwin)
        let task = session.dataTask(with: request)
        task.delegate = delegate
        return (task, nil)
        #else
        // FoundationNetworking delivers streaming callbacks to the session delegate, not to task.delegate.
        let dedicatedSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        return (dedicatedSession.dataTask(with: request), dedicatedSession)
        #endif
    }

    /// Starts a separate process group with only the three standard descriptors.
    static func spawnCommand(_ path: String, arguments: inout [UnsafeMutablePointer<CChar>?],
                             environment: inout [UnsafeMutablePointer<CChar>?],
                             directory: String?, standard: [FileHandle?]) throws -> pid_t {
        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
        #else
        var actions = posix_spawn_file_actions_t()
        var attributes = posix_spawnattr_t()
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF
        #endif
        try checkPOSIX(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try checkPOSIX(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try checkPOSIX(posix_spawnattr_setflags(&attributes, Int16(flags)))
        try checkPOSIX(posix_spawnattr_setpgroup(&attributes, 0))
        #if canImport(Glibc)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        try checkPOSIX(posix_spawnattr_setsigdefault(&attributes, &defaults))
        #endif
        if let directory {
            #if canImport(Darwin)
            try checkPOSIX(posix_spawn_file_actions_addchdir(&actions, directory))
            #elseif canImport(Glibc)
            try checkPOSIX(oort_spawn_chdir(&actions, directory))
            #endif
        }
        for (index, handle) in standard.enumerated() {
            let fd = Int32(index)
            if let handle {
                try checkPOSIX(posix_spawn_file_actions_adddup2(&actions, handle.fileDescriptor, fd))
            } else {
                try checkPOSIX(posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0))
            }
        }
        #if canImport(Glibc)
        try checkPOSIX(oort_spawn_closefrom(&actions, 3))
        #endif
        var child: pid_t = 0
        try checkPOSIX(posix_spawn(&child, path, &actions, &attributes, &arguments, &environment))
        return child
    }

    /// Peeks at the exit status without reaping the process group leader.
    static func commandStatus(_ pid: pid_t) -> Int32? {
        #if canImport(Darwin)
        var info = siginfo_t()
        guard waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT | WNOHANG) == 0, info.si_pid != 0 else { return nil }
        switch info.si_code {
        case CLD_EXITED: return info.si_status
        case CLD_KILLED, CLD_DUMPED: return 128 + info.si_status
        default: return nil
        }
        #elseif canImport(Glibc)
        var status: Int32 = 0
        return oort_child_status(pid, &status) != 0 ? status : nil
        #endif
    }

    #if canImport(Glibc)
    // Linux has no per-descriptor switch. The parent handles EPIPE; spawnCommand restores the signal in children.
    private static let ignoreBrokenPipe: Int32 = {
        var action = sigaction()
        action.__sigaction_handler.sa_handler = SIG_IGN
        sigemptyset(&action.sa_mask)
        return sigaction(SIGPIPE, &action, nil) == 0 ? 0 : errno
    }()
    #endif

    static func prepareCommandInput(_ fd: Int32) throws {
        #if canImport(Darwin)
        if fcntl(fd, F_SETNOSIGPIPE, 1) != 0 { try checkPOSIX(errno) }
        #elseif canImport(Glibc)
        try checkPOSIX(ignoreBrokenPipe)
        #endif
    }
}
