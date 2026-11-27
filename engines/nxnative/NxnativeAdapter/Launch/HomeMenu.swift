import Darwin
import Foundation

/// The background-pause protocol of NX2Apple patch 0035.
public enum HomeMenu {
    static let launcherKey = "DM_HOME_MENU_LAUNCHER"
    static let bundleIDKey = "DM_LAUNCHER_BUNDLE_ID"

    public static func hostExecutable(in app: URL) -> URL {
        app.appendingPathComponent("Contents/MacOS/dmhost")
    }

    /// Check the installed build, not the currently selected checkout: either can be newer than the other.
    public static func supported(by app: URL, knownEngine: Bool = false) -> Bool {
        guard let host = try? Data(contentsOf: hostExecutable(in: app), options: [.mappedIfSafe]) else { return false }
        func contains(_ marker: String) -> Bool {
            host.range(of: Data("\(marker)\0".utf8)) != nil
        }
        // For imported/backported builds, the wire markers can prove support without engine history.
        return contains(launcherKey) && contains(bundleIDKey)
            && (knownEngine || contains("org.nxnative.%@.%d")
                || (contains("org.nxnative.resume.%d") && contains("org.nxnative.quit.%d")))
    }

    public static func environment(supported: Bool, launcherBundleID: String?) -> [String: String] {
        guard supported, let launcherBundleID, !launcherBundleID.isEmpty else { return [:] }
        return [launcherKey: "1", bundleIDKey: launcherBundleID]
    }

    public static func notification(_ event: String, pid: Int32) -> String {
        "org.nxnative.\(event).\(pid)"
    }

    /// The launcher can briefly have other children. Match the host executable and pin its process identity.
    public struct Host: Equatable, Sendable {
        public let pid: Int32
        private let startedSeconds: UInt64
        private let startedMicroseconds: UInt64

        private init?(pid: Int32) {
            guard pid > 0 else { return nil }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            self.pid = pid
            startedSeconds = info.pbi_start_tvsec
            startedMicroseconds = info.pbi_start_tvusec
        }

        public static func find(appPID: Int32, executable: URL) -> Host? {
            guard appPID > 0 else { return nil }
            let expected = executable.resolvingSymlinksInPath().path
            if let host = matching(appPID, executable: expected) { return host }
            let count = proc_listchildpids(appPID, nil, 0)
            guard count > 0 else { return nil }
            var children = [pid_t](repeating: 0, count: Int(count) + 16)
            let listed = proc_listchildpids(appPID, &children, Int32(children.count * MemoryLayout<pid_t>.size))
            return children.prefix(max(0, Int(listed))).lazy.compactMap {
                matching($0, executable: expected)
            }.first
        }

        private static func matching(_ pid: pid_t, executable: String) -> Host? {
            guard let identity = Host(pid: pid) else { return nil }
            var path = [CChar](repeating: 0, count: Int(PATH_MAX) * 4)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
                  String(cString: path) == executable else { return nil }
            return identity
        }

        public var isAlive: Bool { Self(pid: pid) == self }

        @discardableResult
        public func terminate() -> Bool {
            isAlive && Darwin.kill(pid, SIGTERM) == 0
        }
    }

    public struct Session {
        public enum Event: Sendable { case paused, resumed, exited }
        public enum Phase: Equatable { case running, paused, quitting, exited }

        public let pid: Int32
        public private(set) var phase: Phase = .running

        public init(pid: Int32) { self.pid = pid }

        public mutating func receive(_ event: Event, from pid: Int32) {
            guard pid == self.pid, phase != .exited else { return }
            switch event {
            case .paused: if phase == .running { phase = .paused }
            case .resumed: phase = .running
            case .exited: phase = .exited
            }
        }

        public func resumeRequest(hostIsHidden: Bool = false) -> String? {
            guard phase == .paused || (phase == .running && hostIsHidden) else { return nil }
            return HomeMenu.notification("resume", pid: pid)
        }

        public mutating func requestQuit() -> String? {
            guard phase == .paused else { return nil }
            phase = .quitting
            return HomeMenu.notification("quit", pid: pid)
        }

        public mutating func quitTimedOut() {
            if phase == .quitting { phase = .paused }
        }
    }
}
