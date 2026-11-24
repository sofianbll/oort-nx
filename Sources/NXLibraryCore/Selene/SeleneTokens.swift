import CoreGraphics

public enum SeleneTokens {
    /// Canvas units. Secondary variants preserve the proportions of existing screens.
    public enum Text: CGFloat {
        case screenTitle = 40
        case title = 28
        case body = 17
        case caption = 16
        case metadata = 14

        case profileScreenTitle = 44
        case dialogTitle = 34
        case panelTitle = 30
        case profileTitle = 24
        case sectionTitle = 26
        case selectionTitle = 22
        case rowTitle = 21
        case panelBody = 19
        case menuCaption = 18
        case compactCaption = 15
        case heroTitle = 62
        case profileHeroTitle = 82
        case inboxTitle = 48
        case emptyStateTitle = 25
        case attribution = 13
    }

    public enum Space {
        public static let hairline: CGFloat = 4
        public static let seam: CGFloat = 2
        public static let tight: CGFloat = 6
        public static let badge: CGFloat = 7
        public static let compact: CGFloat = 8
        public static let small: CGFloat = 12
        public static let line: CGFloat = 14
        public static let medium: CGFloat = 16
        public static let control: CGFloat = 18
        public static let panel: CGFloat = 20
        public static let large: CGFloat = 24
        public static let titleGap: CGFloat = 22
        public static let feature: CGFloat = 28
        public static let section: CGFloat = 32
        public static let group: CGFloat = 48
        public static let actionPillHeight: CGFloat = 54
        public static let profileKeypadKey: CGFloat = 80
        public static let chromeGutter: CGFloat = 64
        public static let settingsHintsClearance: CGFloat = 100
        public static let settingsInfoClearance: CGFloat = 60
        public static let stageGutter: CGFloat = 120
        public static let stageHeader: CGFloat = 110
        public static let inboxHintsClearance: CGFloat = 95
        public static let inboxPageInset: CGFloat = 62
        public static let emptyStateInset: CGFloat = 25
        public static let toastTop: CGFloat = 112
        public static let transferMeasure: CGFloat = 700
    }

    public enum Radius {
        public static let cover: CGFloat = 6
        public static let row: CGFloat = 10
        public static let content: CGFloat = 12
        public static let card: CGFloat = 16
        public static let modal: CGFloat = 20
        public static let field: CGFloat = 22
        public static let dialog: CGFloat = 28
        public static let collectionFocus: CGFloat = 18
        public static let spotlightFocus: CGFloat = 19
        public static let badge: CGFloat = 14
        public static let anchoredCard: CGFloat = 18
    }

    public enum Color {
        public static let danger: UInt32 = 0xFF6B6B
        public static let statusOK: UInt32 = 0x3DDC84
        public static let statusCloud: UInt32 = 0x9CCBFF
        public static let untested: UInt32 = 0xE8B65C
    }

    public enum Effect {
        public static let panelBlurPoints: CGFloat = 10
        public static let deepBlurPoints: CGFloat = 40
        public static let dialogShadowRadius: CGFloat = 30
        public static let dialogShadowOpacity = 0.55
        public static let menuVeil = 0.55
        public static let deepVeil = 0.65
        public static let panelVeil = 0.45
        public static let searchVeil = 0.82
        public static let profileRemovalVeil = 0.72
        public static let bandBlur: CGFloat = 12
        public static let bandOpacity = 0.55
        public static let cloudBadgeOpacity = 0.94
    }
}

/// Surface roles are independent of the active palette; SwiftUI supplies its tint.
public enum SeleneOverlayStyle: Equatable {
    case menu, deep, options, search, dialog, activity, profileRemoval

    public var backdropBlur: CGFloat {
        switch self {
        case .deep: SeleneTokens.Effect.deepBlurPoints
        case .options: SeleneTokens.Effect.panelBlurPoints
        default: 0
        }
    }

    public var veilOpacity: Double {
        switch self {
        case .menu: SeleneTokens.Effect.menuVeil
        case .deep, .activity: SeleneTokens.Effect.deepVeil
        case .options, .dialog: SeleneTokens.Effect.panelVeil
        case .search: SeleneTokens.Effect.searchVeil
        case .profileRemoval: SeleneTokens.Effect.profileRemovalVeil
        }
    }
}
