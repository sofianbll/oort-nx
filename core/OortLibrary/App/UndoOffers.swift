import Foundation
import Observation

/// The last reversible gesture and its way back: a notice shows it, then Activity keeps it until another one
/// replaces it, so nothing that must be read leaves with the notice.
@Observable
public final class UndoOffers {
    public struct Offer: Identifiable, Equatable {
        public let id: UUID
        public let message: String
    }

    public private(set) var offer: Offer?
    /// The notice is on screen.
    public private(set) var isShown = false
    @ObservationIgnored private var undo: (() -> Void)?

    public init() {}

    public func offer(_ message: String, undo: @escaping () -> Void) {
        offer = Offer(id: UUID(), message: message)
        self.undo = undo
        isShown = true
    }

    /// Once only: the way back may itself offer another gesture.
    @discardableResult public func perform() -> Bool {
        guard let undo else { return false }
        drop()
        undo()
        return true
    }

    /// The notice leaves; a newer one stays.
    public func hide(_ id: UUID) {
        if offer?.id == id { isShown = false }
    }

    /// Another profile cannot undo what this one did.
    public func drop() {
        offer = nil
        undo = nil
        isShown = false
    }
}
