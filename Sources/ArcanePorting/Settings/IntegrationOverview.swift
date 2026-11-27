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

    public var barStatus: String { legacyStatus ?? status }
    public var barName: String { id == .switchGames ? "Switch (nxnative)" : name }

    public enum Detail {
        case words([IntegrationWords]), status, date(Date), access, action(IntegrationDetailAction)
    }

    public var steps: [IntegrationCatalog.Step<Detail>] {
        let check: [Detail] = [.status] + (checkDate.map { [.date($0)] } ?? []) + (checks.isEmpty ? [] : [.words(checks)]) + [.access]
        return IntegrationCatalog.steps(link: link ? [.action(.settings)] : [],
            verify: check + (browse != nil && !link ? [.action(.settings)] : []),
            next: browse.map { [.action($0)] } ?? (link ? [] : [.action(.settings)]))
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
    public var keysReady: Bool?
    public var xcodeVersion: String?
    public var metalVersion: String?
    public var engineGate: String?
    public var hasSwitchGames = false
    public var steam: CatalogSourceStatus = .disabled
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
        var checks: [IntegrationWords] = []
        if let expectedEngineCommit {
            checks.append(.init("Expected engine commit: %@", args: [String(expectedEngineCommit.prefix(8))]))
        }
        if let engineCommit {
            checks.append(.init("Observed engine commit: %@", args: [String(engineCommit.prefix(8))]))
        }
        if let keysReady {
            checks.append(.init(keysReady ? "Switch keys selected" : "Switch keys missing or invalid"))
        }
        if let xcodeVersion { checks.append(.verbatim(xcodeVersion)) }
        if let metalVersion { checks.append(.init("Metal compiler: %@", args: [metalVersion])) }
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
                         reads: "Selected game files, local keys and installed game apps.",
                         writes: "Game apps, build caches, logs and a private copy of imported keys. nxnative writes local saves.",
                         sends: "GitHub for engine downloads and updates; Apple for Metal downloads. Local porting does not upload game files or keys.",
                         settingID: engine == .blocked ? "engineStatus" : "engineFolder", link: engine == .notDetected,
                         checks: engineChecks + (engineGate.map { [.verbatim($0)] } ?? []), browse: hasSwitchGames ? .switchGames : nil)
        case .steam:
            // The same state as Settings › Sources shows, said for the overview (NXLibraryCore/Steam/SteamSourceEntries.swift).
            let state = SteamSourceEntries.state(steam, found: steamGameCount)
            let status = SteamSourceEntries.catalogueSummary(steam, found: steamGameCount).key
            return .init(id: id, purpose: "Find installed Mac games and open them in Steam.",
                         status: status, emphasis: state.emphasis, action: "Open Steam source settings",
                         reads: "Steam manifests, local play history and achievements.",
                         writes: "Oort NX catalog, play activity and local caches for metadata and achievements; no Steam files.",
                         sends: "Play sends the App ID to local Steam. Browsing sends IDs and language to the Steam store and requests achievement data and icons from Valve’s API and CDN.",
                         settingID: SteamSourceEntries.sourceID, link: steam == .disabled,
                         browse: steam == .ready && steamGameCount > 0 ? .steamGames : nil, legacyStatus: state.summary.key)
        case .macApps:
            return .init(id: id, purpose: "Add local Mac apps as library shortcuts.",
                         status: hasMacShortcuts ? "Mac shortcuts added" : "No Mac shortcuts added",
                         emphasis: .neutral, action: "Open Mac app settings",
                         reads: "The chosen Mac app’s name, location and icon.",
                         writes: "The shortcut in this library, not the app.",
                         sends: "No app information is sent online.",
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
            return .init(id: id, purpose: "Keep copies of ported apps, build caches or selected game files, not saves.",
                         status: state.0, emphasis: state.1, action: "Open cloud library settings",
                         reads: "Selected local files and Drive folders; the reference library is read-only.",
                         writes: "Local copies and rclone connection settings; uploads write to the personal library, not the reference.",
                         sends: "rclone exchanges OAuth credentials and tokens with Google and uploads files to Drive. New connections made here request full Drive access.",
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
                         reads: "Local sign-in token; Nextendo account, friends, avatars and online activity.",
                         writes: "A local refresh token; requested friend changes on Nextendo.",
                         sends: "Nextendo receives OAuth codes and tokens, friend actions and player or game IDs. Online play uses Nextendo; presence and current game depend on your settings.",
                         settingID: nextendo == .noLocalProfile ? "showProfilePicker" : "nextendo", link: nextendo == .noLocalProfile || nextendo == .expired)
        case .images:
            let state: String
            switch (steamGridDB, igdb) {
            case (true, true): state = "Both providers configured"
            case (true, false): state = "Only SteamGridDB configured"
            case (false, true): state = "Only IGDB configured"
            case (false, false): state = "No provider credentials"
            }
            return .init(id: id, purpose: "Configure SteamGridDB and IGDB. Automatic icons and scores also use public sources.",
                         status: state, emphasis: .neutral, action: "Open provider settings",
                         reads: "Game titles or IDs and provider results.",
                         writes: "Private API credentials, artwork preferences, saved images and cached scores on this Mac.",
                         sends: "Searches and key to SteamGridDB; searches, client ID and access token to IGDB; client ID and secret to Twitch. Game names or Steam IDs to Wikidata, title IDs to Nlib and game names to Switch Icon Showdown.",
                         settingID: steamGridDB && !igdb ? "igdb" : "steamGridDB", link: !steamGridDB && !igdb)
        case .saves:
            let state = switch saves {
            case .off: "Cloud saves off"
            case .iCloudDrive: "iCloud Drive selected"
            case .folder: "Custom save folder selected"
            }
            return .init(id: id, purpose: "Keep supported game saves in iCloud Drive or in a folder you choose.",
                         status: state, emphasis: .neutral, action: "Open cloud save settings",
                         reads: "The primary user and device saves and their copies in the chosen folder.",
                         writes: "Oort creates the folder and sets each game’s preference. nxnative writes the copies; a game-specific setting can override the global choice.",
                         sends: "Oort does not upload saves directly. iCloud Drive syncs to Apple; other folders depend on their sync client.",
                         settingID: "cloudSaves", link: saves == .off)
        case .programs, .online:
            return nil
        }
    }
}
