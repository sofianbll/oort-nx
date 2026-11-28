import Foundation

/// Steam as its owner observes it on this system: never a decision. The status, its tone, Link and Continue are
/// decided once from these facts (`IntegrationFacts.row`), the same on every system.
public struct SteamFacts: Equatable, Sendable {
    /// The choice in force: what the switch shows and what X turns into its opposite.
    public var enabled = false
    /// Whether Steam is on this computer; nil where the system does not look for it apart from reading it.
    public var found: Bool? = nil
    /// The last reading of its libraries.
    public var read: CatalogSourceStatus = .disabled
    /// The games read.
    public var games = 0

    public init(enabled: Bool = false, found: Bool? = nil, read: CatalogSourceStatus = .disabled, games: Int = 0) {
        (self.enabled, self.found, self.read, self.games) = (enabled, found, read, games)
    }
}

/// Game information online as its owner observes it.
public struct OnlineFacts: Equatable, Sendable {
    public var on = false
    /// Games whose information was found online.
    public var known = 0

    public init(on: Bool = false, known: Int = 0) { (self.on, self.known) = (on, known) }
}

/// What the owners of the integrations observe, and what the system offers and announces: facts only. Each app fills
/// them from its owners (the Mac: IntegrationSurface); `row` decides each entry from them once, and IntegrationScreen
/// lays the screens out. No I/O or persisted state.
public struct IntegrationFacts: Equatable, Sendable {
    public enum Engine: CaseIterable, Sendable { case notDetected, checking, detected, blocked }
    public enum Drive: CaseIterable, Sendable { case notConfigured, off, unchecked, checked, checking, transferring, paused, failed }
    public enum Account: CaseIterable, Sendable { case noLocalProfile, unchecked, connected, expired, checking, unavailable }
    /// Why new builds are blocked, said plainly; the details stay in the engine settings.
    public enum BuildBlock: CaseIterable, Sendable { case appleTools, buildTools, engineVersion }
    public enum Saves: Equatable, Sendable { case off, iCloudDrive, folder }
    /// The Switch keys the engine is given; `invalid` says the problem in the player's words.
    public enum Keys: Equatable, Sendable { case selected, missing, invalid(String) }

    /// The entries this system offers: a fact of the system, never a case of it.
    public var offers: Set<IntegrationID> = []
    /// Ryujinx-Nextendo is announced where it will run.
    public var announcesRyujinx = false
    /// The system has a settings row for each entry it offers (Settings › Sources, Engine…).
    public var settingsRows = false

    public var engine: Engine = .notDetected
    public var engineCommit: String?
    public var expectedEngineCommit: String?
    public var keys: Keys?
    public var xcodeVersion: String?
    public var metalVersion: String?
    public var buildBlock: BuildBlock?
    /// The installed Metal compiler against the one the engine tested; nil until the engine check ran.
    public var appleToolsTested: Bool?
    public var hasSwitchGames = false
    public var steam = SteamFacts()
    public var hasMacShortcuts = false
    public var programs = 0
    public var online = OnlineFacts()
    public var drive: Drive = .notConfigured
    public var driveCheckDate: Date?
    public var nextendo: Account = .noLocalProfile
    public var steamGridDB = false
    public var igdb = false
    public var saves: Saves = .off
    public init() {}

    // Keep the library shortcut's attention priority independent of the catalogue order.
    public var rows: [IntegrationRow] { IntegrationID.allCases.compactMap(row) }
    public var sections: [IntegrationCatalog.Group<IntegrationRow>] {
        IntegrationCatalog.sections(announcingRyujinx: announcesRyujinx, offering: row)
    }

    private var engineChecks: [IntegrationWords] {
        // Said plainly; the versions themselves stay in the engine settings (Open engine settings).
        var checks: [IntegrationWords] = []
        // The same engine when one names the other in full or by a prefix Git accepts (seven characters or more).
        if let engineCommit, let expectedEngineCommit, min(engineCommit.count, expectedEngineCommit.count) >= 7 {
            let (short, long) = engineCommit.count <= expectedEngineCommit.count ? (engineCommit, expectedEngineCommit) : (expectedEngineCommit, engineCommit)
            checks.append(long.lowercased().hasPrefix(short.lowercased()) ? .init("Engine up to date") : .init("Engine not the tested version"))
        }
        switch keys {
        case .selected?: checks.append(.init("Switch keys selected"))
        case .missing?: checks.append(.init("Switch keys missing"))
        case .invalid(let message)?: checks.append(.verbatim(message))
        case nil: break
        }
        switch (buildBlock == .appleTools || appleToolsTested == false, xcodeVersion, metalVersion) {
        case (true, _, _): checks.append(.init("Apple tools not the tested version"))
        case (_, nil, nil): break
        case (_, _?, _?): checks.append(.init("Apple tools ready"))
        default: checks.append(.init("Apple tools incomplete"))
        }
        if buildBlock == .buildTools { checks.append(.init("Build tools incomplete")) }
        if buildBlock != nil { checks.append(.init("The details are in the engine settings.")) }
        return checks
    }

    /// One entry, decided once from the facts; nil when the system does not offer it. Its settings are offered only
    /// where the system has settings rows.
    public func row(_ id: IntegrationID) -> IntegrationRow? {
        guard offers.contains(id), var row = decided(id) else { return nil }
        if row.manage?.target == .settings, !settingsRows { row.manage = nil }
        return row
    }

    private func decided(_ id: IntegrationID) -> IntegrationRow? {
        switch id {
        case .switchGames:
            let state: (String, IntegrationEmphasis) = switch engine {
            case .notDetected: ("Engine not detected", .neutral)
            case .checking: ("Checking the build environment…", .working)
            case .detected: ("Engine folder found", .neutral)
            case .blocked: ("New builds blocked", .attention)
            }
            return .init(id: id, purpose: "Build compatible Switch games for Mac and open games already built.",
                         status: state.0, emphasis: state.1, action: "Open engine settings",
                         reads: "The game files you choose, your Switch keys and the games already built.",
                         writes: "The games it builds, its working files and a private copy of your keys. The games write their own saves.",
                         sends: "Never your games or your keys. It only downloads its updates from GitHub and Apple’s tools from Apple.",
                         settingID: engine == .blocked ? "engineStatus" : "engineFolder", link: engine == .notDetected,
                         checks: engineChecks, browse: hasSwitchGames ? .init("Open Switch games", .switchGames) : nil)
        case .steam:
            // The same state as Settings › Sources shows, said for the overview (OortLibrary/Steam/SteamSourceEntries.swift).
            let state = SteamSourceEntries.state(steam.read, found: steam.games)
            let missing = steam.found == false
            let status = missing ? IntegrationCatalog.notFound.key : SteamSourceEntries.catalogueSummary(steam.read, found: steam.games).key
            return .init(id: id, purpose: "Find installed Mac games and open them in Steam.",
                         status: status, emphasis: missing ? .neutral : state.emphasis, action: "Open Steam source settings",
                         reads: "The games Steam installed, your play time and your achievements.",
                         writes: "Your Oort NX library and the pictures it keeps; never Steam’s files.",
                         sends: "Play tells Steam on this computer which game to start. While you browse, Oort sends Steam each game’s number and your language to get its pictures, information and achievements.",
                         settingID: SteamSourceEntries.sourceID, link: steam.read == .disabled || missing,
                         browse: steam.read == .ready && steam.games > 0 && !missing ? .init(IntegrationCatalog.steamGames.key, .steamGames) : nil,
                         legacyStatus: missing ? nil : state.summary.key,
                         switchOn: steam.enabled, linked: steam.enabled && steam.read != .failed && !missing,
                         says: !steam.enabled ? nil : missing ? IntegrationCatalog.steamMissing : steam.read == .failed ? state.detail : nil)
        case .macApps:
            return .init(id: id, purpose: "Add local Mac apps as library shortcuts.",
                         status: hasMacShortcuts ? "Mac shortcuts added" : "No Mac shortcuts added",
                         emphasis: .neutral, action: "Open Mac app settings",
                         reads: "The name, place and icon of the app you choose.",
                         writes: "A shortcut in your library; the app itself does not change.",
                         sends: "Nothing",
                         settingID: "macShortcutAdd", link: !hasMacShortcuts)
        case .programs:
            // Linked when not empty, as Mac apps: the programs' page is where they are added and kept.
            return .init(id: id, purpose: "Any program with its arguments, an emulator with a game for example. Sends nothing.",
                         status: programs == 0 ? "No programs added" : IntegrationCatalog.ready.key, emphasis: .neutral,
                         action: "Open programs", reads: "The chosen program’s name, location and icon.",
                         writes: "The shortcut in this library, not the program.", sends: "Nothing",
                         settingID: nil, link: programs == 0, manageTarget: .programs)
        case .online:
            return .init(id: id, purpose: IntegrationCatalog.ID.online.capabilities.key,
                         status: online.on ? "On" : IntegrationCatalog.off.key, emphasis: .neutral, action: nil,
                         reads: "Your game names, or their Steam number.",
                         writes: "Covers and information, kept on this computer.",
                         sends: "Your game names, or their Steam number, and your language, to the Steam store, Wikipedia and Wikidata.",
                         settingID: nil, link: !online.on,
                         checks: online.on ? [.init("%lld games known", count: online.known)] : [],
                         switchOn: online.on, clears: online.known > 0)
        case .drive:
            let state: (String, IntegrationEmphasis) = switch drive {
            case .notConfigured: ("Drive not connected", .neutral)
            case .off: ("Cloud library off", .neutral)
            case .unchecked: ("Connection not tested", .neutral)
            case .checked: ("Last Drive check succeeded", .neutral)
            case .checking: ("Checking Google Drive…", .working)
            case .transferring: ("Drive transfer in progress", .working)
            case .paused: ("Drive transfer paused", .attention)
            case .failed: ("Drive check failed", .attention)
            }
            let setting = switch drive {
            case .notConfigured: "cloudLibrarySetup"
            case .off: "cloudLibraryEnabled"
            case .failed: "cloudLibraryService"
            case .paused: "cloudLibraryAdvanced"
            default: "cloudLibraryEnabled"
            }
            return .init(id: id, purpose: "Keep copies of your built games and of the game files you choose. Not your saves.",
                         status: state.0, emphasis: state.1, action: "Open cloud library settings",
                         reads: "The files you choose and your Drive folders. The shared library is only read.",
                         writes: "Copies on this computer and in your own Drive library, never in the shared one.",
                         sends: "Your files to your Google Drive, and your Google sign-in. A new connection asks for access to your whole Drive.",
                         settingID: setting, link: drive == .notConfigured, checkDate: drive == .checked || drive == .failed ? driveCheckDate : nil)
        case .nextendo:
            let state: (String, IntegrationEmphasis) = switch nextendo {
            case .noLocalProfile: ("No local profile for Nextendo", .neutral)
            case .unchecked: ("Nextendo connection not verified", .neutral)
            case .connected: ("Nextendo signed in", .neutral)
            case .expired: ("Nextendo sign-in expired", .attention)
            case .checking: ("Nextendo account operation in progress", .working)
            case .unavailable: ("Nextendo unavailable", .attention)
            }
            let says: IntegrationWords? = switch nextendo {
            case .unavailable: .init("Nextendo cannot be reached right now.")
            // Not checked in this session, or being checked: maybe signed in, maybe not.
            case .unchecked, .checking: .init("Account not checked yet: open the Nextendo settings.")
            default: nil
            }
            return .init(id: id, purpose: "Play compatible nxnative games online and see your Nextendo friends.",
                         status: state.0, emphasis: state.1,
                         action: nextendo == .noLocalProfile ? "Open profile settings" : "Open Nextendo settings",
                         reads: "Your Nextendo account, your friends, their pictures and who is online.",
                         writes: "Your sign-in on this computer, and the friend changes you ask for.",
                         sends: "To Nextendo: your sign-in, your friend requests, that you are online in the app, and the game you play online. What your friends see depends on your settings.",
                         settingID: nextendo == .noLocalProfile ? "showProfilePicker" : "nextendo", link: nextendo == .noLocalProfile || nextendo == .expired,
                         linked: nextendo == .connected, says: says)
        case .images:
            let state: String
            switch (steamGridDB, igdb) {
            case (true, true): state = "Both providers configured"
            case (true, false): state = "Only SteamGridDB configured"
            case (false, true): state = "Only IGDB configured"
            case (false, false): state = "No provider credentials"
            }
            return .init(id: id, purpose: "Add your SteamGridDB and IGDB keys. Icons and scores also come from public sites.",
                         status: state, emphasis: .neutral, action: "Open provider settings",
                         reads: "Your game names or numbers and what the sites find.",
                         writes: "Your keys, kept private, your picture choices, and the pictures and scores it keeps.",
                         sends: "Your game names or numbers to SteamGridDB, IGDB, Wikidata, Nlib, Nintendo, LaunchBox, GameTDB and Switch Icon Showdown, and your keys to the sites that need them (SteamGridDB, IGDB through Twitch).",
                         settingID: steamGridDB && !igdb ? "igdb" : "steamGridDB", link: !steamGridDB && !igdb)
        case .saves:
            let state = switch saves {
            case .off: "Cloud saves off"
            case .iCloudDrive: "iCloud Drive selected"
            case .folder: "Custom save folder selected"
            }
            return .init(id: id, purpose: "Keep supported game saves in iCloud Drive or in a folder you choose.",
                         status: state, emphasis: .neutral, action: "Open cloud save settings",
                         reads: "The game saves on this computer and their copies in the folder you chose.",
                         writes: "The folder and each game’s choice; the games write the copies. A game can keep its own choice.",
                         sends: "Nothing directly. iCloud Drive syncs with Apple; another folder, with its own app.",
                         settingID: "cloudSaves", link: saves == .off)
        }
    }
}

/// One integration as the core decides it from the facts: what it says, how much it needs the player, what links it
/// and what comes next. IntegrationScreen lays it out; the home bar of the Mac shows its status.
public struct IntegrationRow: Identifiable, Sendable {
    /// A gesture's words and the owner's target it asks for.
    public struct Action: Equatable, Sendable {
        public let title: String
        public let target: IntegrationTarget
        public init(_ title: String, _ target: IntegrationTarget) { (self.title, self.target) = (title, target) }
    }

    public let id: IntegrationID
    public var name: String { id.title.key }
    public let purpose: String
    public let status: String
    public let emphasis: IntegrationEmphasis
    public let reads: String
    public let writes: String
    public let sends: String
    /// The settings row that keeps the entry; nil on an entry without one.
    public let settingID: String?
    /// Where the entry is kept (its settings, the programs' page): nil when it has none on this system.
    public internal(set) var manage: Action?
    /// Nothing links it yet: Link holds `manage`.
    public let needsLink: Bool
    public let checkDate: Date?
    public let checks: [IntegrationWords]
    /// What it opens once linked (its games, its programs).
    public let browse: Action?
    let legacyStatus: String?
    /// On or off, for an entry whose owner offers a switch (IntegrationCatalog.ID.hasSwitch); nil otherwise.
    public let switchOn: Bool?
    /// The owner's fact for Link, when it is not just « nothing to link » (Nextendo signed in, Steam on and read).
    public let linked: Bool
    /// Link's sentence, when the owner knows better than linked/not linked.
    public let says: IntegrationWords?
    /// Verify offers to delete what the owner found (information online), after a question.
    public let clears: Bool

    public var barStatus: String { legacyStatus ?? status }
    public var barName: String { id == .switchGames ? "Switch (nxnative)" : name }

    init(id: IntegrationID, purpose: String, status: String, emphasis: IntegrationEmphasis, action: String?, reads: String,
         writes: String, sends: String, settingID: String?, link: Bool, checkDate: Date? = nil, checks: [IntegrationWords] = [],
         browse: Action? = nil, legacyStatus: String? = nil, switchOn: Bool? = nil, linked: Bool? = nil,
         says: IntegrationWords? = nil, manageTarget: IntegrationTarget = .settings, clears: Bool = false) {
        (self.id, self.purpose, self.status, self.emphasis, self.reads, self.writes, self.sends) = (id, purpose, status, emphasis, reads, writes, sends)
        (self.settingID, self.needsLink, self.checkDate, self.checks, self.browse) = (settingID, link, checkDate, checks, browse)
        (self.legacyStatus, self.switchOn, self.linked, self.says, self.clears) = (legacyStatus, switchOn, linked ?? !link, says, clears)
        manage = action.map { Action($0, manageTarget) }
    }
}
