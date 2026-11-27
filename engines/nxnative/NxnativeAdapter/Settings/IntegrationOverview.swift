import NXLibraryCore

public struct IntegrationRow: Identifiable {
    public enum Emphasis { case neutral, working, attention }
    public let id: IntegrationID
    public let name: String
    public let purpose: String
    public let status: String
    public let emphasis: Emphasis
    public let action: String
    public let reads: String
    public let writes: String
    public let sends: String
    fileprivate let settingID: String
}

/// A disposable projection of facts already held by the individual owners. No I/O or persisted state.
public struct IntegrationOverview {
    public enum Engine: CaseIterable { case notDetected, checking, detected, blocked }
    public enum Drive: CaseIterable { case notConfigured, off, unchecked, checked, checking, transferring, paused, failed }
    public enum Account: CaseIterable { case noLocalProfile, unchecked, connected, expired, checking, unavailable }
    public var engine: Engine = .notDetected
    public var steam: CatalogSourceStatus = .disabled
    public var steamGameCount = 0
    public var hasMacShortcuts = false
    public var drive: Drive = .notConfigured
    public var nextendo: Account = .noLocalProfile
    public var steamGridDB = false
    public var igdb = false
    public var saves: CloudSaves = .off
    public init() {}

    public var rows: [IntegrationRow] { IntegrationID.allCases.map(row) }

    /// The setting is declared in the same catalog as Search and Changed. Never activates the setting.
    @discardableResult
    public func open(_ id: IntegrationID, in router: AppRouter) -> Bool {
        guard router.route == .integrations,
              let setting = SettingsCatalog.all.first(where: { $0.id == row(id).settingID })
        else { return false }
        router.integrationFocus = id
        router.openSettings(setting.group, rowID: setting.id)
        return true
    }

    public func row(_ id: IntegrationID) -> IntegrationRow {
        switch id {
        case .switchGames:
            let state: (String, IntegrationRow.Emphasis) = switch engine {
            case .notDetected: ("Engine not detected", .neutral)
            case .checking: ("Checking the build environment…", .working)
            case .detected: ("Engine folder found", .neutral)
            case .blocked: ("New builds blocked", .attention)
            }
            return .init(id: id, name: "Switch (nxnative)", purpose: "Build compatible Switch games for Mac and open games already built.",
                         status: state.0, emphasis: state.1, action: "Open engine settings",
                         reads: "Selected game files, local keys and installed game apps.",
                         writes: "Game apps, build caches, logs and a private copy of imported keys. nxnative writes local saves.",
                         sends: "GitHub for engine downloads and updates; Apple for Metal downloads. Local porting does not upload game files or keys.",
                         settingID: engine == .blocked ? "engineStatus" : "engineFolder")
        case .steam:
            let state: (String, IntegrationRow.Emphasis) = switch steam {
            case .disabled: ("Steam source off", .neutral)
            case .idle: ("Steam not scanned yet", .neutral)
            case .scanning: ("Reading Steam libraries…", .working)
            case .ready: (steamGameCount == 0 ? "No games found" : "Steam library scanned", .neutral)
            case .partial: ("Steam scan incomplete", .attention)
            case .cancelled: ("Steam scan cancelled", .attention)
            case .failed: ("Steam scan failed", .attention)
            }
            return .init(id: id, name: "Steam", purpose: "Find installed Mac games and open them in Steam.",
                         status: state.0, emphasis: state.1, action: "Open Steam source settings",
                         reads: "Steam manifests, local play history and achievements.",
                         writes: "Oort NX catalog, play activity and local caches for metadata and achievements; no Steam files.",
                         sends: "Play sends the App ID to local Steam. Browsing sends IDs and language to the Steam store and requests achievement data and icons from Valve’s API and CDN.",
                         settingID: "steamSource")
        case .macApps:
            return .init(id: id, name: "Mac apps", purpose: "Add local Mac apps as library shortcuts.",
                         status: hasMacShortcuts ? "Mac shortcuts added" : "No Mac shortcuts added",
                         emphasis: .neutral, action: "Open Mac app settings",
                         reads: "The chosen Mac app’s name, location and icon.",
                         writes: "The shortcut in this library, not the app.",
                         sends: "No app information is sent online.",
                         settingID: "macShortcutAdd")
        case .drive:
            let state: (String, IntegrationRow.Emphasis) = switch drive {
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
            return .init(id: id, name: "Google Drive", purpose: "Keep copies of ported apps, build caches or selected game files, not saves.",
                         status: state.0, emphasis: state.1, action: "Open cloud library settings",
                         reads: "Selected local files and Drive folders; the reference library is read-only.",
                         writes: "Local copies and rclone connection settings; uploads write to the personal library, not the reference.",
                         sends: "rclone exchanges OAuth credentials and tokens with Google and uploads files to Drive. New connections made here request full Drive access.",
                         settingID: setting)
        case .nextendo:
            let state: (String, IntegrationRow.Emphasis) = switch nextendo {
            case .noLocalProfile: ("No local profile for Nextendo", .neutral)
            case .unchecked: ("Nextendo connection not verified", .neutral)
            case .connected: ("Nextendo signed in", .neutral)
            case .expired: ("Nextendo sign-in expired", .attention)
            case .checking: ("Nextendo account operation in progress", .working)
            case .unavailable: ("Nextendo unavailable", .attention)
            }
            return .init(id: id, name: "Nextendo", purpose: "Play compatible nxnative games online and see your Nextendo friends.",
                         status: state.0, emphasis: state.1,
                         action: nextendo == .noLocalProfile ? "Open profile settings" : "Open Nextendo settings",
                         reads: "Local sign-in token; Nextendo account, friends, avatars and online activity.",
                         writes: "A local refresh token; requested friend changes on Nextendo.",
                         sends: "Nextendo receives OAuth codes and tokens, friend actions and player or game IDs. Online play uses Nextendo; presence and current game depend on your settings.",
                         settingID: nextendo == .noLocalProfile ? "showProfilePicker" : "nextendo")
        case .images:
            let state: String
            switch (steamGridDB, igdb) {
            case (true, true): state = "Both providers configured"
            case (true, false): state = "Only SteamGridDB configured"
            case (false, true): state = "Only IGDB configured"
            case (false, false): state = "No provider credentials"
            }
            return .init(id: id, name: "Artwork and scores", purpose: "Configure SteamGridDB and IGDB. Automatic icons and scores also use public sources.",
                         status: state, emphasis: .neutral, action: "Open provider settings",
                         reads: "Game titles or IDs and provider results.",
                         writes: "Private API credentials, artwork preferences, saved images and cached scores on this Mac.",
                         sends: "Searches and key to SteamGridDB; searches, client ID and access token to IGDB; client ID and secret to Twitch. Game names or Steam IDs to Wikidata, title IDs to Nlib and game names to Switch Icon Showdown.",
                         settingID: steamGridDB && !igdb ? "igdb" : "steamGridDB")
        case .saves:
            let state = switch saves {
            case .off: "Cloud saves off"
            case .iCloudDrive: "iCloud Drive selected"
            case .folder: "Custom save folder selected"
            }
            return .init(id: id, name: "iCloud saves", purpose: "Keep supported game saves in iCloud Drive or in a folder you choose.",
                         status: state, emphasis: .neutral, action: "Open cloud save settings",
                         reads: "The primary user and device saves and their copies in the chosen folder.",
                         writes: "Oort creates the folder and sets each game’s preference. nxnative writes the copies; a game-specific setting can override the global choice.",
                         sends: "Oort does not upload saves directly. iCloud Drive syncs to Apple; other folders depend on their sync client.",
                         settingID: "cloudSaves")
        }
    }
}
