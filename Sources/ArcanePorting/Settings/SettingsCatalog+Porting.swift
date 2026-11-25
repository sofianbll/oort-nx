import Foundation
import NXLibraryCore

/// The rows of the Porting group (Engine, Keys, Library, New games, Cloud saves, Porting storage), and the whole
/// Settings list: the base rows and these, in screen order.
extension SettingsCatalog {
    public static func changed(in settings: AppSettings, externalChanges: Set<String> = [],
                               supportsNextendo: Bool = false, hasProfileAccount: Bool = false,
                               cloudConfigured: Bool = false) -> [SettingDescriptor] {
        changed(in: settings, externalChanges: externalChanges,
                rows: visible(supportsNextendo: supportsNextendo, hasProfileAccount: hasProfileAccount, cloudConfigured: cloudConfigured))
    }

    /// Case- and diacritic-insensitive match over title and about.
    public static func search(_ query: String, supportsNextendo: Bool = false, hasProfileAccount: Bool = false,
                              cloudConfigured: Bool = false) -> [SettingDescriptor] {
        search(query, in: visible(supportsNextendo: supportsNextendo, hasProfileAccount: hasProfileAccount, cloudConfigured: cloudConfigured))
    }

    public static func opensCloudAdvanced(_ id: String) -> Bool {
        ["cloudLibraryAdvanced", "cloudLibraryFolder", "cloudSourcesRoot", "cloudLibraryConnect",
         "cloudLibraryTool", "cloudLibraryTest", "cloudLibraryDisconnect"].contains(id)
    }

    /// The rows a player can reach now.
    public static func visible(supportsNextendo: Bool, hasProfileAccount: Bool, cloudConfigured: Bool) -> [SettingDescriptor] {
        all.filter { row in
            if row.id == "nextendoClientID" && !supportsNextendo { return false }
            if row.group == .profileNextendo && !hasProfileAccount { return false }
            guard row.group == .cloudLibrary else { return true }
            switch row.id {
            case "cloudLibrarySetup": return !cloudConfigured
            case "cloudLibraryAdvanced", "cloudLibraryTool", "showsCloudPlayIcon", "showsCloudDetailsLink", "cloudTileBadges": return true
            default: return cloudConfigured
            }
        }
    }

    public static let all = ordered(baseRows + portingRows + [
        action("nextendo", .profileNextendo, "Nextendo", "Free community online play for compatible nxnative games. Requires a Nextendo account."),
        action("nextendoFriends", .profileNextendo, "Friends", "Refresh friends"),
        action("nextendoAddFriend", .profileNextendo, "Add a friend", "Friend code"),
        row("nextendoClientID", .multiplayer, "Nextendo client ID",
            "Public OAuth client ID for sign-in and online play. Clear the field to use the build default.", \.nextendoClientID),
    ])

    /// Each Porting section's rows, in screen order.
    static let portingRows: [SettingDescriptor] = [
        // Engine
        row("checkEngineAtLaunch", .engine, "Check engine at launch",
            "Checks the engine and toolchain each time Arcane starts.", \.checkEngineAtLaunch),
        action("engineFolder", .engine, "Engine repository", "The upstream checkout used for porting; updates stay manual."),
        action("engineStatus", .engine, "Compatibility", "Engine commit, Metal compiler, build environment, toolchain gate and required flags."),
        action("toolchainOverride", .engine, "Untested toolchain override", "Explicitly allow unverified new portings."),
        action("upstream", .engine, "Upstream", "Check newer engine commits without installing them."),
        action("newestEngine", .engine, "Newest engine", "Build with nxnative main before Arcane has tested it, or go back to the tested engine."),
        action("compare", .engine, "Compare", "Open the commit comparison on GitHub."),
        action("setup", .engine, "Setup", "Open the setup checklist."),

        // Keys
        action("keys", .keys, "prod.keys", "Import, replace or detect private keys."),

        // Library
        row("refreshLibraryAtLaunch", .library, "Refresh library at launch",
            "Scans your library folders for new or removed games at start.", \.refreshLibraryAtLaunch),
        action("boxCovers", .library, "Box covers", "Open GameTDB for box covers."),
        action("gameFolder", .library, GameFoldersCopy.sourcesTitle, "Game sources: NSP, XCI, NSZ and XCZ files, or Switch 2 NUP files and extracted folders, for builds. Optional for existing apps."),
        action("libraryFolder", .library, GameFoldersCopy.appsTitle, "Choose where to find existing nxnative game apps and install new builds."),
        row("gameInboxEnabled", .library, "Sort incoming files",
            "Check the Inbox for Switch files to sort.", \.gameInboxEnabled),
        action("libraryRefresh", .library, "Scan game apps", "Find existing nxnative builds and refresh the library."),
        row("notifyPortingEnds", .library, "Notify when a porting ends",
            "A notification when a porting finishes while Arcane is in the background.", \.notifyPortingEnds),

        // New games
        row("gameDefaults.fullscreen", .games, "Fullscreen",
            "New games: start in fullscreen or a window.", \.gameDefaults.fullscreen),
        row("gameDisplay", .games, GameDisplay.title,
            "Screen used to open ported games.", \.gameDisplay),
        row("gameDefaults.enable60FPS", .games, "60 FPS",
            "New games: frame-rate target of 30 or 60 FPS.", \.gameDefaults.enable60FPS),
        row("gameDefaults.isDockedMode", .games, "Docked mode",
            "New games: console profile or handheld mode.", \.gameDefaults.isDockedMode),
        row("gameDefaults.enableMetalFXUpscale", .games, "MetalFX upscaling",
            "New games: MetalFX enlarges the finished picture to your screen.", \.gameDefaults.enableMetalFXUpscale),
        row("gameDefaults.enableMetalHUD", .games, "Metal HUD",
            "New games: Metal performance overlay.", \.gameDefaults.enableMetalHUD),
        row("gameDefaults.language", .games, "Game language",
            "New games: starting language; Game Default uses the build's language.", \.gameDefaults.language),
        row("gameDefaults.renderScale", .games, "Render scale",
            "New games: internal 3D resolution, from 50% to 100% when supported.", \.gameDefaults.renderScale),
        row("gameDefaults.rumble", .games, "Rumble",
            "New games: default controller vibration for new ported games.", \.gameDefaults.rumble),
        row("gameDefaults.rumbleGain", .games, "Rumble strength",
            "New games: default vibration strength for new ported games.", \.gameDefaults.rumbleGain),

        // Cloud saves
        row("cloudSaves", .cloudSaves, "Cloud saves",
            "One sync choice for all games, applied at next launch: Off, iCloud Drive or a folder you choose. Only the primary user and device save sync.", \.cloudSaves),
        row("cloudSavesPickedFolder", .cloudSaves, "Cloud saves folder",
            "The chosen folder for save sync; choosing a folder enables it.", \.cloudSavesPickedFolder),
        action("cloudLibrarySetup", .cloudLibrary, "Configure cloud library", "Connect Google Drive."),
        action("cloudLibraryEnabled", .cloudLibrary, "Enable cloud library",
               "Cloud storage for ported apps and build caches, separate from saves."),
        action("cloudLibraryService", .cloudLibrary, "Cloud service", "Last connection test and recovery for Google Drive."),
        action("cloudLibraryFolder", .cloudLibrary, "Library folder", "Folder for game apps and build caches."),
        action("cloudSourcesRoot", .cloudLibrary, "Game files folder", "Choose a path on the same cloud service. No files are moved."),
        action("cloudReferenceFolder", .cloudLibrary, "Reference library", "Follow a shared Google Drive folder in read-only mode."),
        action("cloudLibraryImport", .cloudLibrary, "Import games from the cloud", "Add missing games without downloading their apps."),
        row("showsCloudPlayIcon", .cloudLibrary, "Icon next to Play", "Show the cloud icon by the play button.", \.showsCloudPlayIcon),
        row("showsCloudDetailsLink", .cloudLibrary, "Link in Details", "Show the cloud library link in Details.", \.showsCloudDetailsLink),
        row("cloudTileBadges", .cloudLibrary, "Tile badges", "Show cloud status on game covers.", \.cloudTileBadges),
        action("cloudLibraryAdvanced", .cloudLibrary, "Folders and connection tools", "Advanced"),
        action("cloudLibraryConnect", .cloudLibrary, "Change Google credentials", "Sign in with your own Google OAuth client in your browser."),
        action("cloudLibraryTool", .cloudLibrary, "Cloud tool", "Choose the executable or use the detected one."),
        action("cloudLibraryTest", .cloudLibrary, "Test connection", "Lists the cloud folder without changing its files."),
        action("cloudLibraryDisconnect", .cloudLibrary, "Disconnect", "Removes only the local connection. Cloud files stay where they are."),

        // Porting storage
        action("buildCaches", .portingStorage, "Build caches", "Move one game's build cache or all build caches to the Trash after confirmation; rebuilds may take longer."),
    ]
}
