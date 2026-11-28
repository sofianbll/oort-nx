/// The catalogue order and words are shared. Each owner supplies only the installed offers and their observed state
/// (IntegrationFacts); IntegrationScreen lays the screens out; a renderer neither classifies an integration nor
/// invents a missing capability.
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

        /// An entry its owner turns on and off shows its switch on the catalogue row, as before the catalogue. A still
        /// opens the detail; X, or a click on the switch, asks the owner for the other state without leaving the list.
        /// The same switch is the Link step of the detail.
        public var hasSwitch: Bool { self == .steam || self == .online }

        /// Turned on from the list, it starts sending at once: while it is off, its row says what it does and sends
        /// instead of its capabilities, as its question does elsewhere, so X never turns it on unexplained.
        public var explainsBeforeOn: Bool { self == .online }

        /// The Link step says what the entry is linked to, or how to link it.
        public func link(_ linked: Bool) -> IntegrationWords {
            switch (self, linked) {
            case (.switchGames, true): .init("Linked to the nxnative engine on this computer.")
            case (.switchGames, false): .init("Choose the engine folder to begin.")
            case (.steam, true): .init("Linked to Steam on this computer.")
            case (.steam, false): .init("Turn on Steam to add the games it installed.")
            case (.macApps, true): .init("Linked to the Mac apps you added.")
            case (.macApps, false): .init("Add a Mac app to begin.")
            case (.drive, true): .init("Linked to your Google Drive.")
            case (.drive, false): .init("Connect your Google Drive to begin.")
            case (.nextendo, true): .init("Linked to your Nextendo account.")
            case (.nextendo, false): .init("Sign in to Nextendo to begin.")
            case (.saves, true): .init("Linked to the save folder you chose.")
            case (.saves, false): .init("Choose iCloud Drive or a folder to begin.")
            case (.images, true): .init("Linked with your SteamGridDB or IGDB key.")
            case (.images, false): .init("Add a SteamGridDB or IGDB key to begin.")
            case (.programs, true): .init("Linked to the programs you added.")
            case (.programs, false): .init("Add a program to begin.")
            case (.online, true): .init("Linked to the Steam store, Wikipedia and Wikidata.")
            case (.online, false): .init("Turn it on to look for covers and game information.")
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

        /// Announced, not offered: one quiet line under the section, never a row. Ryujinx-Nextendo is announced only
        /// where it will run (a fact of the system).
        public func upcoming(announcingRyujinx ryujinx: Bool) -> [String] {
            switch self {
            case .sources: ["Epic Games", "GOG", "Minecraft", "CrossOver"]
            case .engines: ryujinx ? ["Ryujinx-Nextendo"] : []
            case .services: []
            }
        }
    }

    public struct Group<Entry>: Identifiable {
        public let id: Section
        public let entries: [Entry]
        /// « Coming later: … », or nil when nothing is announced in this section on this host.
        public let upcoming: IntegrationWords?
    }

    /// A section shows its offers and what it announces on this system; one with neither is left out, so none is
    /// ever empty.
    public static func sections<Entry>(announcingRyujinx ryujinx: Bool, offering entry: (ID) -> Entry?) -> [Group<Entry>] {
        Section.allCases.map { section in
            let coming = section.upcoming(announcingRyujinx: ryujinx)
            return Group(id: section, entries: section.order.compactMap(entry),
                         upcoming: coming.isEmpty ? nil : .init("Coming later: %@", args: [coming.joined(separator: " · ")]))
        }
        .filter { !$0.entries.isEmpty || $0.upcoming != nil }
    }

    public static let open = IntegrationWords("Open")
    public static let off = IntegrationWords("Off")
    public static let ready = IntegrationWords("Ready here")
    public static let steamGames = IntegrationWords("Open Steam games")
    public static let notFound = IntegrationWords("Not found")
    public static let reads = IntegrationWords("Reads: %@")
    public static let writes = IntegrationWords("Writes: %@")
    public static let sends = IntegrationWords("Sends: %@")
    /// Link, when Steam is on but cannot be found or read here.
    public static let steamMissing = IntegrationWords("Steam was not found on this computer.")

    /// What X does on a row with a switch, said for its current state.
    public static func toggle(on: Bool) -> IntegrationWords { on ? .init("Turn off") : .init("Turn on") }

    /// The detail's boxes, in this order: Link, Verify, Continue.
    public static let link = IntegrationWords("Link")
    public static let verify = IntegrationWords("Verify")
    public static let next = IntegrationWords("Continue")
    /// Continue, when it has no action.
    public static func rest(linked: Bool) -> IntegrationWords {
        linked ? .init("Nothing else to do here: it works on its own.") : .init("Link it first to continue.")
    }

    /// What information online does and sends: under its switch while it is off, and in the question asked before
    /// it is on (its consent depends on it: never truncated).
    public static let onlineAbout = IntegrationWords("Oort NX looks for each game’s cover, description, year and genres on the Steam store, Wikipedia and Wikidata. It sends the game’s name, or its Steam number, and your language. Like any site, they see your internet address. No account, no key, and nothing else leaves this computer.")
    public static let clearOnline = IntegrationWords("Delete what was found online")
    public static let clearOnlineQuestion = IntegrationWords("Delete what was found online?")
    public static let clearOnlineMessage = IntegrationWords("Covers and descriptions found online leave this computer. Your own pictures stay.")
}
