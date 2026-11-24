#!/usr/bin/env python3
"""Render the real profile and sort views without windows, live data or sign-in."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

HOST = r'''
import AppKit
import CoreText
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

@main struct ProfileScreenProbe {
    @MainActor static var regressions: [String] = []

    @MainActor static func expect(_ condition: Bool, _ message: String) {
        if !condition { regressions.append(message); print("FAIL: \(message)") }
    }

    @MainActor static func main() async throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let font = URL(fileURLWithPath: CommandLine.arguments[2])
        let refs = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        NSApplication.shared.setActivationPolicy(.prohibited)
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        let data = AppData.supportRoot
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        settings.settings.interfaceSounds = false
        SoundEffectService.shared.bind(to: settings)
        settings.settings.nextendoClientID = "fixture-client"
        let profiles = LocalProfileStore(directory: data, settings: settings.settings, name: "Alex")
        let alex = profiles.active!
        let sam = LocalProfile(name: "Sam", avatar: 3, look: alex.look)
        try checkPickerHalo(in: out)
        if ProcessInfo.processInfo.environment["NX_TEST_PROFILE_HALO_ONLY"] == "1" { return }
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        vm.localProfiles = profiles
        let game = PortedGame(name: "Lunar Observatory", url: data.appendingPathComponent("Fixture.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: "0100000000001000")
        let slate = LocalProfile(name: "", look: alex.look)
        ProfileEditorView.checkInput(existing: sam, new: slate)
        let (rejectedPIN, readyPIN) = ProfilePINDialog.checkInput()
        print("Profile editor input checks passed")
        let avatarGames = (0..<7).map { index -> CatalogGame in
            var item = game
            item.id = UUID()
            item.name = "Observatory \(index + 1)"
            item.titleId = String(format: "010%013X", index + 1)
            return .init(nxnative: item)
        }
        let art = ArtworkStore(cacheDirectory: data.appendingPathComponent("avatar-fixtures"))
        for (index, game) in avatarGames.enumerated() {
            let url = art.cacheDirectory.appendingPathComponent(game.personalizationKey).appendingPathComponent("hero.png")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let hue = Double(index) / Double(avatarGames.count)
            let face = ZStack {
                LinearGradient(colors: [.init(hue: hue, saturation: 0.7, brightness: 0.8), .black],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: ["person.crop.circle.fill", "theatermasks.fill", "sparkles", "moon.fill",
                                   "hare.fill", "bird.fill", "mountain.2.fill"][index])
                    .font(.system(size: 118)).foregroundStyle(.white.opacity(0.84))
            }.frame(width: 460, height: 300)
            let picture = try bitmap(face)
            try save(picture, to: url)
            // ImageRenderer never runs the cover's async lookup.
            CoverArtMemo.shared.setObject(NSImage(cgImage: picture, size: .init(width: 460, height: 300)),
                                          forKey: CoverArtMemo.key(game.id, revision: ArtworkPicks.shared.revision))
        }
        let artRevision = ArtworkPicks.shared.revision
        CoverArtMemo.shared.setObject(CoverArtMemo.shared.object(forKey: CoverArtMemo.key(avatarGames[0].id, revision: artRevision))!,
                                      forKey: CoverArtMemo.key(game.id, revision: artRevision))
        let cachedPortraits = ProfileEditorView.loadAvatars(avatarGames, artwork: art)
        precondition(cachedPortraits.count == avatarGames.count)
        precondition(ProfilePortrait.symbols.count == LocalProfile.avatarCount)
        let gif = try checkGIF(in: data)
        let square = try personalPortrait(width: 512, height: 512, in: data)
        let wide = try personalPortrait(width: 768, height: 256, in: data)
        var squareProfile = alex
        squareProfile.portrait = square
        var wideProfile = alex
        wideProfile.portrait = wide
        try checkPortraitFrames([squareProfile, wideProfile], in: out)
        wideProfile.portrait = gif
        checkAnimatedPortraitFrame(wideProfile)
        wideProfile.portrait = wide
        func picker(selected: UUID?, removing: LocalProfile? = nil, editing: LocalProfile? = nil, overlay: Bool = false) -> some View {
            ProfilePickerView(profiles: profiles, initialSelection: selected, canClose: overlay, isOverlay: overlay,
                              games: [game], avatarGames: avatarGames, artwork: art, onChoose: { _ in }, onClose: {}, onActiveEdited: {},
                              onGuest: { _ in },
                              selected: selected, draft: editing, removing: removing)
        }
        try render("01-who", picker(selected: alex.id), in: out, refs, "web/reddit-showcase-who-05s.png", reduced: false, native: true)
        try render("02-add-focus", picker(selected: nil), in: out, refs, "web/182-10.png", reduced: false, native: true)
        for (step, ref) in [(ProfileEditorView.Step.name, "web/182-11.png"), (.avatar, "web/182-12.png"),
                            (.theme, "web/archive-theme-step.png"), (.background, "web/archive-background-step.png")] {
            try render("0\(step.rawValue + 3)-wizard-\(step)", ZStack {
                SeleneBackdrop().still(true)
                ProfileEditorView(profile: slate, games: [game], isNew: true, onCancel: {}, onSave: { _ in true }, step: step)
            }, in: out, refs, ref)
        }
        let french = AppLocale(language: .french, region: "FR")
        L10n.setContext(french)
        for (name, enabled) in [("off", false), ("on", true)] {
            try render("first-launch-steam-\(name)",
                       FoundGamesSetupView(viewModel: vm, steamRoot: data, steamEnabled: enabled,
                                           onOpenLibrary: { _ in },
                                           fixtureFindings: .init(steamGameCount: 2, portedAppCount: 0))
                           .environment(\.nxAppLocale, french), in: out, refs, "none")
        }
        try render("03-wizard-edit-name", ZStack {
            SeleneBackdrop().still(true)
            ProfileEditorView(profile: sam, games: [], isNew: false, nameOnly: true, onCancel: {}, onSave: { _ in true })
        }.environment(\.nxAppLocale, french), in: out, refs, "none")
        try render("04-wizard-avatar", ZStack {
            SeleneBackdrop().still(true)
            ProfileEditorView(profile: slate, games: [game], isNew: true, onCancel: {}, onSave: { _ in true },
                              step: .avatar, cachedPortraits: cachedPortraits)
        }.environment(\.nxAppLocale, french), in: out, refs, "web/182-12.png", reduced: false)
        try render("04-wizard-discard", ZStack {
            SeleneBackdrop().still(true)
            ProfileEditorView(profile: sam, games: [game], isNew: false, onCancel: {}, onSave: { _ in true },
                              step: .avatar, cachedPortraits: cachedPortraits).discardFixture()
        }.environment(\.nxAppLocale, french), in: out, refs, "none")
        L10n.setContext(.init(language: .english, region: "US"))
        let current = LibrarySort.recent
        let linked = fakeAccount(data.appendingPathComponent("profile-page-account"))
        var profileGames = avatarGames
        var achievementGame = profileGames[1].nxnativeGame!
        let profilePack = LocalAchievementPack.linksAwakening!
        achievementGame.titleId = profilePack.titleID
        achievementGame.versionString = profilePack.gameVersion
        profileGames[1] = CatalogGame(nxnative: achievementGame)
        let oldArt = art.cacheDirectory.appendingPathComponent(avatarGames[1].personalizationKey).appendingPathComponent("hero.png")
        let newArt = art.cacheDirectory.appendingPathComponent(profileGames[1].personalizationKey).appendingPathComponent("hero.png")
        try FileManager.default.createDirectory(at: newArt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: oldArt, to: newArt)
        for (index, item) in profileGames.prefix(3).enumerated() {
            var native = item.nxnativeGame!
            let end = Date(timeIntervalSince1970: 1_791_014_400 + TimeInterval(index * 86_400))
            native.lastBuild = .init(startedAt: end.addingTimeInterval(-120), endedAt: end, exitCode: 0)
            profileGames[index] = .init(nxnative: native)
        }
        vm.applyCatalog(.init(sources: [.init(integration: .nxnative, isEnabled: true)], games: profileGames))
        precondition(vm.visibleCatalogGames.count == profileGames.count)
        _ = vm.localAchievementStore.record([.seashells: 10], in: profilePack, profile: alex.id, at: .now)
        var date = Date.now.addingTimeInterval(-3 * 3600)
        let pageHistory = PlaySessionStore(fileURL: data.appendingPathComponent("profile-page-sessions.json"), now: { date })
        for (index, item) in profileGames.prefix(5).reversed().enumerated() {
            precondition(pageHistory.start(gameID: item.id, sourceID: item.personalizationKey, announces: false))
            date.addTimeInterval(index == 0 ? 5_400 : 900)
            _ = pageHistory.end(gameID: item.id)
        }
        for item in profileGames {
            _ = await GameArtLoader.shared.hero(for: item.nxnativeGame!, metadata: nil, artwork: art,
                                                personalizations: vm.personalizations)
        }
        var pageProfile = alex
        pageProfile.portrait = wide
        pageProfile.appearsOnline = true
        linked.setScreenFixture(.connected)
        linked.setPresenceFixture()
        precondition(linked.account?.friends?.isEmpty == false)
        let pageRouter = AppRouter()
        vm.homeSeen = true
        vm.spotlight.selectedKey = SpotlightItem.card(.activity).key
        let activityCard = SpotlightView(viewModel: vm, router: pageRouter, settings: settings, playSessions: pageHistory,
                                         runningGames: RunningGameMonitor(), artwork: art, storeHost: ModStoreHost())
        L10n.setContext(french)
        precondition(activityCard.selectedItem == .card(.activity))
        precondition(activityCard.recentBuilds?.map(\.game.id) == profileGames.prefix(3).reversed().map(\.id))
        try render("spotlight-activity-builds-shown", activityCard.environment(\.nxAppLocale, french), in: out, refs, "none")
        activityCard.handle(.secondaryAction)
        precondition(activityCard.recentBuilds == nil)
        precondition(!AppSettingsStore(fileURL: settings.fileURL).settings.showsRecentBuilds)
        try render("spotlight-activity-builds-hidden", activityCard.environment(\.nxAppLocale, french), in: out, refs, "none")
        activityCard.handle(.secondaryAction)
        precondition(activityCard.recentBuilds?.count == 3)
        precondition(AppSettingsStore(fileURL: settings.fileURL).settings.showsRecentBuilds)
        L10n.setContext(.init(language: .english, region: "US"))
        activityCard.activate(.card(.activity))
        precondition(pageRouter.route == .profile)
        pageRouter.back()
        precondition(pageRouter.route == .library)
        let query = LibraryQuery(filter: .favorites, searchText: "no matches", sort: .recent)
        vm.librarySelection = .init(query: query)
        pageRouter.navigate(to: .profile)
        pageRouter.navigate(to: .profileCollection(.mostPlayed))
        let card = CollectionView(viewModel: vm, router: pageRouter, settings: settings, playSessions: pageHistory, artwork: art)
        precondition(card.games.count == 5 && card.games.first?.id == profileGames[4].id)
        card.reconcile()
        precondition(vm.librarySelection.selectedGameID == profileGames[4].id)
        card.handle(.tabNext)
        precondition(vm.librarySelection.selectedGameID == card.games[1].id)
        card.handle(.jumpToEnd)
        precondition(vm.librarySelection.selectedGameID == card.games.last?.id)
        card.handle(.rightStickPress)
        precondition(vm.librarySelection.query == query)
        card.handle(.jumpToStart)
        try render("profile-most-played", card.environment(\.nxAppLocale, french), in: out, refs, "none")
        pageRouter.back()
        precondition(pageRouter.route == .profile)
        vm.librarySelection = .init()
        L10n.setContext(french)
        for (name, size, account) in [
            ("16-9-linked", CGSize(width: 1440, height: 810), linked),
            ("16-9-local", CGSize(width: 1440, height: 810), nil),
            ("16-10", CGSize(width: 1280, height: 800), linked),
            ("21-9", CGSize(width: 1890, height: 810), linked),
            ("small", CGSize(width: 680, height: 470), linked)
        ] {
            let page = ProfilePage(profile: pageProfile, viewModel: vm, history: pageHistory, artwork: art,
                                   nextendo: account, router: pageRouter, focus: .constant(.card(.recent)),
                                   onSwitch: {})
            if name == "16-9-linked" {
                var checkedFocus = false
                try render("profile-page-\(name)", page.checkSectionFocus { checkedFocus = true }
                    .environment(\.nxAppLocale, french), in: out, refs, "profile-page.png", size: size)
                precondition(checkedFocus)
                page.confirmFocusedSection()
                precondition(pageRouter.route == .profileCollection(.recent))
                pageRouter.back()
            } else {
                try render("profile-page-\(name)", page.environment(\.nxAppLocale, french), in: out, refs,
                           "profile-page.png", size: size)
            }
        }
        let settingsRouter = AppRouter()
        settingsRouter.navigate(to: .profile)
        let entry = ProfilePage(profile: alex, viewModel: vm, history: pageHistory, artwork: art,
                                nextendo: linked, router: settingsRouter, focus: .constant(.edit), onSwitch: {})
        for (action, section) in [(ProfilePage.Focus.edit, SettingsSection.profileIdentity),
                                  (.account, .profileNextendo), (.lock, .profileSecurity)] {
            entry.openSettingsFixture(action)
            precondition(settingsRouter.route == .settings(section))
            SettingsView(initialSection: section, viewModel: vm, settings: settings, router: settingsRouter, artwork: art)
                .pressScreenFixtureBack()
            precondition(settingsRouter.route == .profile)
        }
        SettingsView.checkIntegrationJump(viewModel: vm, settings: settings, artwork: art)
        var settingsProfile = profiles.active!
        settingsProfile.portrait = square
        settingsProfile.avatar = 7
        settingsProfile.createdAt = Date(timeIntervalSince1970: 1_795_344_000)
        settingsProfile.appearsOnline = true
        settingsProfile.showsCurrentGame = false
        precondition(profiles.update(settingsProfile))
        vm.playSessionStore = pageHistory
        for (section, reference) in [(SettingsSection.profileIdentity, "profile-settings.png"),
                                     (.profileLook, "profile-settings-arbre.png"), (.profileSecurity, "profile-settings-arbre.png"),
                                     (.profileNextendo, "profile-settings-nextendo.png"), (.profileCards, "profile-settings-arbre.png"),
                                     (.startUp, "profile-settings-arbre.png"), (.look, "profile-settings-arbre.png"),
                                     (.multiplayer, "profile-settings-arbre.png")] {
            try render("settings-\(section.rawValue)",
                       SettingsView(initialSection: section, viewModel: vm, settings: settings, router: settingsRouter,
                                    artwork: art, profileAccount: linked)
                           .environment(\.nxAppLocale, french),
                       in: out, refs, reference, size: .init(width: 1600, height: 900))
        }
        // Cloud saves are staged; the dedicated Settings probe renders the single review over this page.
        vm.settingsStore = settings
        settings.settings.cloudSaves = .iCloudDrive
        settings.settings.cloudSavesPickedFolder = "/fixture/Switch/Saves"
        L10n.setContext(french)
        let cloudPage = SettingsView(initialSection: .cloudSaves, viewModel: vm, settings: settings, router: settingsRouter,
                                     artwork: art, profileAccount: linked).environment(\.nxAppLocale, french)
        try render("settings-cloudSaves", cloudPage, in: out, refs, "none", size: .init(width: 1600, height: 900))
        L10n.setContext(.init(language: .english, region: "US"))
        settings.settings.cloudSaves = .off
        settings.settings.cloudSavesPickedFolder = ""
        try render("settings-profile-pin", SettingsView(initialSection: .profileSecurity, viewModel: vm, settings: settings,
                   router: settingsRouter, artwork: art, fixturePIN: "set").environment(\.nxAppLocale, french),
                   in: out, refs, "none", names: .automatic)
        var locked = profiles.active!
        precondition(locked.setPIN("1234") && profiles.update(locked))
        try render("settings-profile-change-pin", SettingsView(initialSection: .profileSecurity, viewModel: vm,
                   settings: settings, router: settingsRouter, artwork: art, fixturePIN: "change")
                   .environment(\.nxAppLocale, french), in: out, refs, "none", names: .playstation)
        try render("settings-profile-remove-pin", SettingsView(initialSection: .profileSecurity, viewModel: vm,
                   settings: settings, router: settingsRouter, artwork: art, fixturePIN: "remove")
                   .environment(\.nxAppLocale, french), in: out, refs, "none", names: .nintendo)
        SettingsView.checkPINChange(viewModel: vm, settings: settings, artwork: art, profiles: profiles)
        for section: SettingsSection in [.profileIdentity, .profileNextendo, .profileCards] {
            SettingsView(initialSection: section, viewModel: vm, settings: settings, router: settingsRouter, artwork: art)
                .pressScreenFixtureReset()
        }
        let resetProfile = profiles.active!
        precondition(resetProfile.avatar == 0 && resetProfile.portrait == nil && resetProfile.name == settingsProfile.name)
        precondition(resetProfile.appearsOnline == nil && resetProfile.showsCurrentGame == nil && resetProfile.pageCards == nil)
        for choice in InGameHomeButton.allCases {
            settings.settings.inGameHomeButton = choice
            try render("settings-home-\(choice)", SettingsView(initialSection: .controllers, viewModel: vm, settings: settings,
                       router: pageRouter, artwork: art).environment(\.nxAppLocale, french),
                       in: out, refs, "none", size: .init(width: 1440, height: 810))
        }
        settings.settings.inGameHomeButton = .auto
        L10n.setContext(.init(language: .english, region: "US"))
        let switchToSam = ProfileFlow.Change(target: sam, startsGuest: false, step: .confirm)
        precondition(switchToSam.requiresConfirmation(current: alex.id, running: true, endsGuest: false))
        precondition(!switchToSam.canCommit(current: alex.id, running: true))
        precondition(switchToSam.canCommit(current: alex.id, running: false))
        precondition(!switchToSam.requiresConfirmation(current: sam.id, running: true, endsGuest: false))
        precondition(switchToSam.requiresConfirmation(current: alex.id, running: false, endsGuest: true))
        for (name, starting, ending, running) in [("switch", false, false, true), ("guest-start", true, false, false),
                                                 ("guest-end", false, true, false)] {
            try render("32-\(name)", ZStack {
                picker(selected: alex.id).seleneOverlayOwnership(false)
                SeleneOverlay(style: .profileRemoval) {
                    ProfileSwitchDialog(startsGuest: starting, endsGuest: ending, hasGame: running, hasSteam: false,
                                        waiting: false, onCancel: {}, onConfirm: {})
                }
            }, in: out, refs, "none", native: true)
        }
        func lock(_ dialog: ProfilePINDialog) -> some View {
            ZStack {
                picker(selected: alex.id).seleneOverlayOwnership(false)
                SeleneOverlay(style: .profileRemoval) { dialog }
            }.environment(\.nxAppLocale, french)
        }
        L10n.setContext(french)
        try render("33-profile-lock", lock(.init(title: "Unlock profile", onCancel: {}, onPIN: { _ in nil })),
                    in: out, refs, "none", names: .nintendo, native: true)
        try render("34-profile-lock-error", lock(rejectedPIN), in: out, refs, "none", native: true)
        try render("35-profile-lock-ready", lock(readyPIN), in: out, refs, "none", native: true)
        L10n.setContext(.init(language: .english, region: "US"))
        func stage<Bar: View>(_ top: Bar, showsSort: Bool = true, player: LocalProfile? = nil) -> some View {
            ZStack(alignment: .top) {
                SeleneBackdrop().still(true)
                top
                VStack {
                    Spacer()
                    CollectionCoverRow(games: player == nil ? [.init(nxnative: game)] : Array(avatarGames.prefix(4)),
                        selectedID: player == nil ? game.id : avatarGames[1].id,
                        artwork: ArtworkStore(), boxArt: vm.boxArt, boxArtIndexVersion: 0,
                        officialName: { _ in nil }, needsMetadata: { _ in }, cloud: vm.cloudLibrary,
                        showsCloudBadges: true, onSelect: { _ in }, onActivate: { _ in })
                    Spacer()
                }
                if showsSort {
                    SeleneHintsBar(left: HintItem.homeGlobals(other: "Spotlight", onOther: {}, onMenu: {}, onSearch: {}, onProfiles: {}),
                                   right: [LibrarySortMenu.hint(current, action: {})])
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .environment(\.profilePortrait, showsSort ? player ?? pageProfile : nil)
            .environment(\.onlinePlayersByTitle, [game.titleId!.lowercased(): 12])
        }
        let online = fakeAccount(data.appendingPathComponent("fixture-online"))
        online.setPresenceFixture()
        let after = stage(SpotlightTopBar(filter: .all, sort: current, nextendo: online))
        try render("07-top-bar", after, in: out, refs, "screenshots/library.png")
        try render("07-top-bar-square", stage(SpotlightTopBar(filter: .all, sort: current), player: squareProfile),
                   in: out, refs, "none")
        try checkTopBar(in: out, profile: alex, accent: Color(hex: SelenePaletteCatalog.resolve(alex.look.theme, in: ThemeStore.shared.palettes).glyph))
        func menu(_ name: String, _ prepare: (AppRouter) -> Void, lang: AppLocale? = nil, names: ButtonNameStyle = .xbox) throws {
            let router = AppRouter()
            router.isMenuPresented = true
            prepare(router)
            if let lang { L10n.setContext(lang) }
            try render(name, ZStack {
                stage(SpotlightTopBar(filter: .all, sort: current, nextendo: online), showsSort: false)
                MenuOverlayView(router: router, cloudLibrary: vm.cloudLibrary, activeProfile: alex,
                                hasBuildActivity: true, onSelect: { _ in }, onSelectPower: { _ in }, onTab: { _ in })
            }.environment(\.nxAppLocale, lang ?? .init(language: .english, region: "US")),
                       in: out, refs, "screenshots/menu.png", names: names)
            L10n.setContext(.init(language: .english, region: "US"))
        }
        let fr = AppLocale(language: .french, region: "FR")
        try menu("09-menu", { $0.menuSelection.selected = .profile })
        try menu("09-menu-fr", { $0.menuSelection.selected = .profile }, lang: fr)
        L10n.setContext(fr)
        try render("09-menu-open-activity-fr", ActivityCenterView(viewModel: vm, porting: vm.porting,
                   cloudLibrary: vm.cloudLibrary, focus: .init(), onFocus: { _ in }, onOpen: { _ in },
                   onCancel: { _ in }, onBack: {}, onOutside: {}, onTab: { _ in }).environment(\.nxAppLocale, fr),
                   in: out, refs, "none")
        L10n.setContext(.init(language: .english, region: "US"))
        try menu("09-menu-profile-card", { $0.menuSelection.selected = .profile; $0.openEntryMenu(); $0.moveEntryMenu(by: 1) })
        try menu("09-menu-library-card", { $0.menuSelection.selected = .library; $0.openEntryMenu() })
        try menu("09-menu-activity", { $0.menuSelection.selected = .activityCenter })
        try menu("09-menu-settings", { $0.menuSelection.selected = .settings })
        try menu("09-menu-power", { $0.menuSelection.selected = .power; $0.openPowerMenu() })
        try menu("09-menu-power-fr", { $0.menuSelection.selected = .power; $0.openPowerMenu() }, lang: fr)
        try menu("09-menu-profile-card-fr", { $0.menuSelection.selected = .profile; $0.openEntryMenu() }, lang: fr)
        try menu("09-menu-library-card-fr", { $0.menuSelection.selected = .library; $0.openEntryMenu(); $0.moveEntryMenu(by: 2) }, lang: fr)
        try checkMenuCards()
        // Each submenu over a real Details page: the page blurs under the heavier veil, the focus walks down the pills.
        let german = AppLocale(language: .german, region: "DE")
        let submenus: [(String, (AppRouter) -> Void)] = [
            ("profile", { $0.menuSelection.selected = .profile; $0.openEntryMenu() }),
            ("library", { $0.menuSelection.selected = .library; $0.openEntryMenu() }),
            ("power", { $0.menuSelection.selected = .power; $0.openPowerMenu() })]
        func details(blur: CGFloat) -> some View {
            ZStack {
                SeleneBackdrop().still(true).blur(radius: blur)
                GameDetailView(viewModel: vm, setup: vm.setup, store: vm.store, router: AppRouter(), settings: settings,
                               playSessions: PlaySessionStore(), runningGames: RunningGameMonitor(), artwork: art, game: game)
                    .blur(radius: blur)
            }
        }
        L10n.setContext(fr)
        try render("10-details-page", details(blur: 0).environment(\.nxAppLocale, fr), in: out, refs, "none")
        for (locale, tag) in [(fr, "fr"), (german, "de")] {
            for (submenu, open) in submenus {
                for downs in 1...2 {
                    let router = AppRouter()
                    router.isMenuPresented = true
                    open(router)
                    for _ in 0..<downs { router.menuStep(.down) }
                    L10n.setContext(locale)
                    try render("10-details-\(submenu)-\(tag)-\(downs + 1)", ZStack {
                        details(blur: AppShellView.profileOverlayBlur)
                        MenuOverlayView(router: router, cloudLibrary: vm.cloudLibrary, activeProfile: alex,
                                        hasBuildActivity: false, onSelect: { _ in }, onSelectPower: { _ in },
                                        onTab: { _ in })
                    }.environment(\.nxAppLocale, locale), in: out, refs, "none")
                }
            }
        }
        L10n.setContext(.init(language: .english, region: "US"))
        // The same screens under each family's button names: Switch, PS5 and the keyboard (Automatic, no pad).
        for (suffix, names) in [("switch", ButtonNameStyle.nintendo), ("ps5", .playstation), ("keyboard", .automatic)] {
            try render("07-top-bar-\(suffix)", after, in: out, refs, "none", names: names)
            try menu("09-menu-\(suffix)", { $0.menuSelection.selected = .profile }, names: names)
        }
        try render("10-online-tile", after, in: out, refs, "screenshots/library.png")
        precondition(profiles.update(sam))
        L10n.setContext(french)
        let editor = SettingsEditor(settings)
        settings.beginDraft(fields: SettingsDraftFields.fields(profiles: profiles, languages: vm.availableLanguages))
        let profileSection = SettingsStartUpSection(settings: editor, onActions: { _ in }, onChooseLanguage: {},
                                                   onChooseRegion: {}, profiles: profiles)
        for choice: ProfileStartup in [.last, .profile(alex.id), .profile(sam.id), .ask] {
            profileSection.cycleProfile(1)
            precondition(editor.settings.profileStartup == choice)
        }
        profileSection.cycleProfile(-1)
        precondition(editor.settings.profileStartup == .profile(sam.id))
        try render("19-profiles-at-startup", ZStack {
            SeleneBackdrop().still(true)
            SettingsView(initialSection: .startUp, viewModel: vm, settings: settings, router: AppRouter(), artwork: art)
        }.environment(\.nxAppLocale, french), in: out, refs, "screenshots/game-options.png")
        settings.endDraft()
        let appsFolder = data.appendingPathComponent("Fixture game apps", isDirectory: true)
        let sourcesFolder = data.appendingPathComponent("Fixture game files", isDirectory: true)
        let originalAppsFolder = vm.libraryFolder
        let originalAppsPath = AppData.preferences.string(forKey: AppViewModel.StorageKeys.savedLibraryFolder)
        vm.libraryFolder = appsFolder
        AppData.preferences.set(sourcesFolder.path, forKey: PortingModel.savedGameFolderKey)
        settings.settings.refreshLibraryAtLaunch.toggle()
        settings.settings.notifyPortingEnds.toggle()
        SettingsView(initialSection: .library, viewModel: vm, settings: settings, router: AppRouter(), artwork: art)
            .pressScreenFixtureReset()
        precondition(vm.libraryFolder?.path == appsFolder.path, "X must preserve the chosen game apps folder")
        precondition(AppData.preferences.string(forKey: AppViewModel.StorageKeys.savedLibraryFolder) == appsFolder.path)
        precondition(vm.porting.gameFilesFolder?.path == sourcesFolder.path)
        precondition(settings.settings.refreshLibraryAtLaunch == AppSettings().refreshLibraryAtLaunch)
        precondition(settings.settings.notifyPortingEnds == AppSettings().notifyPortingEnds)

        var cachedGame = game
        cachedGame.isHidden = true
        let cache = data.appendingPathComponent("\(game.titleId!)_build", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 4096).write(to: cache.appendingPathComponent("fixture"))
        cachedGame.workspacePath = data.path
        cachedGame.buildCachePath = cache.path
        vm.applyCatalog(.init(games: [.init(nxnative: cachedGame)]))
        vm.storageSnapshot = StorageManager(logsRoot: data).snapshot(games: [cachedGame], applicationsFolder: appsFolder)
        for (name, section) in [("21-settings-console", SettingsSection.console), ("22-settings-setup", .engine),
                                ("23-settings-game-folders", .library), ("24-settings-porting-storage", .portingStorage),
                                ("25-settings-hidden-apps", .libraryGames)] {
            try render(name, ZStack {
                SeleneBackdrop().still(true)
                SettingsView(initialSection: section, viewModel: vm, settings: settings, router: AppRouter(), artwork: art)
            }.environment(\.nxAppLocale, french), in: out, refs, "screenshots/game-options.png")
        }
        L10n.setContext(french)
        // The flattened Settings scroll views need more height than the viewport to show their full contents.
        let settingsCaptureSize = CGSize(width: 1440, height: 1500)
        try render("oort-about-fr", ZStack {
            SeleneBackdrop().still(true)
            SettingsView(initialSection: .about, viewModel: vm, settings: settings, router: AppRouter(), artwork: art)
        }.environmentObject(AppUpdater()).environment(\.nxAppLocale, french), in: out, refs, "none", size: settingsCaptureSize)
        try render("oort-theme-fr", ZStack {
            SeleneBackdrop().still(true)
            SettingsView(initialSection: .profileLook, viewModel: vm, settings: settings, router: AppRouter(), artwork: art)
        }.environment(\.nxAppLocale, french), in: out, refs, "none", size: settingsCaptureSize)
        for (name, icon, label) in [("halftone", AppIconAppearanceMode.auto, "Trame"), ("particles", .mono, "Particules")] {
            if vm.iconAppearanceMode != icon { vm.iconAppearanceMode = icon }
            precondition(vm.iconAppearanceMode.label == label)
            try render("oort-look-\(name)-fr", ZStack {
                SeleneBackdrop().still(true)
                SettingsView(initialSection: .look, viewModel: vm, settings: settings, router: AppRouter(), artwork: art)
            }.environment(\.nxAppLocale, french), in: out, refs, "none", size: settingsCaptureSize)
        }
        L10n.setContext(.init(language: .english, region: "US"))
        var storageActions: [SettingsRowAction] = []
        SettingsPortingStorageSection(viewModel: vm) { storageActions = $0 }.publishScreenFixtureActions()
        precondition(storageActions.count == 2)
        for (index, action) in storageActions.enumerated() {
            precondition(action.isEnabled)
            action.activate()
            let notice = vm.settingsNotice!
            precondition(notice.actionTitle == "Move to Trash")
            precondition(notice.initialFocus == notice.cancelIndex)
            try render("26-settings-trash-\(index)", SeleneOverlay(style: .dialog) {
                SeleneChoiceDialog(title: notice.title, message: notice.message, choices: notice.choices,
                                   focus: .constant(notice.initialFocus), cancelIndex: notice.cancelIndex,
                                   onCancel: {}, onChoose: { _ in })
            }.background(SeleneBackdrop().still(true)).environment(\.nxAppLocale, french), in: out, refs, "none")
        }
        vm.settingsNotice = nil
        vm.storageSnapshot = nil
        vm.applyCatalog(.init())
        try render("27-settings-no-hidden-apps",
                   SettingsView(initialSection: .libraryGames, viewModel: vm, settings: settings, router: AppRouter(), artwork: art)
                       .environment(\.nxAppLocale, french), in: out, refs, "none")
        vm.libraryFolder = originalAppsFolder
        AppData.preferences.set(originalAppsPath, forKey: AppViewModel.StorageKeys.savedLibraryFolder)
        AppData.preferences.removeObject(forKey: PortingModel.savedGameFolderKey)
        precondition(SeleneConfirmButton.ordered == [.confirm, .cancel])
        try render("11-remove", picker(selected: sam.id, removing: sam).environment(\.nxAppLocale, french),
                    in: out, refs, "web/182-15.png", native: true)
        L10n.setContext(.init(language: .english, region: "US"))
        try render("11-original-protected", picker(selected: alex.id), in: out, refs, "none", native: true)
        // Y on a profile: the wizard replaces the selector, with one bar of hints; closing it brings the selector back.
        try render("21-picker-y-wizard", picker(selected: sam.id, editing: sam, overlay: true), in: out, refs,
                    "web/182-12.png", native: true)
        try render("22-picker-back", picker(selected: sam.id, overlay: true), in: out, refs, "web/reddit-showcase-who-05s.png", native: true)
        try render("16-switch-profile", picker(selected: sam.id), in: out, refs, "web/reddit-showcase-who-05s.png", reduced: false, native: true)
        try render("17-second-profile-collection", stage(SpotlightTopBar(filter: .recentlyPlayed, sort: current), player: sam),
                   in: out, refs, "screenshots/library.png")
        let historyStore = PlaySessionStore(fileURL: data.appendingPathComponent("fixture-history.json"))
        let firstGame = UUID(), secondGame = UUID()
        precondition(historyStore.start(gameID: firstGame, sourceID: "fixture"))
        precondition(profiles.choose(sam.id))
        historyStore.profileID = sam.id
        precondition(historyStore.lastPlayed(for: firstGame) == nil)
        precondition(historyStore.start(gameID: secondGame, sourceID: "fixture"))
        let native = CatalogGame(nxnative: game)
        var originalGame = native
        originalGame.setFavorite(true)
        vm.homeSeen = true
        var fixture = originalGame
        fixture.setFavorite(false)
        // Without an enabled source the library lists nothing: the screen would show an empty collection.
        vm.applyCatalog(.init(sources: [.init(integration: .nxnative, isEnabled: true)], games: [fixture] + avatarGames))
        vm.spotlight.selectedKey = SpotlightItem.game(game.id).key
        vm.profileOwnsInput = true
        try render("20-picker-over-spotlight", ZStack {
            // The shell blurs the screen under an overlaid picker by `profileOverlayBlur`.
            SeleneBackdrop().still(true).blur(radius: AppShellView.profileOverlayBlur)
            SpotlightView(viewModel: vm, router: AppRouter(), settings: settings, playSessions: historyStore,
                          runningGames: RunningGameMonitor(), artwork: art, storeHost: ModStoreHost())
                .blur(radius: AppShellView.profileOverlayBlur)
            picker(selected: profiles.active?.id, overlay: true)
        }, in: out, refs, "web/reddit-showcase-who-05s.png", native: true)
        vm.profileOwnsInput = false
        vm.librarySelection.query.filter = .notPlayed
        try render("23-spotlight-not-played", ZStack {
            SeleneBackdrop().still(true)
            SpotlightView(viewModel: vm, router: AppRouter(), settings: settings, playSessions: historyStore,
                          runningGames: RunningGameMonitor(), artwork: art, storeHost: ModStoreHost())
        }.environment(\.profilePortrait, profiles.active), in: out, refs, "screenshots/library.png")
        try save(bitmap(HStack(spacing: 12) {
            panel(NSImage(contentsOf: out.appendingPathComponent("09-menu-library-card-fr.png"))!, "Bibliothèque")
            panel(NSImage(contentsOf: out.appendingPathComponent("23-spotlight-not-played.png"))!, "Spotlight")
        }), to: out.appendingPathComponent("bibliotheque-spotlight.png"))
        try render("24-collection", ZStack {
            SeleneBackdrop().still(true)
            CollectionView(viewModel: vm, router: AppRouter(), settings: settings, playSessions: historyStore,
                           artwork: art)
        }, in: out, refs, "none")
        try render("25-search", ZStack {
            stage(SpotlightTopBar(filter: .all, sort: current), showsSort: false)
            FindGameView(router: AppRouter(), viewModel: vm, playSessions: historyStore, artwork: art)
        }, in: out, refs, "screenshots/find.png")
        try render("26-game-options", ZStack {
            details(blur: 10)
            GameOptionsView(viewModel: vm, game: game, origin: .details,
                            onClose: {}, onShowBuild: {}, onMove: {})
        }, in: out, refs, "screenshots/game-options.png")
        let steamLibrary = data.appendingPathComponent("Steam")
        let steamContent = steamLibrary.appendingPathComponent("steamapps/common/Fixture")
        let steamApp = steamContent.appendingPathComponent("Fixture.app")
        let application = try JSONDecoder().decode(CatalogNativeApplication.self, from: JSONSerialization.data(withJSONObject: [
            "url": steamApp.absoluteString, "executableURL": steamApp.appendingPathComponent("Contents/MacOS/Fixture").absoluteString,
            "bundleIdentifier": "test.arcane.fixture", "name": "Fixture", "architectures": ["arm64"], "isDeclaredGame": true
        ]))
        var steam = SteamCatalogGame(appID: 42, name: "Solar Observatory")
        steam.hasBeenRecognized = true
        steam.installations = [.init(libraryURL: steamLibrary, contentURL: steamContent,
                                     applications: [application], availability: .available)]
        let steamGame = CatalogGame(steam: steam)
        let steamCatalog = CatalogDocument(sources: [.init(integration: .steam, isEnabled: true)], games: [steamGame])
        SteamPlayCoordinator.shared.setGames(steamCatalog.games, sources: steamCatalog.sources)
        vm.applyCatalog(steamCatalog)
        vm.librarySelection.query.filter = .all
        vm.librarySelection.selectedGameID = steamGame.id
        vm.spotlight.selectedKey = SpotlightItem.game(steamGame.id).key
        try render("play-steam-spotlight", ZStack {
            SeleneBackdrop().still(true)
            SpotlightView(viewModel: vm, router: AppRouter(), settings: settings, playSessions: historyStore,
                          runningGames: RunningGameMonitor(), artwork: art, storeHost: ModStoreHost())
        }, in: out, refs, "none")
        try render("play-steam-collection", ZStack {
            SeleneBackdrop().still(true)
            CollectionView(viewModel: vm, router: AppRouter(), settings: settings, playSessions: historyStore,
                           artwork: art)
        }, in: out, refs, "none")
        try render("play-steam-options", ZStack {
            SeleneBackdrop().still(true)
            SteamOptionsView(viewModel: vm, game: steamGame, origin: .spotlight, onClose: {}, onMove: {})
        }, in: out, refs, "none")
        let nativeGame = CatalogGame(nxnative: game)
        let player = SteamPlayCoordinator.shared
        vm.profileOwnsInput = true
        precondition(vm.play(nativeGame) == .refused(.profileLocked))
        precondition(vm.play(steamGame) == .refused(.profileLocked) && player.phase(of: steamGame) == .idle)
        vm.profileOwnsInput = false
        vm.launchingGameId = UUID()
        precondition(vm.play(nativeGame) == .refused(.launchInProgress))
        vm.launchingGameId = nil
        var guestNotices = 0
        player.showGuestNotice = { guestNotices += 1 }
        precondition(profiles.beginGuest(.init(name: "Guest fixture", look: sam.look)))
        precondition(vm.play(nativeGame) == .refused(.installationMissing), "The temporary guest can request nxnative Play")
        precondition(vm.play(steamGame) == .refused(.guestUnsupported) && guestNotices == 1)
        precondition(player.phase(of: steamGame) == .idle)
        precondition(profiles.choose(sam.id))
        vm.alertMessage = nil
        player.showGuestNotice = {}
        precondition(vm.playRouter.availability(of: vm.playTarget(for: steamGame)) == .unavailable(.launcherMissing))
        precondition(vm.play(steamGame) == .refused(.launcherMissing) && player.phase(of: steamGame) == .failed(.clientMissing))
        print("Common Play checks passed: profile ownership, guest, duplicate nxnative and missing Steam")
        try checkDeferredPlay(vm, profiles: profiles, other: alex, game: game)
        try await checkCloudInstallPlay(game, profiles: profiles, other: alex)
        try checkIconDeferredPlay(vm, profiles: profiles, other: alex, game: game, out: out, refs: refs)
        vm.applyCatalog(.init(sources: [.init(integration: .nxnative, isEnabled: true)], games: [fixture] + avatarGames))
        let pack = LocalAchievementPack.linksAwakening!
        var progress = LocalAchievementProgress()
        _ = progress.record([.seashells: 12, .heartPieces: 4], in: pack, at: Date(timeIntervalSince1970: 1_790_000_000))
        let achievements = pack.summary(progress, language: .french)
        var zelda = game
        zelda.name = "Link’s Awakening"
        zelda.url = data.appendingPathComponent("AchievementFixture.app")
        zelda.titleId = pack.titleID
        zelda.versionString = pack.gameVersion
        let achievementModel = AchievementsScreenModel(ids: achievements.rows(.all).map(\.id))
        func achievementScreen() -> some View {
            AchievementsScreen(model: achievementModel, game: .init(nxnative: zelda), summary: achievements,
                               art: nil, onFilter: { _ in }, onShiftFilter: { _ in }, onCycleOrder: {},
                               onFocus: { _ in }, onOpen: {}, onCloseDetail: {}, onClose: {})
        }
        L10n.setContext(fr)
        precondition(LibrarySortMenu.hint(.recent, action: {}).hold == "Récents")
        try render("27-local-achievements", achievementScreen().environment(\.nxAppLocale, fr), in: out, refs, "none")
        _ = achievementModel.handle(.confirm, summary: achievements)
        try render("28-local-achievement-detail", achievementScreen().environment(\.nxAppLocale, fr), in: out, refs, "none")
        try render("29-local-achievement-toast", ZStack(alignment: .topTrailing) {
            SeleneBackdrop().still(true)
            AchievementUnlockToast(names: achievements.rows(.unlocked).map(\.name)).padding(24)
        }, in: out, refs, "none")
        try await checkSessionCard(game: .init(nxnative: zelda), art: art, in: out, refs)
        try render("29-local-achievement-card", ZStack {
            SeleneBackdrop().still(true)
            DetailsAchievementsCard(summary: achievements, appID: 0, focused: false, onOpen: {})
        }, in: out, refs, "none")
        let plist = zelda.url.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["DMTitleID": pack.titleID], format: .xml, options: 0)
            .write(to: plist)
        let scopedSave = try vm.profileSaveLocation(for: zelda, profileID: sam.id)
        let guest = LocalProfile(name: "Guest", look: alex.look)
        precondition(profiles.beginGuest(guest) && vm.profileNextendo == nil)
        let guestSave = try vm.defaultSaveLocation(for: zelda)
        let legacySave = try vm.legacySaveLocation(for: zelda)
        let guestEnvironment = try guestSave.profileLaunchEnvironment(shared: legacySave)
        precondition(guestSave != scopedSave && guestSave != legacySave && guestEnvironment["DM_SAVE_SYNC"] == "0")
        precondition(guestEnvironment["DM_SAVE"]?.contains(guest.id.uuidString) == true)
        precondition(profiles.choose(sam.id))
        let anotherGuest = LocalProfile(name: "Guest", look: alex.look)
        precondition(profiles.beginGuest(anotherGuest))
        let anotherSave = try vm.defaultSaveLocation(for: zelda)
        precondition(anotherSave != guestSave)
        precondition(profiles.choose(sam.id))
        let selectedSave = try vm.saveContext(for: zelda, launchProfileID: sam.id).location
        precondition(scopedSave == selectedSave)
        try render("30-profile-saves", ZStack {
            SeleneBackdrop().still(true)
            SavesPanel(viewModel: vm, game: zelda, onClose: {})
        }, in: out, refs, "none")
        try render("31-profile-saves-copy", ZStack {
            SeleneBackdrop().still(true)
            SavesPanel(viewModel: vm, game: zelda, onClose: {}, copyingFrom: [alex])
        }.environment(\.nxAppLocale, french), in: out, refs, "none")
        precondition(profiles.choose(alex.id))
        let capturedSave = try vm.saveContext(for: zelda, launchProfileID: sam.id).location
        precondition(capturedSave == scopedSave, "Changing profiles must not reroute the launched game's achievements")
        precondition(profiles.choose(sam.id))
        try await checkQueuedBackup(vm, profiles: profiles, game: zelda, owner: sam)
        L10n.setContext(.init(language: .english, region: "US"))
        vm.librarySelection.query.filter = .all
        vm.applyCatalog(.init(games: [originalGame]))
        precondition(vm.catalogGames.first?.isFavorite == false)
        let revision = vm.catalogSnapshot.revision
        precondition(profiles.choose(alex.id))
        vm.refreshProfileFavorites()
        precondition(vm.catalogSnapshot.revision == revision && vm.catalogGames.first?.isFavorite == true)
        let accountDir = NextendoLaunch.tokenStore(profileID: sam.id, originalID: alex.id, root: data).directory
        precondition(accountDir != NextendoLaunch.tokenStore(profileID: alex.id, originalID: alex.id, root: data).directory)
        let samAccount = fakeAccount(accountDir)
        samAccount.setScreenFixture(.connected, second: true)
        L10n.setContext(french)
        try render("18-second-profile-nextendo", SettingsView(initialSection: .profileNextendo,
            viewModel: vm, settings: settings, router: AppRouter(), artwork: art, profileAccount: samAccount)
            .environment(\.nxAppLocale, french), in: out, refs, "none")
        samAccount.setScreenFixture(.connected, second: true, failure: .discordUnlinked)
        try render("18-nextendo-discord", SettingsView(initialSection: .profileNextendo,
            viewModel: vm, settings: settings, router: AppRouter(), artwork: art, profileAccount: samAccount)
            .environment(\.nxAppLocale, french), in: out, refs, "none")
        L10n.setContext(.init(language: .english, region: "US"))
        try render("12-sort-before", stage(BeforeSortTopBar(), showsSort: false), in: out, refs, "screenshots/library.png")
        try render("13-sort-after", after, in: out, refs, "screenshots/library.png")
        var focus: LibrarySort? = current
        LibrarySortMenu.handle(.navigateDown, focused: &focus) { _ in preconditionFailure() }
        precondition(focus == .name)
        try render("14-sort-menu", after.overlay {
            LibrarySortMenu(current: current, focused: focus!, choose: { _ in }, close: {})
        }, in: out, refs, "screenshots/library.png")
        var chosen: LibrarySort?
        LibrarySortMenu.handle(.confirm, focused: &focus) { chosen = $0 }
        precondition(focus == nil && chosen == .name)
        let beforeImage = out.appendingPathComponent("12-sort-before.png")
        let afterImage = out.appendingPathComponent("13-sort-after.png")
        try save(bitmap(HStack(spacing: 12) {
            panel(NSImage(contentsOf: beforeImage)!, "Arcane · avant")
            panel(NSImage(contentsOf: afterImage)!, "Arcane · après")
        }), to: out.appendingPathComponent("15-sort-avant-apres.png"))
        if !regressions.isEmpty { exit(1) }
    }

    @MainActor static var restoringFixture: ((PortedGame) throws -> Void)?

    @MainActor static func checkCloudInstallPlay(_ game: PortedGame, profiles: LocalProfileStore,
                                                other: LocalProfile) async throws {
        var fixture = game
        let original = profiles.active!
        let data = AppData.supportRoot.appendingPathComponent("CloudInstallPlay", isDirectory: true)
        fixture.url = data.appendingPathComponent("Old.app", isDirectory: true)
        fixture.bundleId = "example.oort.cloud-deferred-play"
        fixture.status = .built
        try FileManager.default.createDirectory(at: fixture.url, withIntermediateDirectories: true)
        let catalog = CatalogGame(nxnative: fixture)
        for (result, refusal) in [("failed", PlayRefusal.preparationFailed), ("cancelled", .notStarted),
                                  ("installed", .openFailed), ("profile changed", .profileLocked)] {
            let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
            let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
            vm.localProfiles = profiles
            vm.applyCatalog(.init(games: [catalog]))
            try vm.cloudLibrary.usePlayFixtureArchive(in: data)
            var events: [PlayEvent] = []
            restoringFixture = { game in
                precondition(vm.cloudLibrary.appInstall?.title == game.titleId)
                precondition(vm.play(catalog) { events.append($0) } == .accepted(.pending))
                if result == "cancelled" { throw CancellationError() }
                if result == "failed" { throw CloudArchiveError.localChanged }
                if result == "profile changed" { precondition(profiles.choose(other.id)) }
            }
            vm.performCloudLibrary(.restore(.app), for: fixture)
            guard let transfer = vm.cloudLibrary.active?.task else {
                preconditionFailure("Synthetic restore did not start: \(String(describing: vm.cloudLibrary.states[fixture.id]?.issue))")
            }
            await transfer.value
            restoringFixture = nil
            await vm.cloudLibrary.queueStore.flush()
            expect(events == [.result(.refused(refusal))],
                   "Cloud install (\(result)) must report to the original observer: \(events)")
            precondition(vm.cloudLibrary.appInstall == nil && !vm.saveGate.isBusy(titleID: fixture.titleId!))
            precondition(profiles.choose(original.id))
        }
        print("Cloud install Play: production defer reports success, failure and cancellation to the original observer")
    }

    @MainActor static func checkIconDeferredPlay(_ vm: AppViewModel, profiles: LocalProfileStore, other: LocalProfile,
                                                game: PortedGame, out: URL, refs: URL) throws {
        let original = profiles.active!
        var fixture = game
        fixture.url = game.url.deletingLastPathComponent().appendingPathComponent("MissingIconFixture.app")
        fixture.status = .built
        let catalog = CatalogGame(nxnative: fixture)
        let language = L10n.context
        defer {
            _ = profiles.choose(original.id)
            vm.applyCatalog(.init()); vm.alertMessage = nil; vm.settingsNotice = nil
            L10n.setContext(language)
        }
        vm.applyCatalog(.init(games: [catalog]))
        var events: [PlayEvent] = []
        func request() {
            events.removeAll()
            vm.alertMessage = nil
            vm.appIcon.appIconsInFlight.insert(fixture.id)
            precondition(vm.play(catalog) { events.append($0) } == .accepted(.pending))
        }
        for (name, locale) in [("en", AppLocale(language: .english, region: "US")),
                               ("fr", .init(language: .french, region: "FR"))] {
            L10n.setContext(locale)
            request()
            let notice = vm.settingsNotice!
            try render("play-icon-wait-\(name)", SeleneOverlay(style: .dialog) {
                SeleneChoiceDialog(title: notice.title, message: notice.message, choices: notice.choices,
                                   focus: .constant(notice.initialFocus), cancelIndex: notice.cancelIndex,
                                   onCancel: {}, onChoose: { _ in })
            }.environment(\.nxAppLocale, locale), in: out, refs, "none")
            vm.appIcon.completePlayFixture(fixture, .success(false))
            expect(events == [.result(.refused(.installationMissing))],
                   "Icon signing must deliver the resumed result to the original observer (\(name)): \(events)")
        }
        request()
        precondition(profiles.choose(other.id))
        vm.appIcon.completePlayFixture(fixture, .success(false))
        expect(events == [.result(.refused(.profileLocked))] && vm.alertMessage == nil,
               "Icon signing must refuse a stale profile without trying to play: \(events)")
        precondition(profiles.choose(original.id))
        request()
        vm.appIcon.completePlayFixture(fixture, .failure(CocoaError(.fileWriteUnknown)))
        expect(events == [.result(.refused(.preparationFailed))], "Failed icon signing must refuse the original Play: \(events)")
        request()
        vm.settingsNotice = nil
        vm.appIcon.completePlayFixture(fixture, .success(false))
        expect(events == [.result(.refused(.notStarted))] && vm.alertMessage == nil && vm.launchingGameId == nil,
               "Cancelling the icon notice must refuse Play exactly once: \(events)")
    }

    @MainActor static func checkDeferredPlay(_ vm: AppViewModel, profiles: LocalProfileStore,
                                             other: LocalProfile, game: PortedGame) throws {
        let original = profiles.active!
        let fm = FileManager.default
        var fixture = game
        fixture.url = game.url.deletingLastPathComponent().appendingPathComponent("DeferredPlay.app")
        fixture.bundleId = "example.oort.deferred-play-fixture"
        fixture.status = .built
        let catalog = CatalogGame(nxnative: fixture)
        vm.applyCatalog(.init(games: [catalog]))
        var events: [PlayEvent] = []
        func afterInstall() -> () -> Void {
            vm.cloudLibrary.appInstall = (fixture.titleId!, {})
            precondition(vm.play(catalog) { events.append($0) } == .accepted(.pending))
            precondition(vm.play(catalog) == .refused(.launchInProgress))
            let resume = vm.cloudLibrary.playAfterAppInstall!
            vm.cloudLibrary.appInstall = nil
            vm.cloudLibrary.playAfterAppInstall = nil
            return { resume(nil) }
        }
        let staleInstall = afterInstall()
        precondition(profiles.choose(other.id))
        staleInstall()
        precondition(events == [.result(.refused(.profileLocked))] && vm.alertMessage == nil,
                     "Cloud completion must not play under a different profile, and must notify the original observer")
        precondition(profiles.choose(original.id))
        events.removeAll()
        afterInstall()()
        precondition(events == [.result(.refused(.installationMissing))], "The original observer must receive the resumed result")
        vm.alertMessage = nil
        let settings = vm.settingsStore!
        let old = settings.settings
        defer { settings.settings = old; vm.applyCatalog(.init()); vm.alertMessage = nil }
        settings.settings.multiplayerVPN = .zeroTier
        settings.settings.multiplayerDefault = .local
        func confirmVPN() throws -> () -> Void {
            let contents = fixture.url.appendingPathComponent("Contents")
            let dm = contents.appendingPathComponent("Resources/dm")
            try fm.createDirectory(at: dm, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": fixture.bundleId!, "DMSettings": []],
                                                format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            // No VPN setting: this host always requires a fallback, regardless of the machine's interfaces.
            try Data("""
                {"schema":1,"game":"0100000000001000","settings":[
                 {"env":"DM_NETWORK","kind":"choice","section":"Game","label":"Network","default":"offline",
                  "options":[["offline","Offline"],["ldn","Local communication"]]}]}
                """.utf8).write(to: dm.appendingPathComponent("launcher.json"))
            precondition(vm.play(catalog) { events.append($0) } == .refused(.confirmationRequired))
            let retry = vm.settingsNotice!.retry!
            vm.settingsNotice = nil
            try fm.removeItem(at: fixture.url)
            return retry
        }
        events.removeAll()
        let staleVPN = try confirmVPN()
        precondition(profiles.choose(other.id))
        staleVPN()
        precondition(events == [.result(.refused(.profileLocked))] && vm.alertMessage == nil)
        precondition(profiles.choose(original.id))
        events.removeAll()
        try confirmVPN()()
        precondition(events == [.result(.refused(.installationMissing))])
        print("Deferred Play checks passed: installation, VPN, original observer and stale profile")
    }

    @MainActor static func checkPickerHalo(in out: URL) throws {
        let french = AppLocale(language: .french, region: "FR")
        L10n.setContext(french)
        defer { L10n.setContext(.init(language: .english, region: "US")) }
        let profiles = LocalProfileStore(directory: AppData.supportRoot.appendingPathComponent("halo-fixture"),
                                         settings: AppSettings(), name: "Alex")
        let first = profiles.active!
        let guest = LocalProfile(name: "Invité", avatar: LocalProfile.avatarCount - 1, look: first.look)
        precondition(profiles.beginGuest(guest))
        let palette = ThemeStore.shared.palettes.first { $0.id == "vantablack" }!
        let wallpaper = AppData.supportRoot.appendingPathComponent("halo-fixture/black.png")
        try save(bitmap(Color.black.frame(width: 16, height: 16)), to: wallpaper)
        var passed = true
        func check(_ name: String, _ id: UUID?, size: CGSize, reduced: Bool, moves: [GamepadAction] = []) throws {
            let canvas = SeleneCanvas(size: size)
            ProfilePickerView.haloFixtureFrame = .null
            let view = ProfilePickerView(profiles: profiles, initialSelection: id, canClose: false,
                                         games: [], onChoose: { _ in }, onClose: {}, onActiveEdited: {}, onGuest: { _ in })
                .environment(\.seleneBackdropStyle, .init(palette: palette, wallpaperURL: wallpaper, animated: false))
                .environment(\.nxAppLocale, french)
                .environment(\.seleneCanvas, canvas)
                .environment(\.seleneReduceMotion, reduced)
                .environment(\.seleneButtonNames, .xbox)
                .frame(width: size.width, height: size.height)
            let image = try hostedBitmap(view, size: size, moves: moves)
            try image.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("halo-\(name).png"))
            let face = ProfilePickerView.haloFixtureFrame
            precondition(!face.isNull && image.pixelsWide == Int(size.width) && image.pixelsHigh == Int(size.height))
            if name.hasSuffix("-long-start") { precondition(face.midX < size.width * 0.1) }
            if name.hasSuffix("-long-middle") { precondition(abs(face.midX - size.width / 2) < 1) }
            if name.hasSuffix("-long-end") { precondition(face.midX > size.width * 0.9) }
            let radius = canvas.u(94 * (reduced ? 1 : 1.1))
            // Measure the shadow, not the stroke or the label, on the dark fixture background.
            let directions: [(CGFloat, CGFloat)] = [(0, -1), (-1, 0), (1, 0), (0.6, 0.8)]
            let samples = directions.map { dx, dy in
                (6...11).map { offset -> Double in
                    let distance = radius + canvas.u(CGFloat(offset))
                    let x = Int((face.midX + dx * distance).rounded())
                    let y = Int((face.midY + dy * distance).rounded())
                    guard let pixel = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return 0 }
                    return max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) * 255
                }.reduce(0, +) / 6
            }
            let good = samples.min()! > 9 && samples.min()! >= samples.max()! * 0.65
            let values = samples.map { Int($0.rounded()) }
            print("halo \(name): \(good ? "PASS" : "FAIL") top/left/right/lower = \(values); center \(face.midX),\(face.midY)")
            passed = passed && good
        }
        for (name, size, reduced) in [("full", SeleneCanvas.design, false),
                                      ("narrow", .init(width: 900, height: 650), false),
                                      ("reduced", SeleneCanvas.design, true)] {
            try check("\(name)-first", first.id, size: size, reduced: reduced)
            try check("\(name)-guest", guest.id, size: size, reduced: reduced)
            try check("\(name)-add", nil, size: size, reduced: reduced)
        }
        let more = (1...10).map { LocalProfile(name: "P\($0)", avatar: $0, look: first.look) }
        for profile in more { precondition(profiles.update(profile)) }
        for (name, size, reduced) in [("full", SeleneCanvas.design, false),
                                      ("narrow", .init(width: 900, height: 650), false),
                                      ("reduced", SeleneCanvas.design, true)] {
            try check("\(name)-long-start", first.id, size: size, reduced: reduced)
            try check("\(name)-long-middle", more[4].id, size: size, reduced: reduced, moves: [.navigateRight])
            try check("\(name)-long-guest", guest.id, size: size, reduced: reduced)
            try check("\(name)-long-end", guest.id, size: size, reduced: reduced, moves: [.navigateRight])
        }
        if !passed { exit(1) }
    }

    // A never-ordered window lays out the actual AppKit scroll viewport; ImageRenderer omits it.
    @MainActor static func hostedBitmap<V: View>(_ view: V, size: CGSize,
                                                moves: [GamepadAction] = []) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.frame.size = size
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        window.layoutIfNeeded()
        func settle() {
            for _ in 0..<15 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                host.layoutSubtreeIfNeeded()
            }
        }
        settle()
        for move in moves {
            NotificationCenter.default.post(name: .nxProfileInput, object: move)
            settle()
        }
        precondition(!window.isVisible)
        // One pixel per point, also when the current screen is Retina.
        guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: image)
        return image
    }

    @MainActor static func checkSessionCard(game: CatalogGame, art: ArtworkStore, in out: URL, _ refs: URL) async throws {
        let end = Date()
        let play = PlaySession(gameID: game.id, titleID: "fixture", bundleID: nil,
                               startedAt: end.addingTimeInterval(-60), endedAt: end, lastHeartbeatAt: end)
        let summary = SessionSummary(session: play, game: game, total: 60)!
        var active = false
        let presenter = SessionCardPresenter(isActive: { active })
        presenter.ended(summary, enabled: true)
        presenter.profileDidChange()
        active = true
        presenter.becameActive()
        try await Task.sleep(nanoseconds: SessionCardPresenter.delay + 500_000_000)
        precondition(presenter.shown == nil, "A pending session card must not follow a profile switch")

        presenter.ended(summary, enabled: true)
        try await Task.sleep(nanoseconds: SessionCardPresenter.delay + 500_000_000)
        precondition(presenter.shown == summary, "The new session card should appear")
        func layer() -> some View {
            ZStack {
                SeleneBackdrop().still(true)
                SessionCardLayer(presenter: presenter, game: { _ in nil }, metadata: [:], artwork: art)
            }
        }
        try render("29-session-before-profile-switch", layer(), in: out, refs, "none")
        presenter.profileDidChange()
        precondition(presenter.shown == nil, "A visible session card must disappear on profile switch")
        try render("29-session-after-profile-switch", layer(), in: out, refs, "none")
        print("Session card profile reset passed")
    }

    @MainActor static func checkQueuedBackup(_ vm: AppViewModel, profiles: LocalProfileStore,
                                             game: PortedGame, owner: LocalProfile) async throws {
        var game = game
        game.bundleId = "example.arcane.backup-fixture"
        let other = LocalProfile(name: "Backup fixture", look: owner.look)
        precondition(profiles.update(other))
        let titleID = game.titleId!
        let store = SaveSnapshotStore(root: vm.saveBackupRoot)
        for (profile, marker) in [(owner, "MARKER-A"), (other, "MARKER-B")] {
            let location = try vm.profileSaveLocation(for: game, profileID: profile.id)
            let slot = location.directory(.account)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: slot.appendingPathComponent("progress"))
        }
        let panel = SavePanelModel(viewModel: vm, game: game)
        let resume = DispatchSemaphore(value: 0)
        vm.saveQueue.async { resume.wait() }
        panel.backUp()
        precondition(profiles.choose(other.id))
        let otherStore = SaveSnapshotStore(root: vm.saveBackupRoot)
        resume.signal()

        let deadline = ContinuousClock.now + .seconds(5)
        while panel.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!panel.busy && panel.issue == nil, "The queued backup must complete")
        let snapshots = try store.list(titleID: titleID)
        precondition(snapshots.count == 1, "A's backup folder must contain exactly one snapshot")
        let directory = try store.directory(snapshotID: snapshots[0].id, titleID: titleID)
        let saved = try String(contentsOf: directory.appendingPathComponent("save/progress"), encoding: .utf8)
        precondition(saved == "MARKER-A", "A's queued backup must not publish B's save")
        let otherSnapshots = try otherStore.list(titleID: titleID)
        precondition(otherSnapshots.isEmpty, "A's queued backup must not publish into B's backups")
        precondition(profiles.choose(owner.id))
    }

    @MainActor static func fakeAccount(_ directory: URL) -> NextendoSettings {
        let store = NextendoTokenStore(directory: directory)
        let oauth = NextendoOAuth(store: store) { request in
            precondition(request.url?.path == "/api/avatar")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        return NextendoSettings(store: store, service: .init(oauth: oauth))
    }

    /// The profile's portrait sits on the right beside the clock: its accent ring is in the right third of the
    /// bar and nowhere in the left third (no portrait, no filter chip).
    @MainActor static func checkTopBar(in out: URL, profile: LocalProfile, accent: Color) throws {
        let size = CGSize(width: 1440, height: 810)
        let bar = SpotlightTopBar(filter: .notPlayed, sort: .recent)
            .environment(\.profilePortrait, profile)
            .environment(\.seleneCanvas, SeleneCanvas(size: size))
            .environment(\.seleneReduceMotion, true)
            .frame(width: size.width, height: 110 * size.height / 1080 , alignment: .top)
            .background(Color.black)
        let image = try bitmap(bar)
        let rep = NSBitmapImageRep(cgImage: image)
        let ring = NSColor(accent).usingColorSpace(.deviceRGB)!
        var columns: [Int] = []
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if abs(c.redComponent - ring.redComponent) < 0.08, abs(c.greenComponent - ring.greenComponent) < 0.08,
                   abs(c.blueComponent - ring.blueComponent) < 0.08 { columns.append(x); break }
            }
        }
        precondition(!columns.isEmpty, "the profile ring is not drawn")
        precondition(columns.allSatisfy { $0 > rep.pixelsWide * 2 / 3 }, "the profile ring is not on the right: \(columns.min()!)")
        // Nothing but black in the left third: no portrait and no filter chip under it.
        for x in 0..<rep.pixelsWide / 4 {
            for y in 0..<rep.pixelsHigh {
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                precondition(c.redComponent + c.greenComponent + c.blueComponent < 0.05, "something is drawn at the top left")
            }
        }
        try save(image, to: out.appendingPathComponent("07-top-bar-position.png"))
    }

    /// Every pill of an open card is as wide as the widest, in every language, with the same left edge. Measured on the
    /// pixels of the real card over black, with no pill focused (no glow, no scale).
    @MainActor static func checkMenuCards() throws {
        defer { L10n.setContext(.init(language: .english, region: "US")) }
        func lines(_ titles: [(String, MaterialIcon)], width: CGFloat) -> [MenuCard.Line] {
            titles.map { .init(id: $0.0, title: $0.0, icon: $0.1, width: width, focused: false, focus: {}, choose: {}) }
        }
        for language in AppLanguage.allCases where language != .automatic {
            let locale = AppLocale(language: language, region: "FR")
            L10n.setContext(locale)
            let cards = [MenuAction.profile, .library].map { lines($0.entries.map { ($0.title, $0.icon) }, width: 320) }
                + [lines(PowerAction.allCases.map { ($0.title, $0.icon) }, width: 240)]
            for card in cards {
                let size = CGSize(width: 1440, height: 810)
                let rep = NSBitmapImageRep(cgImage: try bitmap(MenuCard(lines: card).padding(40)
                    .environment(\.nxAppLocale, locale)
                    .environment(\.seleneCanvas, SeleneCanvas(size: size))
                    .environment(\.seleneReduceMotion, true)
                    .background(Color.black)))
                var bands: [(left: Int, right: Int)] = []
                var current: (left: Int, right: Int)?
                for y in 0..<rep.pixelsHigh {
                    var span: (Int, Int)?
                    for x in 0..<rep.pixelsWide {
                        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if c.redComponent + c.greenComponent + c.blueComponent > 0.06 { span = (span?.0 ?? x, x) }
                    }
                    if let span {
                        current = (min(current?.left ?? span.0, span.0), max(current?.right ?? span.1, span.1))
                    } else if let finished = current {
                        bands.append(finished)
                        current = nil
                    }
                }
                if let current { bands.append(current) }
                let titles = card.map(\.title)
                precondition(bands.count == card.count, "\(language.rawValue): \(bands.count) pills drawn for \(titles)")
                let widths = bands.map { $0.right - $0.left + 1 }
                precondition(widths.max()! - widths.min()! <= 1, "\(language.rawValue): pill widths differ \(widths) for \(titles)")
                precondition(bands.map(\.left).max()! - bands.map(\.left).min()! <= 1, "\(language.rawValue): pills are not aligned")
            }
        }
    }

    @MainActor static func personalPortrait(width: CGFloat, height: CGFloat, in root: URL) throws -> Data {
        let url = root.appendingPathComponent("personal-\(Int(width)).png")
        let picture = HStack(spacing: 0) {
            Color.red
            Color.white
            Color.blue
        }.frame(width: width, height: height)
        try save(bitmap(picture), to: url)
        return try Data(contentsOf: url)
    }

    @MainActor static func checkPortraitFrames(_ profiles: [LocalProfile], in out: URL) throws {
        for (profile, name) in zip(profiles, ["square", "wide"]) {
            let image = try bitmap(ProfilePortrait(profile: profile, size: 120)
                .environment(\.seleneCanvas, SeleneCanvas(size: .init(width: 1920, height: 1080)))
                .padding(10).background(.black))
            let rep = NSBitmapImageRep(cgImage: image)
            func white(_ x: Int, _ y: Int) -> Bool {
                let color = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                return min(color.redComponent, color.greenComponent, color.blueComponent) > 0.9
            }
            precondition(white(70, 70) && white(70, 14) && !white(14, 14),
                         "\(name) portrait must fill the circle without drawing in its corners")
            if name == "wide" {
                precondition(white(14, 70) && white(125, 70), "wide portrait must show its centered crop")
            }
            try save(image, to: out.appendingPathComponent("portrait-\(name).png"))
        }
    }

    @MainActor static func checkAnimatedPortraitFrame(_ profile: LocalProfile) {
        let host = NSHostingView(rootView: ProfilePortrait(profile: profile, size: 120)
            .environment(\.seleneCanvas, SeleneCanvas(size: .init(width: 1920, height: 1080))))
        host.frame.size = .init(width: 120, height: 120)
        _ = host.fittingSize
        host.layoutSubtreeIfNeeded()
        func imageView(in view: NSView) -> NSImageView? {
            (view as? NSImageView) ?? view.subviews.lazy.compactMap { imageView(in: $0) }.first
        }
        guard let image = imageView(in: host), let mask = image.superview?.layer else {
            preconditionFailure("the animated portrait must mount")
        }
        precondition(image.animates && image.frame.width == 200 && image.frame.height == 120 && image.frame.minX == -40
                     && mask.masksToBounds && mask.cornerRadius == 60,
                     "the animated image must cover its circular AppKit frame without distortion")
    }

    @MainActor static func checkGIF(in root: URL) throws -> Data {
        let url = root.appendingPathComponent("fixture.gif")
        let out = root.appendingPathComponent("cropped.gif")
        let encoder = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil)!
        for color in [Color.red, .blue] {
            CGImageDestinationAddImage(encoder, try bitmap(color.frame(width: 100, height: 60)),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(encoder))
        let crop = ProfileAvatar.Crop(x: 1, y: 0, zoom: 2)
        precondition(crop.rectangle(width: 100, height: 60) == CGRect(x: 70, y: 0, width: 30, height: 30))
        let result = ProfileAvatar.render(url, crop: crop)!
        precondition(ProfileAvatar.isGIF(result))
        try result.write(to: out)
        let source = ProfileAvatar.source(out)!
        precondition(CGImageSourceGetCount(source) == 2)
        precondition(ProfileAvatar.thumbnail(source)?.width == 30)
        let values = CGImageSourceCopyPropertiesAtIndex(source, 1, nil) as? [CFString: Any]
        let timing = values?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        precondition(timing?[kCGImagePropertyGIFDelayTime] as? Double == 0.2)
        return try Data(contentsOf: url)
    }

    struct BeforeSortTopBar: View {
        @FocusState private var focused: Bool
        var body: some View {
            LegacySpotlightTopBar(filter: .all, sort: .recent, sortFocus: $focused, onCycleSort: {})
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    static let screenSize = CGSize(width: 1440, height: 810)

    @MainActor static func render<V: View>(_ name: String, _ view: V, in out: URL, _ refs: URL, _ reference: String,
                                           reduced: Bool = true, names: ButtonNameStyle = .xbox, size: CGSize = screenSize,
                                           native: Bool = false) throws {
        let content = view
            .environment(\.seleneCanvas, SeleneCanvas(size: size))
            .environment(\.seleneReduceMotion, reduced)
            .environment(\.seleneButtonNames, names)
            .frame(width: size.width, height: size.height)
        let image = try native ? hostedBitmap(content, size: size).cgImage! : bitmap(content)
        try save(image, to: out.appendingPathComponent(name + ".png"))
        guard let ref = NSImage(contentsOf: refs.appendingPathComponent(reference)) else { return }
        let comparison = HStack(spacing: 12) {
            panel(NSImage(cgImage: image, size: size), "Arcane")
            if name == "20-picker-over-spotlight",
               let original = NSImage(contentsOf: out.appendingPathComponent("01-who.png")) {
                panel(original, "Arcane · 01-who")
            }
            if name == "04-wizard-avatar", reference == "web/182-12.png" {
                // The crop's adjacent portrait centres are 157px apart for Selene's 118-unit cells.
                panel(ref, "Selene · \(reference) · same scale", cropScale: 800 / 1920 * 118 / 157)
            } else {
                panel(ref, "Selene · \(reference)")
            }
        }
        try save(bitmap(comparison), to: out.appendingPathComponent(name + "-comparison.png"))
    }

    static func panel(_ image: NSImage, _ label: String, cropScale: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 16, weight: .semibold))
            if let cropScale, let pixels = image.representations.first {
                Image(nsImage: image).resizable()
                    .frame(width: CGFloat(pixels.pixelsWide) * cropScale, height: CGFloat(pixels.pixelsHigh) * cropScale)
                    .padding(.top, 38)
                    .frame(width: 800, height: 450, alignment: .top)
            } else {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 800, height: 450)
            }
        }
        .padding(10).foregroundStyle(.white).background(.black)
    }

    @MainActor static func bitmap<V: View>(_ view: V) throws -> CGImage {
        guard let image = ImageRenderer(content: view).cgImage else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    static func save(_ image: CGImage, to url: URL) throws {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }
}
'''

EDITOR_TEST = r'''
extension ProfileEditorView {
    @MainActor static var inspectFixture: ((Self) -> Void)?

    func discardFixture() -> Self {
        var view = self
        view._discardFocus = State(initialValue: 1)
        return view
    }

    @MainActor static func checkInput(existing: LocalProfile, new: LocalProfile) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var editor: Self?
        var cancelled = 0
        var saves: [LocalProfile] = []
        var canSave = true
        inspectFixture = { editor = $0 }
        defer { inspectFixture = nil }

        func check(_ profile: LocalProfile, step: Step = .name, _ actions: () -> Void) {
            editor = nil
            let view = Self(profile: profile, games: [], isNew: profile.id == new.id,
                            onCancel: { cancelled += 1 }, onSave: { saves.append($0); return canSave }, step: step)
            let host = NSHostingView(rootView: AnyView(view.frame(width: 1440, height: 810)))
            host.frame = CGRect(x: 0, y: 0, width: 1440, height: 810)
            func settle() {
                for _ in 0..<10 {
                    _ = host.fittingSize
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                }
            }
            settle()
            precondition(editor != nil, "Offscreen hosting did not mount the profile editor")
            actions()
            precondition(host.window == nil)
            host.rootView = AnyView(EmptyView())
            settle()
        }

        func press(_ action: GamepadAction) {
            NotificationCenter.default.post(name: .nxProfileInput, object: action)
        }
        func close() { editor!.backHints.first { $0.glyph == .close }!.action!() }

        check(new) {
            close()
            precondition(cancelled == 1 && editor!.discardFocus == nil)
        }
        check(new) {
            press(.confirm)
            let name = editor!.profile.name
            precondition(!name.isEmpty, "Synthetic confirm must reach the editor")
            press(.menu)
            precondition(editor!.step == .avatar && saves.isEmpty)
            press(.cancel)
            precondition(editor!.step == .name && editor!.profile.name == name && cancelled == 1)
            press(.cancel)
            precondition(editor!.discardFocus == 1 && cancelled == 1)
            press(.confirm)
            precondition(editor!.discardFocus == nil && cancelled == 1)
        }
        check(existing) {
            press(.confirm)
            let draft = editor!.profile
            editor!.selectKey(editor!.keys.count - 1) // Done continues editing instead of saving.
            precondition(editor!.step == .avatar && editor!.profile == draft)
            close()
            precondition(editor!.discardFocus == 1 && cancelled == 1)
            press(.menu)
            press(.cancel)
            precondition(editor!.discardFocus == nil && editor!.step == .avatar && editor!.profile == draft)
            close()
            press(.navigateLeft)
            press(.confirm)
            precondition(cancelled == 2 && saves.isEmpty)
        }
        check(existing, step: .background) {
            editor!.customBackground = AppData.supportRoot.appendingPathComponent("fixture-wallpaper.png")
            editor!.indexes[Step.background.rawValue] = editor!.wallpapers.count
            close()
            precondition(editor!.discardFocus == 1 && cancelled == 2)
            press(.cancel)
            editor!.indexes[Step.background.rawValue] = 0
            close()
            precondition(cancelled == 3 && editor!.discardFocus == nil)
        }
        check(existing) {
            editor!.profile.name = "   "
            press(.menu)
            precondition(editor!.step == .name && saves.isEmpty && editor!.error != nil)
            editor!.profile.name = "  Nova  "
            canSave = false
            press(.menu)
            precondition(editor!.step == .name && editor!.error == "Profiles could not be saved.")
            var expected = existing
            expected.name = "Nova"
            canSave = true
            press(.menu)
            precondition(editor!.step == .name && saves == [expected, expected] && editor!.error == nil)
        }
    }
}
'''

PIN_TEST = r'''
extension ProfilePINDialog {
    @MainActor static var inspectFixture: ((Self) -> Void)?

    @MainActor static func checkInput() -> (rejected: Self, ready: Self) {
        var mounted: Self?
        var submitted: [String] = []
        var cancelled = 0
        inspectFixture = { mounted = $0 }
        defer { inspectFixture = nil }
        let dialog = Self(title: "Unlock profile", onCancel: { cancelled += 1 }, onPIN: { pin in
            submitted.append(pin)
            return pin == "2345" ? nil : "Incorrect code."
        })
        let host = NSHostingView(rootView: AnyView(dialog.frame(width: 1440, height: 810)))
        host.frame = CGRect(x: 0, y: 0, width: 1440, height: 810)
        func settle() {
            _ = host.fittingSize
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        func post(_ input: Any, channel: Notification.Name = .nxProfileInput) {
            NotificationCenter.default.post(name: channel, object: input)
            settle()
        }
        func press(_ action: GamepadAction) { post(action) }
        func key(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: 0, context: nil, characters: text,
                                        charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
            precondition(Self.handleKey(event, input: .nxProfileInput) == nil)
            settle()
        }
        func fill() {
            for (digit, code) in [("2", UInt16(19)), ("3", 20), ("4", 21), ("5", 23)] { key(digit, code: code) }
        }
        settle()
        precondition(mounted != nil && host.window == nil)
        post(8, channel: .nxSettingsPINInput)
        precondition(mounted!.keypad.count == 0)
        press(.menu)
        precondition(submitted.isEmpty && !mounted!.keypad.canValidate)
        press(.navigateDown); press(.navigateDown); press(.navigateDown)
        precondition(mounted!.keypad.selected == .erase)
        press(.navigateRight); press(.confirm)
        press(.secondaryAction)
        precondition(mounted!.keypad.count == 0)
        press(.confirm); press(.navigateLeft); press(.confirm)
        precondition(mounted!.keypad.count == 0)
        key("1", code: 18); key("\u{7f}", code: 51)
        precondition(mounted!.keypad.count == 0)
        press(.navigateRight); press(.navigateRight); press(.confirm)
        precondition(mounted!.keypad.selected == .validate && submitted.isEmpty)
        for digit in [0, 1, 2, 3] { post(digit) }
        precondition(mounted!.keypad.canValidate && submitted.isEmpty)
        press(.confirm)
        precondition(submitted == ["0123"] && mounted!.keypad.count == 0 && mounted!.shakes == 1)
        precondition(mounted!.error == "Incorrect code.")

        // ImageRenderer doesn't mount @State, so seed a fresh dialog from the real rejected state.
        var rejected = Self(title: "Unlock profile", onCancel: {}, onPIN: { _ in nil })
        rejected._error = State(initialValue: mounted!.error)
        rejected._keypad = State(initialValue: mounted!.keypad)
        fill()
        precondition(submitted == ["0123"] && mounted!.keypad.selected == .digit(1))
        var ready = Self(title: "Unlock profile", onCancel: {}, onPIN: { _ in nil })
        ready._keypad = State(initialValue: mounted!.keypad)
        press(.menu)
        precondition(submitted == ["0123", "2345"] && mounted!.error == nil)
        fill()
        key("\r", code: 36, modifiers: .command)
        precondition(submitted == ["0123", "2345", "2345"])
        press(.cancel)
        precondition(cancelled == 1)

        host.rootView = AnyView(dialog.environment(\.seleneReduceMotion, true).id("reduced").frame(width: 1440, height: 810))
        settle()
        for digit in [0, 1, 2, 3] { post(digit) }
        press(.menu)
        precondition(mounted!.error == "Incorrect code." && mounted!.keypad.count == 0 && mounted!.shakes == 0)
        print("Profile keypad input checks passed")
        return (rejected, ready)
    }
}
'''

SETTINGS_PIN_TEST = r'''
extension SettingsView {
    @MainActor static func checkIntegrationJump(viewModel: AppViewModel, settings: AppSettingsStore, artwork: ArtworkStore) {
        let router = AppRouter()
        router.openIntegrations()
        precondition(IntegrationOverview().open(.steam, in: router))
        let sources = CatalogSourcesModel(repository: viewModel.catalogRepository,
            initialConfiguration: .init(integration: .steam), onCommit: { _ in preconditionFailure("Unexpected Steam change") })
        let view = Self(initialSection: .sources, viewModel: viewModel, settings: settings, router: router, artwork: artwork)
        let host = NSHostingView(rootView: view.environmentObject(sources).frame(width: 1280, height: 800))
        host.frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
        for _ in 0..<10 {
            _ = host.fittingSize
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(router.settingsRowID == nil && !sources.configuration.isEnabled, "Focus the published Steam row, do not activate it")
        NotificationCenter.default.post(name: .nxSettingsGamepadAction, object: GamepadAction.cancel)
        precondition(router.route == .integrations && router.integrationFocus == .steam && host.window == nil)
        NotificationCenter.default.post(name: .nxSettingsGamepadAction, object: GamepadAction.confirm)
        precondition(!sources.configuration.isEnabled, "The dismissed Settings view must not receive Confirm")
        print("Integration → Settings row focus and return checks passed")
    }

    @MainActor static func checkPINChange(viewModel: AppViewModel, settings: AppSettingsStore,
                                          artwork: ArtworkStore, profiles: LocalProfileStore) {
        let router = AppRouter()
        router.openSettings(.profileSecurity)
        let view = Self(initialSection: .profileSecurity, viewModel: viewModel, settings: settings,
                        router: router, artwork: artwork)
        let host = NSHostingView(rootView: AnyView(view.frame(width: 1440, height: 810)))
        host.frame = CGRect(x: 0, y: 0, width: 1440, height: 810)
        func settle() {
            _ = host.fittingSize
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        func press(_ action: GamepadAction) {
            NotificationCenter.default.post(name: .nxSettingsGamepadAction, object: action)
            settle()
        }
        func enter(_ digits: [Int]) {
            for digit in digits { NotificationCenter.default.post(name: .nxSettingsPINInput, object: digit) }
            settle()
            press(.menu)
        }
        settle()
        press(.confirm) // Enter the Security rows.
        press(.confirm) // Change code.
        enter([4, 3, 2, 1])
        enter([4, 3, 2, 1])
        enter([4, 3, 2, 1])
        precondition(profiles.active?.matchesPIN("1234") == true)
        enter([1, 2, 3, 4])
        enter([4, 3, 2, 1])
        enter([4, 3, 2, 0])
        precondition(profiles.active?.matchesPIN("1234") == true)
        enter([4, 3, 2, 1])
        precondition(profiles.active?.matchesPIN("4321") == true)
        press(.navigateRight)
        press(.confirm) // Remove code.
        enter([4, 3, 2, 1])
        precondition(profiles.active?.isLocked == false && host.window == nil)
        press(.confirm) // Set code.
        enter([1, 0, 1, 0])
        precondition(profiles.active?.isLocked == false)
        enter([1, 0, 1, 0])
        precondition(profiles.active?.matchesPIN("1010") == true)
        press(.secondaryAction) // Reset still asks for the current code.
        enter([1, 0, 1, 0])
        precondition(profiles.active?.isLocked == false)
    }
}
'''


def replace(file, old, new):
    original = file.read_text()
    text, count = re.subn(old, new if callable(new) else lambda _: new, original, count=1, flags=re.S)
    assert count == 1, (file, old)
    file.write_text(text)


def main():
    work = ROOT / "work"
    work.mkdir(exist_ok=True)
    out = (Path(sys.argv[1]) if len(sys.argv) > 1 else work / "screens-profiles").resolve()
    refs = (Path(sys.argv[2]) if len(sys.argv) > 2 else out / "no-reference").resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="profile-screens-", dir=work) as temp:
        package = Path(temp)
        shutil.copytree(ROOT / "Sources", package / "Sources")
        shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
        replace(package / "Package.swift", r'\.executable\(name: "NXLibrary",', '.executable(name: "ProfileScreenProbe",')
        for target in ("NXLibraryCoreTests", "ArcanePortingTests", "OortCoreTests"):
            stub = package / "Tests" / target
            stub.mkdir(parents=True)
            (stub / "Empty.swift").touch()
        app = package / "Sources/NXLibrary"
        cloud = app / "ViewModels/AppViewModel+CloudLibrary.swift"
        replace(cloud, r"(                    let own = try await archive.latest\(titleID: target.titleID\))",
                lambda m: """                    if let fixture = ProfileScreenProbe.restoringFixture {
                        try await beforeAppInstall()
                        try fixture(game)
                        // Publish a synthetic success, without opening or replacing a real app.
                        outcome = .succeeded
                        return
                    }
""" + m[1])
        with cloud.open("a") as swift:
            swift.write("""
extension CloudLibraryModel {
    func usePlayFixtureArchive(in data: URL) throws {
        let tool = data.appendingPathComponent("rclone-fixture")
        if !FileManager.default.isExecutableFile(atPath: tool.path) {
            try Data("#!/bin/sh\\nexit 99\\n".utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        }
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games", executable: tool) { _, _, _ in
            .init(status: 0, stdout: "[]", stderr: "")
        }
        installScope(nil, backend: backend)
        hasRestoredQueue = true
    }
}
""")
        launch = app / "ViewModels/AppViewModel+Launch.swift"
        replace(launch, r"        guard let saveLaunchToken =",
                '        if game.bundleId == "example.oort.cloud-deferred-play" { return .refused(.openFailed) }\n'
                '        guard let saveLaunchToken =')
        with (app / "ViewModels/AppIconModel.swift").open("a") as swift:
            swift.write("""
extension AppIconModel {
    @MainActor func completePlayFixture(_ game: PortedGame, _ outcome: Result<Bool, Error>) {
        appIconsInFlight.remove(game.id)
        finishIconLaunchWait(for: game, rerun: false, outcome: outcome)
    }
}
""")
        replace(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        replace(app / "ViewModels/AppViewModel.swift", r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        replace(app / "ViewModels/AppViewModel.swift", r"            updateDockIcon\(\)", "")
        replace(app / "ViewModels/AppViewModel.swift", r"        applyCatalog\(catalog\).*?\n    }\n\n    // MARK: - Dynamic",
                "    }\n\n    // MARK: - Dynamic")
        replace(app / "Services/SteamPlayCoordinator.swift", r"static var steamClientURL: URL\? \{.*?\n    \}",
                "static var steamClientURL: URL? { nil }")
        replace(app / "Views/Spotlight/SpotlightTopBar.swift", r"Text\(context\.date,", "Text(Date(timeIntervalSince1970: 1_790_000_000),")
        replace(package / "Sources/NXLibraryCore/App/AppDataProfile.swift",
                r'public static let profile = [^\n]*',
                f'public static let profile = AppDataProfile(home: URL(fileURLWithPath: "{temp}"), isDevelopment: true)')
        replace(package / "Sources/NXLibraryCore/App/AppDataProfile.swift",
                r'public static var preferences: UserDefaults \{ [^\n]+ \}',
                'public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        replace(app / "Views/Shell/MenuOverlayView.swift", r"var presented = false", "var presented = true")
        replace(app / "Views/Setup/FoundGamesSetupView.swift", r"    var findings: FirstRunFindings\? \{ reader.findings \}",
                "    var fixtureFindings: FirstRunFindings? = nil\n"
                "    var findings: FirstRunFindings? { fixtureFindings ?? reader.findings }")
        replace(app / "Views/Setup/FoundGamesSetupView.swift", r"            reader.start\(steamRoot:[^\n]+",
                "            if fixtureFindings == nil { reader.start(steamRoot: steamRoot, appsFolder: viewModel.gameAppsFolder) }")
        activity = app / "Views/Shell/ActivityCenterView.swift"
        replace(activity, r"                ScrollViewReader \{ scroll in\n                    ScrollView \{\n", "")
        replace(activity, r"                    }\n                    \.padding\(EdgeInsets.*?\.onChange\(of: focused\)[^\n]*\n                }\n", "")
        replace(app / "Views/Theme/ThemeStore.swift", r"static let shared = ThemeStore\(\)",
                f'static let shared = ThemeStore(palettesURL: URL(fileURLWithPath: "{ROOT}/Resources/Selene/palettes.json"))')
        replace(app / "Views/Search/FindGameView.swift",
                r'TextField\(L10n.text\("Find a game"\), text: \$query\).*?\.onSubmit \{ pick\(results.first\) \}',
                'Text(query.isEmpty ? L10n.text("Find a game") : query).seleneFont(19)'
                '.foregroundColor(SeleneTheme.ink).frame(maxWidth: .infinity, alignment: .leading)')
        replace(app / "Views/Search/FindGameView.swift", r'var query = ""', 'var query = "Observatory"')
        options = app / "Views/GameOptions/GameOptionsView+Rows.swift"
        replace(options, r'            ScrollViewReader \{ proxy in\n                ScrollView \{\n', '')
        replace(options, r'                }\n                \.scrollIndicators\(\.hidden\).*?\n            }\n            \.id\(level\)\n', '')
        replace(options, r'let entries = p\.entries\(level: level, origin: origin, context: localization\)',
                lambda match: match[0] + '.prefix(8)')
        saves = app / "Views/GameOptions/SavesPanel.swift"
        replace(saves, r"onClose: @escaping \(\) -> Void\) \{",
                "onClose: @escaping () -> Void, copyingFrom: [LocalProfile] = []) {\n"
                "        _copyFrom = State(initialValue: copyingFrom)\n"
                "        _copyFocus = State(initialValue: copyingFrom.count)")
        # The two snapshots share a game fixture; neither needs the live save lease or key monitor.
        replace(saves, r"\n        \.onAppear \{ model.refresh\(\); installKeyMonitor\(\) \}", "")
        replace(saves, r"ProgressView\(\)\.controlSize\(\.small\)\.tint\(SeleneTheme.ink60\)", "Color.clear")
        replace(saves,
                r"        ScrollViewReader \{ proxy in\n            ScrollView \{(.*?)\n            }\.scrollIndicators\(\.hidden\).*?\n        }\n    }\n    private var statusLine",
                lambda m: "        Group {" + m[1] + "\n        }\n    }\n    private var statusLine")
        replace(app / "Views/Theme/SeleneBackdrop.swift",
                r"tint: modsTint \? 1 : 0, moving: moving,\n",
                "tint: modsTint ? 1 : 0, moving: false, asImage: true,\n")
        # ImageRenderer does not draw the AppKit scroll host. Keep the real SwiftUI layout and clip it
        # to the same viewport for screenshots; scroll/input are not verified by the PNGs.
        profile_page = app / "Views/Shell/ProfilePage.swift"
        replace(profile_page,
                r"                ScrollViewReader \{ proxy in\n                    ScrollView \{(.*?)"
                r"                    \}\n                    \.onChange\(of: focus, initial: true\).*?"
                r"\n                \}\n            \}\n            if ownsPage",
                lambda m: "                Color.clear.overlay(alignment: .top) {" + m[1] +
                "                        .fixedSize(horizontal: false, vertical: true)\n"
                "                    }.clipped()\n            }\n            if ownsPage")
        with (app / "Views/Shell/ProfilePage.swift").open("a") as swift:
            swift.write(r'''
extension ProfilePage {
    func checkSectionFocus(_ checked: @escaping () -> Void) -> some View {
        overlayPreferenceValue(Frames.self) { frames in
            let targets = frames.filter { id, _ in
                if case .card = id { return true }
                return false
            }
            if !targets.isEmpty {
                let _ = {
                    precondition(Set(targets.keys) == Set(ProfilePageCard.allCases.map(Focus.card)))
                    for rect in targets.values {
                        // At 1440 × 810 the pill is 36 px high, not the width of either section column.
                        precondition(rect.width > 0 && rect.width < 180 && rect.height == 36 && rect.minX > 0)
                    }
                    checked()
                }()
            }
            Color.clear
        }
    }

    func confirmFocusedSection() { handle(.confirm, data: pageData) }
}
''')
        with profile_page.open("a") as swift:
            swift.write("\nextension ProfilePage {\n    func openSettingsFixture(_ focus: Focus) { activate(focus, data: pageData) }\n}\n")
        # ImageRenderer paints any AppKit-backed view as a full-screen yellow "no entry" placeholder: the game-art
        # layer is one. Arcane itself shows the Selene backdrop there when a game has no art.
        replace(app / "Views/Spotlight/SeleneArtBackground.swift",
                r"            SeleneArtLayer\(image: art,[^\n]*\n",
                "            if let art { Image(nsImage: art).resizable().scaledToFill() }\n")
        replace(app / "Views/Theme/MoonlightRenderer.swift", r"                if let image \{\n                    Image\(decorative:",
                "                if let image = engine.snapshot(width: max(w, 1), height: max(h, 1), colors: colors) {\n                    Image(decorative:")
        # ImageRenderer does not rasterize AppKit scroll views or fields. Render their real SwiftUI contents.
        # Real Settings views, with only the AppKit-backed scroll containers flattened.
        replace(app / "Views/Settings/SettingsView.swift",
                r"        ScrollViewReader \{ proxy in\n            ScrollView \{(.*?)\n            }\n            \.scrollIndicators\(\.hidden\).*?\n        }\n    }\n\n    private var reduceMotion",
                lambda m: "        Color.clear.overlay(alignment: .top) {" + m[1] +
                "\n                .fixedSize(horizontal: false, vertical: true)\n        }.clipped()\n    }\n\n    private var reduceMotion")
        settings_view = app / "Views/Settings/SettingsView.swift"
        replace(settings_view, r"profileAccount: NextendoSettings\? = nil\) \{",
                "profileAccount: NextendoSettings? = nil, fixturePIN: String? = nil) {")
        replace(settings_view, r"profiles = viewModel.localProfiles",
                "profiles = viewModel.localProfiles\n"
                "        _pinProfileID = State(initialValue: fixturePIN != nil ? profiles?.active?.id : nil)\n"
                '        _pinAction = State(initialValue: fixturePIN == "remove" ? .remove : fixturePIN == "change" ? .change : .set)')
        replace(settings_view, r"@State private var focusArea: SettingsFocusArea = \.sidebar", "@State private var focusArea: SettingsFocusArea")
        replace(settings_view, r"_section = State\(initialValue: initialSection\)",
                "_section = State(initialValue: initialSection)\n"
                "        _focusArea = State(initialValue: initialSection == .profileIdentity ? .rows : .sidebar)")
        replace(settings_view, r"focusArea == \.rows \? focusedRow\?\.rowID : nil",
                'initialSection == .profileIdentity ? "Avatar" : focusArea == .rows ? focusedRow?.rowID : nil')
        replace(app / "Views/Settings/SettingsSidebar.swift", r"            ScrollViewReader \{ proxy in\n.*?\n            }",
                "            GeometryReader { _ in groups }.clipped()")
        with (app / "Views/Settings/SettingsView.swift").open("a") as swift:
            swift.write("\nextension SettingsView {\n    func pressScreenFixtureReset() { handleGamepad(.secondaryAction) }\n"
                        "    func pressScreenFixtureBack() { handleBack() }\n}\n")
            swift.write(SETTINGS_PIN_TEST)
        with (app / "Views/Settings/SettingsPortingStorageSection.swift").open("a") as swift:
            swift.write("\nextension SettingsPortingStorageSection {\n    func publishScreenFixtureActions() { publishActions() }\n}\n")
        picker = app / "Views/Shell/ProfilePickerView.swift"
        replace(picker, r"    private func tile\(", "    @MainActor static var haloFixtureFrame = CGRect.null\n\n    private func tile(")
        replace(picker, r"(\.scaleEffect\(isFocused && !reduceMotion \? 1\.1 : 1\))",
                lambda m: m[1] + """
                .onGeometryChange(for: CGRect?.self) { isFocused ? $0.frame(in: .global) : nil } action: {
                    if let frame = $0 { Self.haloFixtureFrame = frame }
                }""")
        # The wizard opens on the avatar step, with the game portraits the real flow loads in a task.
        replace(app / "Views/Shell/ProfilePickerView.swift", r"onSave: save\)",
                "onSave: save, step: .avatar, cachedPortraits: ProfileEditorView.loadAvatars(avatarGames, artwork: artwork!))")
        editor = app / "Views/Shell/ProfileEditorView.swift"
        replace(editor, r'TextField\(L10n.text\("Name"\), text: \$profile.name\)\n                \.textFieldStyle\(\.plain\)',
                'Text(verbatim: profile.name)')
        replace(editor, r'\n                \.focused\(\$nameFocused\)\n                \.onSubmit \{ advance\(\) \}', '')
        replace(editor, r'            ScrollViewReader \{ scroll in\n                ScrollView \{(.*?)\n                }\n                \.scrollIndicators\(\.hidden\)(.*?)\n                \.onChange\(of: index\).*?\n            }',
                lambda m: f"            Group {{{m[1]}\n            }}{m[2]}")
        # Observe the mounted editor's state without adding any test hooks to Arcane.
        replace(editor, r"    var body: some View \{\n", "    var body: some View {\n        let _ = Self.inspectFixture?(self)\n")
        with editor.open("a") as swift:
            swift.write(EDITOR_TEST)
        pin = app / "Views/Shell/AppShellView+Profiles.swift"
        replace(pin, r"(struct ProfilePINDialog: View \{.*?    var body: some View \{\n)",
                lambda m: m[1] + "        let _ = Self.inspectFixture?(self)\n")
        with pin.open("a") as swift:
            swift.write(PIN_TEST)
        replace(app / "Services/GameControllerService.swift", r"        gcSource.start\(\)\n        hidSource.start\(\)",
                "        // The probe never starts physical controller discovery.")
        api = app / "Views/Settings/SettingsAPISection.swift"
        replace(api, r"            if canContactNextendo && supportsNextendo && accountOnly \{ nextendo.check\(clientID: clientID\) \}", "")
        replace(api, r"@State private var friendsExpanded = false",
                "@State private var friendsExpanded = true")
        replace(api, r'            TextField\(text\("Friend code"\).*?\n                \.onSubmit\(sendFriendCode\)',
                '            Text(verbatim: "SW-0000-0000-0000")')
        with (package / "Sources/ArcanePorting/Launch/NextendoAccountService.swift").open("a") as swift:
            swift.write(r'''
extension NextendoAccountSnapshot {
    package static func screenFixture(second: Bool) -> Self {
        .init(name: second ? "Solar Pilot" : "Lunar Pilot", username: second ? "fixture2" : "fixture", countryCode: "FR", friendCode: "SW-4821-7305-1196", avatar: nil,
              avatarPID: nil, friends: [
                  .init(id: 2, name: "Nova", favorite: false, presence: .playing, game: "Observatory 1", gameID: "0100000000000001"),
                  .init(id: 1, name: "Sol", favorite: false, presence: .online, game: nil, gameID: nil)
              ],
              requests: [], sent: [], recentPlayers: [], failure: nil)
    }
}
''')
        with (app / "ViewModels/NextendoSettings.swift").open("a") as swift:
            swift.write(r'''
enum ProfilePresence { case connected }

extension NextendoSettings {
    func setPresenceFixture() { presenceShared = true }
    func setScreenFixture(_ presence: ProfilePresence, second: Bool = false, failure: NextendoError? = nil) {
        status = .signedIn; account = .screenFixture(second: second); accountName = account?.name
        self.failure = failure
        friendsUpdatedAt = .now.addingTimeInterval(-30)
    }
}
''')
        before = subprocess.run(
            ["git", "show", "adad00f:Sources/NXLibrary/Views/Spotlight/SpotlightTopBar.swift"],
            cwd=ROOT, text=True, capture_output=True)
        host = HOST
        if before.returncode == 0:
            (app / "LegacySpotlightTopBar.swift").write_text(
                before.stdout.replace("struct SpotlightTopBar:", "struct LegacySpotlightTopBar:"))
        else:
            # A shallow checkout still verifies current screens; only the historical panel needs this commit.
            host = re.sub(r'        try render\("12-sort-before"[^\n]+\n', "", host)
            host = re.sub(r'        let beforeImage = .*?(?=\n    })', "", host, flags=re.S)
            host = re.sub(r'    struct BeforeSortTopBar: View \{.*?\n    }\n', "", host, flags=re.S)
        (app / "ProfileScreenProbe.swift").write_text(host)
        if os.environ.get("OORT_MAC_SHORTCUT_PROBE") == "1":
            shutil.copyfile(ROOT / "Tests/CatalogAppChecks/MacShortcutProbe.swift", app / "MacShortcutProbe.swift")
            replace(app / "ProfileScreenProbe.swift", r"        try checkDeferredPlay\(vm, profiles: profiles, other: alex, game: game\)",
                    "        try checkDeferredPlay(vm, profiles: profiles, other: alex, game: game)\n"
                    "        try await checkMacShortcuts(in: out, refs: refs)\n"
                    "        L10n.setContext(fr)")
        subprocess.run(["swift", "run", "--jobs", "2", "--package-path", str(package), "ProfileScreenProbe", str(out),
                        str(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"), str(refs)],
                       check=True, env=dict(os.environ, HOME=temp, CFFIXED_USER_HOME=temp))


if __name__ == "__main__":
    main()
