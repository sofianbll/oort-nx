/// The catalogue order, words and detail phases are shared. Each owner supplies only the installed offers and
/// their observed state; a renderer neither classifies an integration nor invents a missing capability.
public enum IntegrationCatalog {
    public enum ID: String, CaseIterable, Sendable {
        case switchGames, steam, macApps, drive, nextendo, saves, images, programs = "prog", online

        public var title: IntegrationWords {
            switch self {
            case .switchGames: .init("nxnative")
            case .steam: .init("Steam")
            case .macApps: .init("Mac apps")
            case .drive: .init("Google Drive")
            case .nextendo: .init("Nextendo")
            case .saves: .init("iCloud saves")
            case .images: .init("Artwork and scores")
            case .programs: .init("Programs")
            case .online: .init("Game information online")
            }
        }

        public var capabilities: IntegrationWords {
            switch self {
            case .switchGames: .init("Build, play and keep saves")
            case .steam: .init("Installed games, play through Steam")
            case .macApps: .init("Shortcuts to local apps")
            case .drive: .init("Games and copies of your files")
            case .nextendo: .init("Online play and friends")
            case .saves: .init("Copies of game saves")
            case .images: .init("Covers, icons and game scores")
            case .programs: .init("Shortcuts to programs")
            case .online: .init("Covers and game information")
            }
        }
    }

    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case sources, engines, services

        public var id: Self { self }
        public var title: IntegrationWords {
            switch self {
            case .sources: .init("Sources")
            case .engines: .init("Engines")
            case .services: .init("Services")
            }
        }

        fileprivate var order: [ID] {
            switch self {
            case .sources: [.steam, .macApps, .programs, .drive]
            case .engines: [.switchGames]
            case .services: [.nextendo, .saves, .images, .online]
            }
        }
    }

    public struct Group<Entry>: Identifiable {
        public let id: Section
        public let entries: [Entry]
    }

    public static func sections<Entry>(offering entry: (ID) -> Entry?) -> [Group<Entry>] {
        Section.allCases.map { Group(id: $0, entries: $0.order.compactMap(entry)) }
    }

    public static let open = IntegrationWords("Open")
    public static let empty = IntegrationWords("Nothing available here")
    public static let off = IntegrationWords("Off")
    public static let ready = IntegrationWords("Ready here")
    public static let steamGames = IntegrationWords("Open Steam games")
    public static let notFound = IntegrationWords("Not found")
    public static let reads = IntegrationWords("Reads: %@")
    public static let writes = IntegrationWords("Writes: %@")
    public static let sends = IntegrationWords("Sends: %@")

    public enum Phase: String, Identifiable, Sendable {
        case link, verify, next

        public var id: Self { self }
        public var title: IntegrationWords {
            switch self {
            case .link: .init("Link")
            case .verify: .init("Verify")
            case .next: .init("Continue")
            }
        }
    }

    public struct Step<Content>: Identifiable {
        public let id: Phase
        public let content: [Content]
    }

    public static func steps<Content>(link: [Content] = [], verify: [Content] = [], next: [Content] = []) -> [Step<Content>] {
        [Step(id: .link, content: link), Step(id: .verify, content: verify), Step(id: .next, content: next)]
            .filter { !$0.content.isEmpty }
    }
}
