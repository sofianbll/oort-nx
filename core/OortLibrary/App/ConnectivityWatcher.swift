import Foundation
import Network
import Synchronization

/// Calls `onReturn` on the main queue when the Mac goes from offline to online, so work that met an outage (the
/// background description pass) resumes by itself. Starts on first use; it never reports the first reading.
public final class ConnectivityWatcher: Sendable {
    private let monitor = NWPathMonitor()
    private let onReturn: @MainActor () -> Void
    /// Written on the main queue only.
    private let state = Mutex((started: false, online: Bool?.none))

    public init(onReturn: @escaping @MainActor () -> Void) {
        self.onReturn = onReturn
    }

    deinit { monitor.cancel() }

    /// Main queue only, like `onReturn`.
    public func start() {
        guard state.withLock({ state in
            defer { state.started = true }
            return !state.started
        }) else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let now = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let returned = self.state.withLock { state in
                    defer { state.online = now }
                    return Self.returned(previous: state.online, current: now)
                }
                if returned { MainActor.assumeIsolated { self.onReturn() } }
            }
        }
        monitor.start(queue: DispatchQueue(label: "Arcane.connectivity"))
    }

    /// The connection as it is now, without waiting for a server.
    public static func isOnline() async -> Bool {
        let monitor = NWPathMonitor()
        for await path in monitor { return path.status == .satisfied }
        return true
    }

    /// True only for a change from offline to online; the first reading is never a return.
    public static func returned(previous: Bool?, current: Bool) -> Bool {
        previous == false && current
    }
}
