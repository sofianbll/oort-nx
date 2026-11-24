import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class SettingsCatalogTests: XCTestCase {
    private static let english = AppLocale(language: .english, region: nil, preferredLanguages: ["en"])

    func testDefaultSettingsHaveNoChanges() {
        XCTAssertEqual(SettingsCatalog.changed(in: AppSettings()).map(\.id), [])
    }

    func testChangedListsFlippedRows() {
        var settings = AppSettings()
        settings.interfaceSounds = false
        XCTAssertTrue(SettingsCatalog.changed(in: settings).map(\.id).contains("interfaceSounds"))
    }

    func testRumbleChangesBelongToNewGameDefaults() {
        var settings = AppSettings()
        settings.gameDefaults.rumble.toggle()
        settings.gameDefaults.rumbleGain += 1
        let changed = SettingsCatalog.changed(in: settings)
        XCTAssertEqual(Set(changed.map(\.id)), ["gameDefaults.rumble", "gameDefaults.rumbleGain"])
        XCTAssertTrue(changed.allSatisfy { $0.group == .games })
        XCTAssertTrue(changed.allSatisfy { $0.about.contains("new ported games") })
    }

    /// Every row identity: moving rows never renames them.
    private static let rowIDs = Set([
        "appLanguage", "appRegion", "startOn", "restoreLastGame", "startInFullscreen", "checkEngineAtLaunch", "onboarding",
        "refreshLibraryAtLaunch", "checkAppUpdatesAtLaunch", "introAnimation", "showProfilePicker", "showButtonHints", "buttonNames",
        "viewButtonSwitches", "spotlightCards", "startingTab", "spotlightOrder", "interfaceSounds", "soundVolume",
        "quietLaunch", "soundPack", "importSoundPack", "importSeleneSounds", "colorThemeID", "wallpaperID", "settingsWallpaperID", "backgroundSizing",
        "wallpaperBrightness", "animatedBackground", "keepWallpaperOnGames", "backgroundShade", "readableText",
        "showClock", "reduceMotion", "iconAppearance", "boxCovers", "igdb", "steamGridDB", "librarySort", "launchStyle",
        "launchMotion", "launchShade", "tileBadgePosition", "surprisePool", "cloudSaves", "cloudSavesPickedFolder", "showsSessionCard",
        "cloudLibraryEnabled", "cloudLibraryService", "cloudLibraryConnect", "cloudLibraryFolder", "cloudLibraryImport",
        "showsCloudPlayIcon", "showsCloudDetailsLink", "cloudTileBadges",
        "cloudLibrarySetup", "cloudLibraryAdvanced", "cloudSourcesRoot", "cloudReferenceFolder", "cloudLibraryTest", "cloudLibraryTool", "cloudLibraryDisconnect",
        "hiddenGames", "gameDefaults.fullscreen", "gameDisplay", "gameDefaults.enable60FPS", "gameDefaults.isDockedMode",
        "gameDefaults.enableMetalFXUpscale", "gameDefaults.enableMetalHUD", "gameDefaults.language",
        "gameDefaults.renderScale", "controllerStatus", "buttonLayout", "controllerDeadzone", "inGameHomeButton", "gameDefaults.rumble",
        "gameDefaults.rumbleGain", "gameFolder", "libraryFolder", "gameInboxEnabled", "libraryRefresh", "notifyPortingEnds",
        "macShortcutAdd", "steamSource", "steamRefresh", "steamFolder", "steamInBackground", "storageUsage", "buildCaches", "logs",
        "metadataCache", "artworkCache", "saveBackups", "console", "engineFolder", "engineStatus",
        "toolchainOverride", "upstream", "newestEngine", "compare", "keys", "setup", "diagnostics", "appUpdates",
        "projectDocs", "multiplayerVPN", "multiplayerDefault", "multiplayerLocalMode", "multiplayerAdapter",
        "profileName", "profileAvatar", "profilePortrait", "profileLock", "appearsOnline", "showsCurrentGame",
        "nextendo", "nextendoFriends", "nextendoAddFriend", "nextendoClientID"
    ] + ProfilePageCard.allCases.map { "profile-card-\($0.rawValue)" })

    func testRowIDsAreUnchanged() {
        XCTAssertEqual(SettingsCatalog.all.count, Self.rowIDs.count)
        XCTAssertEqual(Set(SettingsCatalog.all.map(\.id)), Self.rowIDs)
    }

    func testEveryRowSitsInItsNewSection() {
        let groups = Dictionary(uniqueKeysWithValues: SettingsCatalog.all.map { ($0.id, $0.group) })
        for id in ["librarySort", "launchStyle", "launchMotion", "launchShade", "tileBadgePosition", "surprisePool", "showsSessionCard", "hiddenGames"] {
            XCTAssertEqual(groups[id], .libraryGames, id)
        }
        XCTAssertEqual(groups["cloudSaves"], .cloudSaves)
        XCTAssertEqual(groups["cloudSavesPickedFolder"], .cloudSaves)
        XCTAssertEqual(groups["gameDefaults.rumble"], .games)
        XCTAssertEqual(groups["gameDefaults.rumbleGain"], .games)
        XCTAssertEqual(groups["keys"], .keys)
        XCTAssertEqual(groups["gameInboxEnabled"], .library)
        XCTAssertEqual(groups["buildCaches"], .portingStorage)
        XCTAssertEqual(groups["console"], .console)
        XCTAssertEqual(groups["logs"], .storage)
        XCTAssertEqual(groups["controllerDeadzone"], .controllers)
        XCTAssertEqual(groups["inGameHomeButton"], .controllers)
        for (section, ids) in [
            (SettingsSection.profileIdentity, ["profileName", "profileAvatar", "profilePortrait"]),
            (.profileLook, ["colorThemeID", "wallpaperID", "settingsWallpaperID", "backgroundSizing"]),
            (.profileSecurity, ["profileLock"]),
            (.profileNextendo, ["appearsOnline", "showsCurrentGame", "nextendo", "nextendoFriends", "nextendoAddFriend"]),
            (.profileCards, ProfilePageCard.allCases.map { "profile-card-\($0.rawValue)" }),
        ] {
            XCTAssertEqual(SettingsCatalog.all.filter { $0.group == section }.map(\.id), ids)
        }
        XCTAssertEqual(groups["nextendoClientID"], .multiplayer)
    }

    func testSidebarGroupsInOrder() {
        let groups = SettingsSidebarGroup.all
        XCTAssertEqual(groups.map(\.heading), [nil, "Settings group: Profile", "Settings group: General", "Settings group: Library",
                                               "Settings group: Porting", "Settings group: System"])
        XCTAssertEqual(groups.map(\.sections), [
            [.search, .changed],
            [.profileIdentity, .profileLook, .profileSecurity, .profileNextendo, .profileCards],
            [.startUp, .navigation, .spotlight, .soundMusic, .look, .controllers, .multiplayer, .apiServices],
            [.sources, .libraryGames, .storage],
            [.engine, .keys, .library, .games, .cloudSaves, .cloudLibrary, .portingStorage],
            [.about, .console],
        ])
        XCTAssertEqual(groups.map(\.isPlatform), [false, false, false, false, true, false])
        XCTAssertEqual(SettingsSection.allCases, groups.flatMap(\.sections), "allCases follows the sidebar")
    }

    func testVisibleCategoriesCoverEachLegacySectionExactlyOnce() {
        let groups = SettingsCategory.groups.map { $0.categories }
        XCTAssertEqual(groups.map(\.count), [4, 3, 5, 4])
        XCTAssertEqual(groups.flatMap { $0 }, SettingsCategory.allCases)
        let sections = groups.flatMap { $0 }.flatMap(\.sections)
        XCTAssertEqual(sections.count, SettingsSection.allCases.count - 2)
        XCTAssertEqual(Set(sections), Set(SettingsSection.allCases).subtracting([.search, .changed]))
        XCTAssertEqual(SettingsCategory.switch.sections, [.engine, .keys, .library, .games])
        XCTAssertEqual(SettingsCategory.account.sections, [.profileIdentity, .profileSecurity, .profileNextendo])
        XCTAssertEqual(SettingsCategory.integrations.sections, [.sources, .apiServices])
        XCTAssertEqual(SettingsCategory.switch.inlineSections, [.library])
        XCTAssertEqual(SettingsCategory.switch.subjects, [.engine, .keys, .games])
        XCTAssertEqual(SettingsCategory.account.subjects, [.profileNextendo])
        XCTAssertEqual(SettingsCategory.appearance.subjects, [.look])
        XCTAssertTrue(SettingsCategory.controllers.subjects.isEmpty)
        XCTAssertTrue(SettingsCategory.integrations.subjects.isEmpty)
    }

    func testSearchFindsBothCurrentAndLegacySectionNames() {
        let rows = SettingsCatalog.all
        for query in ["Setup and engine", "Switch"] {
            XCTAssertTrue(SettingsCatalog.search(query, in: rows).contains { $0.group == .engine }, query)
        }
    }

    func testPortingIsThePlatformGroup() {
        XCTAssertEqual(SettingsSection.games.place(in: Self.english), "Porting · New games")
        XCTAssertEqual(SettingsSection.engine.place(in: Self.english), "Porting · Setup and engine")
        XCTAssertEqual(SettingsSection.sources.place(in: Self.english), "Sources")
        XCTAssertEqual(SettingsSection.apiServices.title(in: Self.english), "Online services")
        XCTAssertEqual(SettingsSection.profileNextendo.place(in: .init(language: .french, region: "FR")), "Profil · Nextendo")
    }

    func testGroupResetCoversMovedRows() {
        var settings = AppSettings()
        settings.launchMotion.toggle()
        settings.librarySort = .name
        settings.showsSessionCard.toggle()
        settings.gameDefaults.rumble.toggle()
        settings.gameDefaults.fullscreen.toggle()
        settings.gameDisplay = UUID().uuidString
        settings.gameDisplayOverrides = ["0100000000000001": ""]
        settings.cloudSavesPickedFolder = "/Volumes/Saves"

        let library = SettingsReset.reset(.libraryGames, in: settings)
        XCTAssertEqual(library.launchMotion, AppSettings().launchMotion)
        XCTAssertEqual(library.librarySort, .recent)
        XCTAssertTrue(SettingsCatalog.changed(in: settings).contains { $0.id == "librarySort" })
        XCTAssertEqual(library.showsSessionCard, AppSettings().showsSessionCard)
        XCTAssertEqual(library.gameDefaults.rumble, settings.gameDefaults.rumble, "Rumble is a new-game default")
        XCTAssertEqual(library.cloudSavesPickedFolder, "/Volumes/Saves")

        let games = SettingsReset.reset(.games, in: settings)
        XCTAssertEqual(games.gameDefaults, AppSettings().gameDefaults)
        XCTAssertEqual(games.gameDisplay, "")
        XCTAssertEqual(games.gameDisplayOverrides, settings.gameDisplayOverrides)
        XCTAssertEqual(games.launchMotion, settings.launchMotion)

        XCTAssertFalse(SettingsReset.canReset(.cloudSaves))
        XCTAssertEqual(SettingsReset.reset(.cloudSaves, in: settings).cloudSavesPickedFolder, "/Volumes/Saves")
    }

    func testCloudAppearanceIsAvailableAndResetWithoutAConnection() {
        var settings = AppSettings()
        settings.showsCloudPlayIcon = false
        settings.showsCloudDetailsLink = false
        settings.cloudTileBadges = .none
        settings.cloudSavesPickedFolder = "/Volumes/Saves"

        let ids = ["showsCloudPlayIcon", "showsCloudDetailsLink", "cloudTileBadges"]
        let changed = SettingsCatalog.changed(in: settings)
        XCTAssertEqual(changed.filter { $0.group == .cloudLibrary }.map(\.id), ids)
        for (title, id) in zip(["Icon next to Play", "Link in Details", "Tile badges"], ids) {
            XCTAssertEqual(SettingsCatalog.search(title).first { $0.id == id }?.group, .cloudLibrary)
            XCTAssertFalse(SettingsCatalog.opensCloudAdvanced(id))
        }

        XCTAssertTrue(SettingsReset.canReset(.cloudLibrary))
        let reset = SettingsReset.reset(.cloudLibrary, in: settings)
        XCTAssertTrue(reset.showsCloudPlayIcon)
        XCTAssertTrue(reset.showsCloudDetailsLink)
        XCTAssertEqual(reset.cloudTileBadges, .both)
        XCTAssertEqual(reset.cloudSavesPickedFolder, "/Volumes/Saves")
        XCTAssertEqual(SettingsCatalog.changed(in: reset, externalChanges: ["cloudLibraryEnabled"],
                                                cloudConfigured: true).filter { $0.group == .cloudLibrary }.map(\.id),
                       ["cloudLibraryEnabled"])
    }

    func testOldSectionRawValuesStillDecode() {
        for raw in ["search", "changed", "startUp", "navigation", "spotlight", "soundMusic", "look", "apiServices",
                    "controllers", "library", "games", "engine", "sources", "storage", "about"] {
            XCTAssertNotNil(SettingsSection(rawValue: raw), raw)
        }
    }

    /// The rows in screen order, as before the Porting rows moved to their module.
    func testRowsKeepTheirScreenOrder() {
        XCTAssertEqual(SettingsCatalog.all.map(\.id), [
        "profileName", "profileAvatar", "profilePortrait", "colorThemeID", "wallpaperID", "settingsWallpaperID",
        "backgroundSizing", "profileLock", "appearsOnline", "showsCurrentGame", "nextendo", "nextendoFriends", "nextendoAddFriend",
        ] + ProfilePageCard.allCases.map { "profile-card-\($0.rawValue)" } + [
        "appLanguage", "appRegion", "startOn", "restoreLastGame", "startInFullscreen", "checkAppUpdatesAtLaunch",
        "introAnimation", "showProfilePicker", "onboarding", "showButtonHints", "buttonNames", "viewButtonSwitches", "spotlightCards", "startingTab",
        "spotlightOrder", "interfaceSounds", "soundVolume", "quietLaunch", "soundPack", "importSoundPack", "importSeleneSounds",
        "wallpaperBrightness", "animatedBackground",
        "keepWallpaperOnGames", "backgroundShade", "readableText", "showClock", "reduceMotion", "iconAppearance",
        "controllerStatus", "buttonLayout", "controllerDeadzone", "inGameHomeButton", "multiplayerVPN", "multiplayerDefault",
        "multiplayerLocalMode", "multiplayerAdapter", "nextendoClientID", "igdb", "steamGridDB", "macShortcutAdd", "steamSource",
        "steamRefresh", "steamFolder", "steamInBackground", "librarySort", "launchStyle", "launchMotion", "launchShade",
        "tileBadgePosition", "surprisePool", "showsSessionCard", "hiddenGames", "storageUsage", "logs", "metadataCache", "artworkCache",
        "saveBackups", "checkEngineAtLaunch", "engineFolder", "engineStatus", "toolchainOverride", "upstream",
        "newestEngine", "compare", "setup", "keys", "refreshLibraryAtLaunch", "boxCovers", "gameFolder",
        "libraryFolder", "gameInboxEnabled", "libraryRefresh", "notifyPortingEnds", "gameDefaults.fullscreen", "gameDisplay",
        "gameDefaults.enable60FPS", "gameDefaults.isDockedMode", "gameDefaults.enableMetalFXUpscale",
        "gameDefaults.enableMetalHUD", "gameDefaults.language", "gameDefaults.renderScale", "gameDefaults.rumble",
        "gameDefaults.rumbleGain", "cloudSaves", "cloudSavesPickedFolder", "cloudLibrarySetup", "cloudLibraryEnabled",
        "cloudLibraryService", "cloudLibraryFolder", "cloudSourcesRoot", "cloudReferenceFolder", "cloudLibraryImport",
        "showsCloudPlayIcon", "showsCloudDetailsLink", "cloudTileBadges", "cloudLibraryAdvanced",
        "cloudLibraryConnect", "cloudLibraryTool", "cloudLibraryTest", "cloudLibraryDisconnect", "buildCaches", "diagnostics",
        "appUpdates", "projectDocs", "console"
        ])
    }

    func testBaseRowsHoldNoPortingGroup() throws {
        let porting = try XCTUnwrap(SettingsSidebarGroup.all.first { $0.heading == "Settings group: Porting" }).sections
        XCTAssertFalse(SettingsCatalog.baseRows.contains { porting.contains($0.group) })
        XCTAssertEqual(SettingsCatalog.all.count,
                       SettingsCatalog.baseRows.count + SettingsCatalog.all.filter { porting.contains($0.group) }.count + 4)
    }

    func testSwitchOnlyRowsLiveInTheSwitchSections() {
        let groups = Dictionary(uniqueKeysWithValues: SettingsCatalog.all.map { ($0.id, $0.group) })
        XCTAssertEqual(groups["checkEngineAtLaunch"], .engine)
        XCTAssertTrue(SettingsCatalog.all.filter { [.engine, .keys, .library, .games, .cloudSaves, .cloudLibrary, .portingStorage].contains($0.group) }
            .allSatisfy { $0.group.group.isPlatform })
        XCTAssertEqual(groups["setup"], .engine)
        XCTAssertEqual(groups["refreshLibraryAtLaunch"], .library)
        XCTAssertEqual(groups["boxCovers"], .library)
        XCTAssertNil(groups["environment"], "Compatibility in Engine re-checks the environment")
        XCTAssertFalse(SettingsCatalog.all.contains { $0.group == .startUp && !Self.generalStartUp.contains($0.id) })
    }

    func testEnvironmentIsFoundOnTheEnginePage() {
        XCTAssertEqual(SettingsCatalog.search("environment").first { $0.id == "engineStatus" }?.group, .engine)
    }

    func testWelcomeSetupIsSearchableInStartUp() {
        XCTAssertEqual(SettingsCatalog.search("Welcome setup")
            .first { $0.id == "onboarding" }?.group, .startUp)
    }

    func testProfileStartupSearchAndResetBelongToStartUp() {
        var settings = AppSettings()
        settings.profileStartup = .last
        XCTAssertEqual(SettingsCatalog.search("At startup").first { $0.id == "showProfilePicker" }?.group, .startUp)
        XCTAssertEqual(SettingsCatalog.changed(in: settings).map(\.id), ["showProfilePicker"])
        XCTAssertEqual(SettingsReset.resetShared(.profileCards, in: settings).profileStartup, .last)
        XCTAssertEqual(SettingsReset.resetShared(.startUp, in: settings).profileStartup, .ask)
    }

    func testProfileSearchAndChangedUseTheSameDestinations() throws {
        var profile = LocalProfile(name: "Alex", look: .init(AppSettings()))
        profile.rename(to: "Lunar")
        profile.avatar = 4
        profile.portrait = Data([1])
        XCTAssertTrue(profile.setPIN("1234"))
        profile.appearsOnline = true
        profile.showsCurrentGame = true
        profile.pageCards = .init()
        profile.pageCards?.toggle(.week)
        let modified = SettingsCatalog.profileChanges(profile)
        let changed = SettingsCatalog.changed(in: AppSettings(), externalChanges: modified, hasProfileAccount: true)
        XCTAssertEqual(Set(changed.map(\.id)), ["profileName", "profileAvatar", "profilePortrait", "profileLock",
                                                "appearsOnline", "showsCurrentGame", "profile-card-week"])
        for row in changed {
            XCTAssertEqual(SettingsCatalog.search(row.title, hasProfileAccount: true).first { $0.id == row.id }?.group,
                           row.group)
        }
        XCTAssertEqual(SettingsCatalog.search("Nextendo", hasProfileAccount: true).first { $0.id == "nextendo" }?.group,
                       .profileNextendo)
        XCTAssertNil(SettingsCatalog.search("Nextendo", hasProfileAccount: true).first { $0.id == "nextendoClientID" })
        XCTAssertEqual(SettingsCatalog.search("Nextendo", supportsNextendo: true).first { $0.id == "nextendoClientID" }?.group,
                       .multiplayer)
    }

    func testSettingsKeepLegacyProfileKeysAndResetOnlyTheMovedValues() throws {
        let legacy = #"{"showProfilePicker":false,"colorThemeID":"arcane-flow","wallpaperID":"a","settingsWallpaperID":"b","backgroundSizing":"fit","nextendoClientID":"fixture"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(settings.profileStartup, .last)
        let look = SettingsReset.reset(.look, in: settings)
        XCTAssertEqual(LocalProfile.Look(look), LocalProfile.Look(settings))
        let reset = SettingsReset.reset(.profileLook, in: settings)
        XCTAssertEqual(LocalProfile.Look(reset), LocalProfile.Look(AppSettings()))
        XCTAssertEqual(reset.profileStartup, .last)
        XCTAssertEqual(reset.nextendoClientID, "fixture")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        XCTAssertEqual(json["colorThemeID"] as? String, "arcane-flow")
        XCTAssertEqual(json["wallpaperID"] as? String, "a")
        XCTAssertEqual(json["settingsWallpaperID"] as? String, "b")
        XCTAssertEqual(json["backgroundSizing"] as? String, "fit")
        XCTAssertEqual(json["nextendoClientID"] as? String, "fixture")
        XCTAssertEqual(json["showProfilePicker"] as? Bool, false)
        let profile = LocalProfile(name: "Alex", look: .init(settings))
        let legacyProfile = try JSONEncoder().encode(profile)
        var decoded = try JSONDecoder().decode(LocalProfile.self, from: legacyProfile)
        decoded.rename(to: "Lunar")
        let roundTrip = try JSONDecoder().decode(LocalProfile.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip.defaultName, "Alex")
        XCTAssertEqual(roundTrip.name, "Lunar")
        XCTAssertEqual(roundTrip.look, profile.look)
    }

    private static let generalStartUp: Set<String> = [
        "appLanguage", "appRegion", "startOn", "restoreLastGame", "startInFullscreen",
        "checkAppUpdatesAtLaunch", "introAnimation", "showProfilePicker", "onboarding"
    ]

    func testSearchMatchesAboutText() {
        let titles = SettingsCatalog.search("crops").map(\.title)
        XCTAssertTrue(titles.contains("Wallpaper sizing"))
    }

    func testWallpaperBrightnessIsFoundAndCountsAsChanged() {
        XCTAssertEqual(SettingsCatalog.search("dark").first { $0.id == "wallpaperBrightness" }?.group, .look)
        var settings = AppSettings()
        settings.wallpaperBrightness = .dim
        XCTAssertEqual(SettingsCatalog.changed(in: settings).map(\.id), ["wallpaperBrightness"])
    }

    func testSessionCardIsAGamesRowThatCountsAsChanged() {
        XCTAssertEqual(SettingsCatalog.search("Session card").first { $0.id == "showsSessionCard" }?.group, .libraryGames)
        var settings = AppSettings()
        settings.showsSessionCard = false
        XCTAssertEqual(SettingsCatalog.changed(in: settings).map(\.id), ["showsSessionCard"])
    }

    func testSearchFindsHiddenGameApps() {
        let hits = SettingsCatalog.search("hidden game apps")
        XCTAssertEqual(hits.first { $0.id == "hiddenGames" }?.group, .libraryGames)
    }

    func testPersonalAPIConnectionsShareAGeneralSectionWithoutChangingSourceIdentity() {
        let connections = SettingsCatalog.all.filter { ["igdb", "steamGridDB"].contains($0.id) }
        XCTAssertEqual(connections.map(\.group), [.apiServices, .apiServices])
        XCTAssertEqual(connections.map(\.id), ["igdb", "steamGridDB"])
        XCTAssertFalse(SettingsSection.apiServices.group.isPlatform)
        XCTAssertEqual(SettingsSection.sources.place(in: Self.english), "Sources")
        XCTAssertTrue(SettingsCatalog.search("API").contains { $0.group == .apiServices })
    }

    func testRemotePlayPreferenceIsSearchableChangedAndResetWithoutTouchingNextendo() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: Data("{}".utf8)).multiplayerVPN, .none)
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: Data(#"{"remotePlayMode":"disabled"}"#.utf8)).multiplayerVPN, .none)
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: Data(#"{"remotePlayMode":"automatic"}"#.utf8)).multiplayerVPN, .zeroTier)
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: Data(#"{"remotePlayMode":"automatic","multiplayerVPN":"none"}"#.utf8)).multiplayerVPN, .none)
        var settings = AppSettings()
        settings.multiplayerVPN = .tailscale
        settings.nextendoClientID = "public-client"
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: JSONEncoder().encode(settings)).multiplayerVPN, .tailscale)
        XCTAssertTrue(SettingsCatalog.search("ZeroTier").contains { $0.id == "multiplayerVPN" && $0.group == .multiplayer })
        XCTAssertTrue(SettingsCatalog.changed(in: settings).contains { $0.id == "multiplayerVPN" })
        XCTAssertTrue(SettingsReset.canReset(.multiplayer))
        let reset = SettingsReset.reset(.multiplayer, in: settings)
        XCTAssertEqual(reset.multiplayerVPN, .none)
        XCTAssertEqual(reset.nextendoClientID, settings.nextendoClientID)
    }

    func testEmptySearchReturnsNothing() {
        XCTAssertEqual(SettingsCatalog.search("").count, 0)
        XCTAssertEqual(SettingsCatalog.search("   ").count, 0)
    }

    func testVisibleControlNamesCanBeFoundInTheirOwnGroups() {
        let controls: [(String, SettingsSection)] = [
            ("60 FPS", .games), ("Fullscreen", .games), ("Metal HUD", .games),
            ("Render scale", .games), ("App icon", .look),
            ("Stick navigation deadzone", .controllers), ("Cloud saves folder", .cloudSaves),
            ("Configure cloud library", .cloudLibrary),
            ("Engine repository", .engine), ("Game apps", .library), ("Game files", .library)
        ]
        for (name, group) in controls {
            XCTAssertTrue(SettingsCatalog.search(name).contains { $0.group == group }, name)
        }
    }

    func testCloudSearchMatchesTheConfiguredStateAndKeepsAdvancedDiscoverable() {
        XCTAssertEqual(SettingsCatalog.search("Configure cloud library").map(\.id), ["cloudLibrarySetup"])
        XCTAssertTrue(SettingsCatalog.search("Configure cloud library", cloudConfigured: true).isEmpty)
        XCTAssertTrue(SettingsCatalog.search("Change Google credentials").isEmpty)
        XCTAssertEqual(SettingsCatalog.search("Change Google credentials", cloudConfigured: true).map(\.id), ["cloudLibraryConnect"])
        XCTAssertTrue(SettingsCatalog.search("Import games from the cloud").isEmpty)
        XCTAssertEqual(SettingsCatalog.search("Import games from the cloud", cloudConfigured: true).map(\.id), ["cloudLibraryImport"])
        XCTAssertTrue(SettingsCatalog.search("Test connection").isEmpty)
        XCTAssertEqual(SettingsCatalog.search("Test connection", cloudConfigured: true).map(\.id), ["cloudLibraryTest"])
        XCTAssertTrue(SettingsCatalog.opensCloudAdvanced("cloudLibraryTest"))
        XCTAssertTrue(SettingsCatalog.opensCloudAdvanced("cloudLibraryTool"))
        XCTAssertTrue(SettingsCatalog.opensCloudAdvanced("cloudLibraryConnect"))
        XCTAssertTrue(SettingsCatalog.opensCloudAdvanced("cloudSourcesRoot"))
        XCTAssertTrue(SettingsCatalog.search("Game files folder").isEmpty)
        XCTAssertEqual(SettingsCatalog.search("Game files folder", cloudConfigured: true).map(\.id), ["cloudSourcesRoot"])
        XCTAssertTrue(SettingsCatalog.opensCloudAdvanced("cloudLibraryDisconnect"))
        XCTAssertTrue(SettingsCatalog.opensCloudAdvanced("cloudLibraryFolder"))
        XCTAssertEqual(SettingsCatalog.search("Library folder", cloudConfigured: true)
            .filter { $0.group == .cloudLibrary }.map(\.id), ["cloudLibraryFolder"])
        XCTAssertEqual(SettingsCatalog.search("Last connection test", cloudConfigured: true).map(\.id), ["cloudLibraryService"])
    }

    func testCloudChangedKeepsExternalIDsWithoutOfferingUnavailableRows() {
        let changes: Set<String> = ["cloudLibraryEnabled", "cloudLibraryService", "cloudLibraryFolder", "cloudLibraryTool", "cloudSourcesRoot"]
        XCTAssertEqual(SettingsCatalog.changed(in: AppSettings(), externalChanges: changes).map(\.id), ["cloudLibraryTool"])
        XCTAssertEqual(Set(SettingsCatalog.changed(in: AppSettings(), externalChanges: changes, cloudConfigured: true).map(\.id)), changes)
    }

    func testIndividualNewGameChoicesAreIdentifiableInChanged() {
        var settings = AppSettings()
        settings.gameDefaults.fullscreen = true
        settings.gameDefaults.enableMetalHUD = true
        XCTAssertEqual(Set(SettingsCatalog.changed(in: settings).map(\.id)),
                       ["gameDefaults.fullscreen", "gameDefaults.enableMetalHUD"])
    }

    func testChangedIncludesExternalPreferencesWithoutUnrelatedRows() {
        let changed = SettingsCatalog.changed(in: AppSettings(), externalChanges: ["controllerDeadzone", "iconAppearance"])
        XCTAssertEqual(Set(changed.map(\.id)), ["controllerDeadzone", "iconAppearance"])
        XCTAssertEqual(Set(changed.map(\.group)), [.controllers, .look])
    }

    func testEveryGroupExceptSearchAndChangedHasRows() {
        let groups = Set(SettingsCatalog.all.map(\.group))
        for section in SettingsSection.allCases {
            if [.search, .changed].contains(section) {
                XCTAssertFalse(groups.contains(section), "\(section) should have no rows")
            } else {
                XCTAssertTrue(groups.contains(section), "\(section) has no rows")
            }
        }
    }
}
