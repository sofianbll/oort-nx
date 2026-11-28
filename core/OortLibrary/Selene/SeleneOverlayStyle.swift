import Foundation

/// Surface roles are independent of the active palette; SwiftUI supplies its tint.
public enum SeleneOverlayStyle: Equatable {
    case menu, deep, options, search, dialog, activity, profileRemoval, page

    public var backdropBlur: CGFloat {
        switch self {
        case .deep: SeleneTokens.Effect.deepBlurPoints
        case .options: SeleneTokens.Effect.panelBlurPoints
        default: 0
        }
    }

    public var veilOpacity: Double? {
        switch self {
        case .menu: SeleneTokens.Effect.menuVeil
        case .deep, .activity: SeleneTokens.Effect.deepVeil
        case .options, .dialog: SeleneTokens.Effect.panelVeil
        case .search: SeleneTokens.Effect.searchVeil
        case .profileRemoval: SeleneTokens.Effect.profileRemovalVeil
        case .page: nil
        }
    }
}
