import Foundation

/// The code that follows a store without being a view: SwiftUI views follow an `@Observable` store by reading it, a
/// router or a service registers here. `add` runs the handler at once with `current`, then the store calls `notify`
/// after each change, on the thread that made it, as a Combine subscription did.
// @unchecked: the lock guards the table; a handler runs on the thread of the change (the store's main thread).
public final class StoreListeners<Change>: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [UUID: (Change) -> Void] = [:]

    public init() {}

    public func add(current: Change, _ handler: @escaping (Change) -> Void) -> StoreObservation {
        let id = UUID()
        lock.withLock { handlers[id] = handler }
        handler(current)
        return StoreObservation { [weak self] in
            guard let self else { return }
            _ = self.lock.withLock { self.handlers.removeValue(forKey: id) }
        }
    }

    public func notify(_ change: Change) {
        for handler in lock.withLock({ Array(handlers.values) }) { handler(change) }
    }
}

/// Ends a `StoreListeners.add` when cancelled or dropped.
public final class StoreObservation {
    private var end: (() -> Void)?
    init(_ end: @escaping () -> Void) { self.end = end }
    public func cancel() { end?(); end = nil }
    deinit { end?() }
}
