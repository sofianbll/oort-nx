import Foundation

/// The profile screen is a stack: the selector, the wizard that replaces it, the removal question over it.
/// Only the top layer takes the input and draws its hints; the wizard hides the selector altogether.
public struct ProfileLayers: Equatable {
    public enum Layer: CaseIterable { case selector, editor, removal }

    public var editing: Bool
    public var removing: Bool

    public init(editing: Bool, removing: Bool) {
        self.editing = editing
        self.removing = removing
    }

    public var top: Layer { removing ? .removal : editing ? .editor : .selector }
    public func isTop(_ layer: Layer) -> Bool { top == layer }
    public var showsSelector: Bool { !editing }
}
