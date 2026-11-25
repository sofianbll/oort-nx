import Foundation

/// One row on the Settings screen, as listed by Changed and Search.
public struct SettingDescriptor: Identifiable, Sendable {
    /// The `AppSettings` property name when the row stores a value.
    public let id: String
    public let group: SettingsSection
    public let title: String
    public let about: String
    public let isChanged: @Sendable (AppSettings) -> Bool
    /// Puts this row alone back at its default; nil for an action, or a value kept outside `AppSettings`.
    public let reset: (@Sendable (inout AppSettings) -> Void)?

    public init(id: String, group: SettingsSection, title: String, about: String,
                isChanged: @escaping @Sendable (AppSettings) -> Bool = { _ in false },
                reset: (@Sendable (inout AppSettings) -> Void)? = nil) {
        self.id = id
        self.group = group
        self.title = title
        self.about = about
        self.isChanged = isChanged
        self.reset = reset
    }
}

/// The Settings rows of the base, and the rules that order, compare and search any list of rows. The whole list,
/// with the Porting rows, is `SettingsCatalog.all` (`SettingsCatalog+Porting.swift`).
public enum SettingsCatalog {
    package static let defaults = AppSettings()
    public static let multiplayerVPNHelp = "Use ZeroTier, Tailscale or NetBird for local play away from home."

    package static func row<Value: Equatable & SendableMetatype>(_ id: String, _ group: SettingsSection, _ title: String,
                                      _ about: String,
                                      _ value: WritableKeyPath<AppSettings, Value> & Sendable) -> SettingDescriptor {
        SettingDescriptor(id: id, group: group, title: title, about: about,
                          isChanged: { $0[keyPath: value] != defaults[keyPath: value] },
                          reset: { $0[keyPath: value] = defaults[keyPath: value] })
    }

    package static func action(_ id: String, _ group: SettingsSection, _ title: String,
                       _ about: String) -> SettingDescriptor {
        SettingDescriptor(id: id, group: group, title: title, about: about)
    }

    /// `rows` in sidebar order (`SettingsSidebarGroup`), each section's rows as listed.
    public static func ordered(_ rows: [SettingDescriptor]) -> [SettingDescriptor] {
        let order = SettingsSidebarGroup.all.flatMap(\.sections)
        return rows.enumerated().sorted {
            (order.firstIndex(of: $0.element.group) ?? order.count, $0.offset)
                < (order.firstIndex(of: $1.element.group) ?? order.count, $1.offset)
        }.map(\.element)
    }

    /// The rows of every section outside the Porting group, in screen order.
    public static let baseRows: [SettingDescriptor] = [
        action("profileName", .profileIdentity, "Name", "Shown on your profile and to your friends."),
        action("profileAvatar", .profileIdentity, "Avatar", "One of Arcane’s 28 illustrations."),
        action("profilePortrait", .profileIdentity, "Personal image", "PNG, JPEG or animated GIF, up to 4 MB."),
        action("profileLock", .profileSecurity, "Profile lock", "Use four digits."),
        action("appearsOnline", .profileNextendo, "Appear online", "Share your Nextendo presence."),
        action("showsCurrentGame", .profileNextendo, "Show current game", "Applies the next time you start a game."),
        // Start-up
        row("appLanguage", .startUp, "App language", "Menus, genres and available game descriptions. The games’ own language stays separate.", \.appLanguage),
        row("appRegion", .startUp, "Regional formats", "Dates, numbers and sizes only. Game descriptions follow the app language.", \.appRegion),
        row("startOn", .startUp, "Start on",
            "The screen Arcane opens on: Spotlight, Collection, or where you left it.", \.startOn),
        row("restoreLastGame", .startUp, "Restore last game",
            "Opens with the game you had selected last time.", \.restoreLastGame),
        row("startInFullscreen", .startUp, "Start in fullscreen",
            "Open Arcane in fullscreen. Applies at the next launch.", \.startInFullscreen),
        row("checkAppUpdatesAtLaunch", .startUp, "Check for app updates",
            "Looks for a newer Arcane release at launch, at most once a day.", \.checkAppUpdatesAtLaunch),
        row("introAnimation", .startUp, "Entrance animation",
            "The library's tiles fly in with the boot sound when the app opens.", \.introAnimation),
        row("showProfilePicker", .startUp, "At startup",
            "Choose who plays when Arcane opens.", \.profileStartup),
        action("onboarding", .startUp, "Welcome setup", "Reopen the guided setup without resetting your library."),

        // Navigation
        row("showButtonHints", .navigation, "Button hints",
            "Shows the button prompts along the bottom of the screen.", \.showButtonHints),
        row("buttonNames", .navigation, "Button names",
            "Which letters the prompts use: Nintendo, Xbox or PlayStation. Automatic follows the connected controller.", \.buttonNames),
        row("viewButtonSwitches", .navigation, "View button switches screens",
            "Pressing View flips between Spotlight and Collection; holding it opens Find a game.", \.viewButtonSwitches),

        // Spotlight
        row("spotlightCards", .spotlight, "Cards",
            "Which cards sit in the Spotlight row: Collection, Surprise me, Activity, Mods and Add game.", \.visibleSpotlightCards),
        row("libraryTabs", .spotlight, "Top tabs",
            "The tabs above your games. All games is always there.", \.libraryTabs),
        row("startingTab", .spotlight, "Starting tab",
            "The filter Spotlight and Collection open on.", \.startingTab),
        row("platformCardInfo", .spotlight, "Platform card",
            "What shows beside the platform card.", \.platformCardInfo),
        row("spotlightOrder", .spotlight, "Tile order",
            "Your own order of games and cards on Spotlight. Reset puts everything back in place.", \.spotlightOrder),

        // Sound & music
        row("interfaceSounds", .soundMusic, "Interface sounds",
            "Plays a short sound when you move, select, go back or launch a game.", \.interfaceSounds),
        row("soundVolume", .soundMusic, "Sound volume",
            "How loud the interface sounds are.", \.soundVolume),
        row("quietLaunch", .soundMusic, "Quiet launch screen",
            "Game cues only during launch; movement and selection sounds stay quiet.", \.quietLaunch),
        row("soundPack", .soundMusic, "Sound pack", "Choose the interface sound pack.", \.soundPackID),
        row("noteFigure", .soundMusic, "Note sequence", "The notes you hear as you move. The Oort voices play it from start to end.", \.noteFigure),
        row("noteOctave", .soundMusic, "Octave", "Plays the note sequence lower or higher.", \.noteOctave),
        row("customNotes", .soundMusic, "Your notes", "Eight notes of your own.", \.customNotes),
        row("placeNotes", .soundMusic, "Place", "Where this sequence is heard. A place without its own follows Everywhere.", \.placeNotes),
        action("importSoundPack", .soundMusic, "Import sound pack", "Choose a folder or .oortsound file."),
        action("importSeleneSounds", .soundMusic, "Import sounds and wallpapers from Selene",
               "Copies optional sounds and wallpapers from a local Selene folder you own."),

        // Look
        row("interfaceZoom", .profileLook, "Interface size",
            "Makes text, buttons and covers larger or smaller.", \.interfaceZoom),
        row("colorThemeID", .profileLook, "Color theme",
            "The palette for focus, text and backgrounds.", \.colorThemeID),
        row("wallpaperID", .profileLook, "Wallpaper",
            "The picture behind the base gradient, per theme or none.", \.wallpaperID),
        row("settingsWallpaperID", .profileLook, "Settings wallpaper",
            "The picture behind Settings: the same as the app's, or one of its own.", \.settingsWallpaperID),
        row("backgroundSizing", .profileLook, "Wallpaper sizing",
            "Fill crops the picture to cover the screen, Fit shows all of it, Stretch distorts it to fit.", \.backgroundSizing),
        row("wallpaperBrightness", .look, "Wallpaper brightness",
            "How dark a wallpaper or live background is: dim evenly, bright on the right away from the text, or bright everywhere.", \.wallpaperBrightness),
        row("animatedBackground", .look, "Background motion",
            "The moonlight's beam and motes move and a live background plays; off, they hold still.", \.animatedBackground),
        row("keepWallpaperOnGames", .look, "Game backgrounds",
            "On shows the selected game's art in Spotlight and Collection; Off keeps your wallpaper. Details keeps the game's art.", \.keepWallpaperOnGames),
        row("backgroundShade", .look, "Library shade",
            "Shading behind library text, over game artwork or your wallpaper.", \.backgroundShade),
        row("readableText", .look, "Text shadow",
            "Adds a soft shadow under text so it reads over bright art.", \.readableText),
        row("showClock", .look, "Clock",
            "Shows the time in the top bar.", \.showClock),
        row("reduceMotion", .look, "Reduce motion",
            "Replaces slides and zooms with fades.", \.reduceMotion),
        action("iconAppearance", .look, "App icon", "The icon appearance in the Dock."),
        // Optional connections shared by all library platforms.
        action("igdb", .apiServices, "IGDB", "Personal IGDB credentials for critic scores. Wikidata remains available without a key."),
        action("steamGridDB", .apiServices, "SteamGridDB", "Add your API key to find covers, backgrounds, logos and icons in Change artwork."),
        row("multiplayerVPN", .multiplayer, "Private network (VPN)", multiplayerVPNHelp, \.multiplayerVPN),
        row("multiplayerDefault", .multiplayer, "Default for games", "Applies to games without their own multiplayer choice.", \.multiplayerDefault),
        row("multiplayerLocalMode", .multiplayer, "Local network mode", "Force LAN or local wireless instead of letting the game choose.", \.multiplayerLocalMode),
        row("multiplayerAdapter", .multiplayer, "Network adapter", "Select an interface manually if Arcane cannot identify your VPN.", \.multiplayerAdapter),

        // Games (Library)
        row("librarySort", .libraryGames, "Sort games",
            "Order of games in Spotlight and Collection.", \.librarySort),
        row("launchStyle", .libraryGames, "Launch screen style",
            "What shows while a game starts: art and logo, art only, logo on black, or minimal.", \.launchStyle),
        row("launchMotion", .libraryGames, "Launch screen motion",
            "A slow drift of the art while the game starts.", \.launchMotion),
        row("launchShade", .libraryGames, "Launch screen shade",
            "How much the launch art is darkened.", \.launchShade),
        row("tileBadgePosition", .libraryGames, "Badge position",
            "The corner of game covers that holds the badge.", \.tileBadgePosition),
        row("surprisePool", .libraryGames, "Surprise me pool",
            "Which games Surprise me picks from.", \.surprisePool),
        row("showsSessionCard", .libraryGames, "Session card",
            "When you close a game, a card shows how long you played this time and in total.", \.showsSessionCard),
        action("hiddenGames", .libraryGames, "Hidden game apps",
               "Game apps you hid from Game options; Show puts one back in your lists."),

        // Controllers
        action("controllerStatus", .controllers, "Gamepad",
               "The connected controller and how its buttons map."),
        action("buttonLayout", .controllers, "Button layout", "View the library controls."),
        row("controllerLayout", .controllers, "Controller layout",
            "While browsing", \.launcherChoices.gamepadLayout),
        action("controllerDeadzone", .controllers, "Stick navigation deadzone",
               "Thumbstick threshold for library navigation; does not alter game input."),
        row("inGameHomeButton", .controllers, "Home button in games",
            "Auto follows the controller layout.", \.inGameHomeButton),

        // Steam
        action("integrations", .sources, "All integrations", "See what each one reads, writes and sends."),
        action("macShortcutAdd", .sources, "Mac apps", "Add local Mac apps as library shortcuts."),
        action("steamSource", .sources, "Steam", "Find installed native Mac games in your Steam libraries."),
        action("steamRefresh", .sources, "Refresh Steam", "Check enabled Steam libraries without changing your game files."),
        action("steamFolder", .sources, "Steam folder", "Choose the Steam folder containing steamapps."),
        row("steamInBackground", .sources, "Keep Steam in the background",
            "Steam starts quietly when possible and comes forward if it needs you.", \.steamInBackground),

        // Storage
        action("storageUsage", .storage, "Storage usage", "See per-game app, cache and log sizes and free disk space."),
        action("logs", .storage, "Logs", "Delete build and launch logs after confirmation."),
        action("metadataCache", .storage, "Metadata cache", "Clear cached store descriptions and links."),
        action("artworkCache", .storage, "Artwork cache", "Clear downloaded images; manual picks are kept."),
        action("saveBackups", .storage, "Save backups", "Open the folder of verified per-game backups."),
        action("console", .console, "Console", "View, search and copy logs."),

        // About
        action("diagnostics", .about, "Copy diagnostics", "Copy a scrubbed support report."),
        action("appUpdates", .about, "App updates", "Check now, update or read release notes."),
        action("projectDocs", .about, "Open project docs", "Open the project documentation."),
    ] + ProfilePageCard.allCases.map {
        action("profile-card-\($0.rawValue)", .profileCards, $0.title, "Profile page cards")
    }

    public static func profileChanges(_ profile: LocalProfile?) -> Set<String> {
        guard let profile else { return [] }
        var changed: Set<String> = []
        if profile.name != profile.defaultName { changed.insert("profileName") }
        if profile.avatar != 0 { changed.insert("profileAvatar") }
        if profile.portrait != nil { changed.insert("profilePortrait") }
        if profile.isLocked { changed.insert("profileLock") }
        if profile.sharesPresence { changed.insert("appearsOnline") }
        if profile.showsCurrentGame == true { changed.insert("showsCurrentGame") }
        let cards = profile.pageCards ?? .init()
        let defaults = ProfilePageCards()
        for (index, card) in cards.ordered.enumerated()
            where card != defaults.ordered[index] || cards.isEnabled(card) != defaults.isEnabled(card) {
            changed.insert("profile-card-\(card.rawValue)")
        }
        return changed
    }

    public static func changed(in settings: AppSettings, externalChanges: Set<String> = [],
                               rows: [SettingDescriptor]) -> [SettingDescriptor] {
        rows.filter { $0.isChanged(settings) || externalChanges.contains($0.id) }
    }

    /// Case- and diacritic-insensitive match over title and about.
    public static func search(_ query: String, in rows: [SettingDescriptor]) -> [SettingDescriptor] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return rows.filter {
            $0.title.range(of: needle, options: options) != nil
                || L10n.text($0.title).range(of: needle, options: options) != nil
                || L10n.text($0.about).range(of: needle, options: options) != nil
                || $0.about.range(of: needle, options: options) != nil
                || $0.group.place.range(of: needle, options: options) != nil
                || $0.group.title.range(of: needle, options: options) != nil
                || $0.group.title(in: AppLocale(language: .english, region: "US")).range(of: needle, options: options) != nil
                || SettingsCategory(section: $0.group)?.title().range(of: needle, options: options) != nil
                || SettingsCategory(section: $0.group)?.title(for: $0.group).range(of: needle, options: options) != nil
        }
    }
}
