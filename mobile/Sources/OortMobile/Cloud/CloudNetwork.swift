import Foundation
import Network

/// What the system says of the connection. Watching it sends nothing. It starts only when the module is on.
public final class CloudNetwork: @unchecked Sendable {
    public enum State: Sendable { case none, metered, free }

    private let lock = NSLock()
    private var state = State.free
    private let monitor: NWPathMonitor?

    public init() { monitor = NWPathMonitor() }
    /// A fixed answer, for checks.
    public init(_ state: State) { (self.state, monitor) = (state, nil) }

    var now: State { lock.withLock { state } }

    func start(_ changed: @escaping @Sendable () -> Void) {
        monitor?.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let next: State = path.status != .satisfied ? .none : path.isExpensive || path.isConstrained ? .metered : .free
            let moved = lock.withLock { let moved = state != next; state = next; return moved }
            if moved { changed() }
        }
        monitor?.start(queue: .global(qos: .utility))
    }

    func stop() { monitor?.cancel() }
}
