import Foundation
import NXLibraryCore

public struct IntegrationRow: Identifiable {
    public let id: IntegrationID
    public var name: String { id.title.key }
    public let purpose: String
    public let status: String
    public let emphasis: IntegrationEmphasis
    public let action: String
    public let reads: String
    public let writes: String
    public let sends: String
    fileprivate let settingID: String
    fileprivate var link = false
    fileprivate var checkDate: Date? = nil
    fileprivate var checks: [IntegrationWords] = []
    fileprivate var browse: IntegrationDetailAction? = nil
    fileprivate var legacyStatus: String? = nil

    /// On or off, for an entry whose owner offers a switch (IntegrationCatalog.ID.hasSwitch); nil otherwise.
    public var switchOn: Bool? = nil
    /// The owner's fact for Link, when it is not just « nothing to link » (Nextendo signed in, Steam on and read).
    fileprivate var linked: Bool? = nil
    /// Link's sentence, when the owner knows better than linked/not linked.
    fileprivate var says: IntegrationWords? = nil

    public var barStatus: String { legacyStatus ?? status }
    public var barName: String { id == .switchGames ? "Switch (nxnative)" : name }

    public enum Detail {
        case say(IntegrationWords), words([IntegrationWords]), status, date(Date), access, action(IntegrationDetailAction)
    }

    /// Link holds the settings while the entry needs linking, or when Continue has its own action; else Continue does.
    public var steps: [IntegrationCatalog.Step<Detail>] {
        let check: [Detail] = [.status] + (checkDate.map { [.date($0)] } ?? []) + (checks.isEmpty ? [] : [.words(checks)]) + [.access]
        let settingsInLink = link || browse != nil
        return IntegrationCatalog.steps(id, linked: linked ?? !link, says: says, link: settingsInLink ? [.action(.settings)] : [], verify: check,
            next: browse.map { [.action($0)] } ?? (settingsInLink ? [] : [.action(.settings)]), say: Detail.say)
    }

    public var actions: [IntegrationDetailAction] {
        steps.flatMap(\.content).compactMap { if case .action(let action) = $0 { action } else { nil } }
    }

    public func title(of action: IntegrationDetailAction) -> String {
        switch action {
        case .settings: self.action
        case .switchGames: "Open Switch games"
        case .steamGames: IntegrationCatalog.steamGames.key
        }
    }
}

/// A disposable projection of facts already held by the individual owners. No I/O or persisted state.
public struct IntegrationOverview {
    public enum Engine: CaseIterable { case notDetected, checking, detected, blocked }
    public enum Drive: CaseIterable { case notConfigured, off, unchecked, checked, checking, transferring, paused, failed }
    public enum Account: CaseIterable { case noLocalProfile, unchecked, connected, expired, checking, unavailable }
    public var engine: Engine = .notDetected
    public var engineCommit: String?
    public var expectedEngineCommit: String?
    public var keyStatus: LocalKeyStatus?
    public var xcodeVersion: String?
    public var metalVersion: String?
    /// Why new builds are blocked, said plainly; the details stay in the engine settings.
    public enum BuildBlock: CaseIterable { case appleTools, buildTools, engineVersion }
    public var buildBlock: BuildBlock?
    /// The installed Metal compiler against the one the engine tested; nil until the engine check ran.
    public var appleToolsTested: Bool?

    /// What blocks new builds, from the engine check's blocking lines: Metal is Apple's tools; a commit alone is the
    /// engine's version (already said by its own line); anything else is the build tools. The override lets it pass.
    public static func buildBlock(_ report: CompatibilityReport?, canPass: Bool, canBuild: Bool?) -> BuildBlock? {
        if let report, !canPass {
            let blocking = Set(report.checks.filter { $0.status == .block }.map(\.id))
            if blocking.contains("metal") { return .appleTools }
            if !blocking.subtracting(["commit"]).isEmpty { return .buildTools }
            if !blocking.isEmpty { return .engineVersion }
        }
        return canBuild == false ? .buildTools : nil
    }
    public var hasSwitchGames = false
    public var steam: CatalogSourceStatus = .disabled
    /// The source's choice in force: what Steam's switch shows and what X turns into its opposite.
    public var steamEnabled = false
    public var steamGameCount = 0
    public var hasMacShortcuts = false
    public var drive: Drive = .notConfigured
    public var driveCheckDate: Date?
    public var nextendo: Account = .noLocalProfile
    public var steamGridDB = false
    public var igdb = false
    public var saves: CloudSaves = .off
    public init() {}

    // Keep the library shortcut's attention priority independent of the catalogue order.
    public var rows: [IntegrationRow] { IntegrationID.allCases.compactMap(row) }
    public var sections: [IntegrationCatalog.Group<IntegrationRow>] { IntegrationCatalog.sections(offering: row) }

    private var engineChecks: [IntegrationWords] {
        // Said plainly; the versions themselves stay in the engine settings (Open engine settings).
        var checks: [IntegrationWords] = []
        // The same engine when one names the other in full or by a prefix Git accepts (seven characters or more).
        if let engineCommit, let expectedEngineCommit, min(engineCommit.count, expectedEngineCommit.count) >= 7 {
            let (short, long) = engineCommit.count <= expectedEngineCommit.count ? (engineCommit, expectedEngineCommit) : (expectedEngineCommit, engineCommit)
            checks.append(long.lowercased().hasPrefix(short.lowercased()) ? .init("Engine up to date") : .init("Engine not the tested version"))
        }
        switch keyStatus {
        case .available?: checks.append(.init("Switch keys selected"))
        case .required?: checks.append(.init("Switch keys missing"))
        case .invalid(let issue)?: checks.append(.verbatim(issue.message))
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

    /// The setting is declared in the same catalog as Search and Changed. Never activates the setting.
    @discardableResult
    public func open(_ id: IntegrationID, in router: AppRouter) -> Bool {
        guard router.route == .integrations,
              let row = row(id), let setting = SettingsCatalog.all.first(where: { $0.id == row.settingID })
        else { return false }
        router.integrationFocus = id
        router.openSettings(setting.group, rowID: setting.id)
        return true
    }

    public func row(_ id: IntegrationID) -> IntegrationRow? {
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
                         checks: engineChecks, browse: hasSwitchGames ? .switchGames : nil)
        case .steam:
            // The same state as Settings › Sources shows, said for the overview (NXLibraryCore/Steam/SteamSourceEntries.swift).
            let state = SteamSourceEntries.state(steam, found: steamGameCount)
            let status = SteamSourceEntries.catalogueSummary(steam, found: steamGameCount).key
            return .init(id: id, purpose: "Find installed Mac games and open them in Steam.",
                         status: status, emphasis: state.emphasis, action: "Open Steam source settings",
                         reads: "The games Steam installed, your play time and your achievements.",
                         writes: "Your Oort NX library and the pictures it keeps; never Steam’s files.",
                         sends: "Play tells Steam on this computer which game to start. While you browse, Oort sends Steam each game’s number and your language to get its pictures, information and achievements.",
                         settingID: SteamSourceEntries.sourceID, link: steam == .disabled,
                         browse: steam == .ready && steamGameCount > 0 ? .steamGames : nil, legacyStatus: state.summary.key,
                         switchOn: steamEnabled, linked: steamEnabled && steam != .failed,
                         says: steamEnabled && steam == .failed ? state.detail : nil)
        case .macApps:
            return .init(id: id, purpose: "Add local Mac apps as library shortcuts.",
                         status: hasMacShortcuts ? "Mac shortcuts added" : "No Mac shortcuts added",
                         emphasis: .neutral, action: "Open Mac app settings",
                         reads: "The name, place and icon of the app you choose.",
                         writes: "A shortcut in your library; the app itself does not change.",
                         sends: "Nothing",
                         settingID: "macShortcutAdd", link: !hasMacShortcuts)
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
            return .init(id: id, purpose: "Play compatible nxnative games online and see your Nextendo friends.",
                         status: state.0, emphasis: state.1,
                         action: nextendo == .noLocalProfile ? "Open profile settings" : "Open Nextendo settings",
                         reads: "Your Nextendo account, your friends, their pictures and who is online.",
                         writes: "Your sign-in on this computer, and the friend changes you ask for.",
                         sends: "To Nextendo: your sign-in, your friend requests, that you are online in the app, and the game you play online. What your friends see depends on your settings.",
                         settingID: nextendo == .noLocalProfile ? "showProfilePicker" : "nextendo", link: nextendo == .noLocalProfile || nextendo == .expired,
                         linked: nextendo == .connected, says: switch nextendo {
                             case .unavailable: .init("Nextendo cannot be reached right now.")
                             // Not checked in this session, or being checked: maybe signed in, maybe not.
                             case .unchecked, .checking: .init("Account not checked yet: open the Nextendo settings.")
                             default: nil
                         })
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
        case .programs, .online:
            return nil
        }
    }
}
