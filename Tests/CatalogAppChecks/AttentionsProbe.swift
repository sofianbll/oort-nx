import AppKit
import ArcanePorting
import NXLibraryCore
import SwiftUI

/// Undo, recent searches, one row back, copied settings, tips and empty screens, off screen with synthetic games.
extension SettingsConfirmationProbe {
    @MainActor static func checkAttentions(vm: AppViewModel, settings: AppSettingsStore, output: URL, locale: AppLocale,
                                          capturesOnly: Bool = false) throws {
        let root = AppData.profile.home
        func app(_ name: String, _ title: String) throws -> PortedGame {
            let url = root.appendingPathComponent("\(name).app"), dm = url.appendingPathComponent("Contents/Resources/dm")
            try FileManager.default.createDirectory(at: dm, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": "test.oort.\(title)", "DMSettings": []]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: url.appendingPathComponent("Contents/Info.plist"))
            try Data("""
            {"game":"\(name)","settings":[
              {"env":"DM_DYNAMIC_RESOLUTION","kind":"toggle","section":"Picture","label":"Dynamic resolution","default":"0","on":"1","off":"0"},
              {"env":"DM_RUMBLE","kind":"toggle","section":"Controls","label":"Rumble","default":"1","on":"1","off":"0"}
            ]}
            """.utf8).write(to: dm.appendingPathComponent("launcher.json"))
            return PortedGame(name: name, url: url, platform: .macApp, sizeBytes: 0, modificationDate: .now,
                              bundleId: "test.oort.\(title)", titleId: title)
        }
        let one = try app("Paper Racer", "010000000000F0A1"), two = try app("Moon Garden", "010000000000F0A2")
        vm.applyCatalog(try vm.catalogRepository.updateNXNativeGames { $0 += [one, two] })
        precondition(vm.libraryGames.count >= 2)

        let homeRouter = AppRouter(settings: settings)
        homeRouter.setInitialRoute(.library)
        let artwork = ArtworkStore(), running = RunningGameMonitor(), storeHost = ModStoreHost()
        let sessions = PlaySessionStore(fileURL: root.appendingPathComponent("att-home-sessions.json"))
        func withHost<V: View>(_ view: V, _ locale: AppLocale, size: CGSize = .init(width: 1440, height: 810), light: Bool = false,
                               home: Bool = false,
                               _ check: (() -> Void, (String) throws -> Void) throws -> Void) throws {
            let old = L10n.context
            L10n.setContext(locale)
            defer { L10n.setContext(old) }
            let host = NSHostingView(rootView: ZStack {
                if home {
                    SpotlightView(viewModel: vm, router: homeRouter, settings: settings, playSessions: sessions,
                                  runningGames: running, artwork: artwork, storeHost: storeHost)
                        .environment(\.seleneShowButtonHints, false)
                } else if light { Color.white } else { SeleneBackdrop(still: true) }
                view
            }
                .environment(\.nxAppLocale, locale)
                .environment(\.colorScheme, .dark)
                .environment(\.seleneShowButtonHints, true)
                .environment(\.seleneButtonNames, .nintendo)
                .environment(\.seleneReduceMotion, true)
                .seleneCanvasRoot(zoom: CGFloat(Double(ProcessInfo.processInfo.environment["OORT_ZOOM"] ?? "") ?? 1)))
            host.frame.size = size
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            window.layoutIfNeeded()
            func settle() {
                for _ in 0..<10 {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.016))
                    host.layoutSubtreeIfNeeded()
                }
            }
            settle()
            try check(settle) { name in
                precondition(!window.isVisible)
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("att-\(name).png"))
            }
        }
        let locales = [("fr", locale), ("de", AppLocale(language: .german, region: "DE")), ("en", AppLocale(language: .english, region: "US"))]
        for (tag, locale) in capturesOnly ? [] : locales {
            L10n.setContext(locale)
            // Favorite, hide, then their way back.
            vm.toggleFavorite(one)
            precondition(vm.undoOffers.offer == nil, "Adding shows itself")
            vm.toggleFavorite(one)
            precondition(vm.undoOffers.perform() && vm.libraryGames.first { $0.id == one.id }?.isFavorite == true)
            vm.toggleFavorite(one)
            vm.toggleHidden(one)
            precondition(vm.libraryGames.first { $0.id == one.id }?.isHidden == true)
            for light in [false, true] {
                try withHost(UndoNoticeLayer(offers: vm.undoOffers, tips: vm.tips, isBlocked: false, isBelowCard: false,
                                             focus: .constant(NoticeFocus()), onUndo: {}, onTurnOffTips: {}), locale, light: light) { _, capture in
                    try capture("avis-\(light ? "clair-" : "")\(tag)")
                }
            }
            // Chosen: lit, its own hints, nothing done until A, and B gives the screen back.
            let chooser = Input(viewModel: vm)
            vm.undoOffers.offer(L10n.text("Recent searches cleared")) {}
            chooser.noticeInput(.confirm)
            precondition(vm.undoOffers.offer != nil, "Nothing acts before it is chosen")
            // A pad in hand for the next pictures, whatever this Mac has connected.
            GameControllerService.shared.isGamepadConnected = true
            GameControllerService.shared.handleInput(.button(.r3, true))
            chooser.chooseNotice()
            precondition(vm.noticeFocus.index == 0 && vm.shellDialogOwnsInput, "The screen leaves the keys")
            try withHost(UndoNoticeLayer(offers: vm.undoOffers, tips: vm.tips, isBlocked: false, isBelowCard: false,
                                         focus: .constant(vm.noticeFocus), onUndo: {}, onTurnOffTips: {}), locale) { _, capture in
                try capture("avis-choisi-\(tag)")
            }
            try withHost(UndoNoticeLayer(offers: vm.undoOffers, tips: vm.tips, isBlocked: false, isBelowCard: false,
                                         focus: .constant(NoticeFocus()), onUndo: {}, onTurnOffTips: {}), locale) { _, capture in
                try capture("avis-manette-\(tag)")
            }
            chooser.noticeInput(.cancel)
            precondition(!vm.noticeFocus.isActive && !vm.shellDialogOwnsInput && vm.undoOffers.offer != nil)
            chooser.chooseNotice()
            chooser.noticeInput(.confirm)
            precondition(vm.undoOffers.offer == nil && !vm.noticeFocus.isActive)
            var chosenTip = NoticeFocus()
            chosenTip.enter(keys: 2)
            chosenTip.move(by: 1)
            try withHost(TipNotice(tip: .search, onClose: {}, onTurnOff: {}), locale) { _, capture in try capture("astuce-manette-\(tag)") }
            try withHost(TipNotice(tip: .search, focus: chosenTip.index, onClose: {}, onTurnOff: {}), locale) { _, capture in
                try capture("astuce-choisie-\(tag)")
            }
            vm.toggleHidden(one)
            vm.toggleHidden(one)
            var focus = ActivityCenterFocus()
            focus.selected = ActivityCenterView.rows(vm).first
            precondition(focus.selected == .undo)
            try withHost(ActivityCenterView(viewModel: vm, porting: vm.porting, cloudLibrary: vm.cloudLibrary, focus: focus,
                onFocus: { _ in }, onOpen: { _ in }, onCancel: { _ in }, onBack: {}, onOutside: {}), locale) { _, capture in
                try capture("activite-\(tag)")
            }
            precondition(vm.undoOffers.perform() && vm.libraryGames.first { $0.id == one.id }?.isHidden == false)
            for tip in Tip.allCases {
                try withHost(TipNotice(tip: tip, onClose: {}, onTurnOff: {}), locale) { _, capture in try capture("astuce-\(tip.rawValue)-\(tag)") }
            }

            // Recent searches.
            let recent = RecentSearches(defaults: AppData.preferences, profile: vm.localProfiles?.active?.id)
            for query in ["mario", "zelda", "moon"] { recent.record(query) }
            let router = AppRouter(settings: settings)
            router.isSearchPresented = true
            try withHost(FindGameView(router: router, viewModel: vm, playSessions: vm.playSessionStore ?? PlaySessionStore(fileURL: output.appendingPathComponent("att-sessions.json")), artwork: ArtworkStore()), locale) { settle, capture in
                func send(_ action: GamepadAction) { NotificationCenter.default.post(name: .nxFindGameGamepadAction, object: action); settle() }
                send(.navigateDown)
                try capture("recherches-\(tag)")
                for _ in 0..<3 { send(.navigateDown) }
                send(.confirm)
                precondition(recent.list.isEmpty, "The last row erases them")
                try capture("recherches-effacees-\(tag)")
                precondition(vm.undoOffers.perform() && recent.list == ["moon", "zelda", "mario"])
                send(.navigateDown)
                send(.confirm)
                try capture("recherche-choisie-\(tag)")
            }

            // Copy: the preview, nothing before Copy, then the way back.
            precondition(vm.runtimeSettings.setGameSetting("DM_RUMBLE", to: "0", for: one))
            precondition(vm.runtimeSettings.setGameSetting("DM_DYNAMIC_RESOLUTION", to: "1", for: one))
            let targets = vm.runtimeSettings.copyTargets(for: one)
            precondition(targets.map(\.game.id) == [two.id] && targets[0].copy.changes.count == 2)
            vm.gameForSettingsSheet = one
            let input = Input(viewModel: vm)
            try withHost(ZStack {
                CopySettingsPanel(viewModel: vm, game: one, targets: targets, onClose: {})
            }, locale) { settle, capture in
                try capture("copie-liste-\(tag)")
                NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: GamepadAction.confirm)
                settle()
                precondition(vm.settingsNotice != nil && vm.runtimeSettings.settingsSnapshot(for: two)?.value("DM_RUMBLE") == "1")
            }
            try withHost(input.settingsNoticeOverlay(vm.settingsNotice!), locale) { _, capture in try capture("copie-apercu-\(tag)") }
            let originalPreview = vm.settingsNotice!.id
            precondition(vm.runtimeSettings.setGameSetting("DM_DYNAMIC_RESOLUTION", to: "1", for: two))
            input.settingsNoticeInput(.navigateRight)
            input.settingsNoticeInput(.confirm)
            precondition(vm.settingsNotice?.id != originalPreview && vm.settingsNotice?.notes != nil
                         && vm.runtimeSettings.settingsSnapshot(for: two)?.value("DM_RUMBLE") == "1",
                         "A different plan needs a fresh answer")
            input.settingsNoticeInput(.navigateRight)
            input.settingsNoticeInput(.confirm)
            precondition(vm.runtimeSettings.settingsSnapshot(for: two)?.value("DM_RUMBLE") == "0")
            precondition(vm.runtimeSettings.setGameSetting("DM_DYNAMIC_RESOLUTION", to: "0", for: two))
            precondition(vm.undoOffers.perform() && vm.runtimeSettings.settingsSnapshot(for: two)?.value("DM_RUMBLE") == "1")
            precondition(vm.runtimeSettings.settingsSnapshot(for: two)?.value("DM_DYNAMIC_RESOLUTION") == "0",
                         "Undo leaves an unrelated edit alone")
            vm.gameForSettingsSheet = nil
            for env in ["DM_RUMBLE": "1", "DM_DYNAMIC_RESOLUTION": "0"] { vm.runtimeSettings.setGameSetting(env.key, to: env.value, for: one) }

            vm.gameForSettingsSheet = one
            try withHost(GameOptionsView(viewModel: vm, game: one, origin: .details, onClose: {}, onShowBuild: {}, onMove: {}), locale) { settle, capture in
                func send(_ action: GamepadAction) { NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: action); settle() }
                for _ in 0..<12 { send(.navigateDown) }
                send(.confirm)
                send(.confirm)
                for _ in 0..<12 { send(.navigateDown) }
                try capture("options-general-\(tag)")
            }
            vm.gameForSettingsSheet = nil
            vm.settingsNotice = nil // The earlier panel, kept alive by AppKit, answered too.

            // One row back alone, in the draft.
            settings.beginDraft(fields: SettingsDraftFields.fields(profiles: nil, languages: vm.availableLanguages, cloudEnabled: true))
            let editor = SettingsEditor(settings)
            editor.settings.showsTips = false
            editor.settings.viewButtonSwitches = false
            let settingsRouter = AppRouter(settings: settings)
            settingsRouter.openSettings(.navigation, rowID: "showsTips")
            let sources = CatalogSourcesModel(
                repository: CatalogRepository(store: .init(directory: output.appendingPathComponent("att-catalog-\(tag)"))),
                initialConfiguration: .init(integration: .steam)) { _ in }
            try withHost(SettingsView(initialSection: .navigation, viewModel: vm, settings: settings, router: settingsRouter, artwork: ArtworkStore())
                .environmentObject(sources).environmentObject(AppUpdater()), locale) { settle, capture in
                func send(_ action: GamepadAction) { NotificationCenter.default.post(name: .nxSettingsGamepadAction, object: action); settle() }
                // A row at its default still resets the group; a changed row only itself.
                try capture("reglages-ligne-\(tag)")
                // Later languages are captures only: AppKit keeps the first host alive, and it would answer too.
                guard tag == "fr" else { return }
                send(.secondaryAction)
                precondition(settings.editingSettings.showsTips && !settings.editingSettings.viewButtonSwitches,
                             "X puts back the focused row alone: \(settings.editingSettings.showsTips) \(settings.editingSettings.viewButtonSwitches)")
                try capture("reglages-remis-\(tag)")
                precondition(vm.undoOffers.perform() && !settings.editingSettings.showsTips, "Undo puts the row back")
                settle()
                send(.secondaryAction)
                send(.secondaryAction)
                let group = vm.settingsNotice!
                precondition(!settings.editingSettings.viewButtonSwitches, "The group asks first")
                vm.settingsNotice = nil
                group.runAnswer(.alternative(0))
                precondition(settings.editingSettings.viewButtonSwitches, "The group stays one press away")
            }
            settings.endDraft()
        }
        L10n.setContext(locale)
        vm.homeSeen = true
        vm.showSetupCheck = false
        settings.settings.gameInboxEnabled = false
        settings.settings.startingTab = LibraryFilter.all.rawValue
        settings.settings.visibleSpotlightCards = [.addGame]
        vm.applyCatalog(try vm.catalogRepository.transaction { catalog in
            if let source = catalog.sources.firstIndex(where: { $0.integration == .nxnative }) {
                catalog.sources[source].isEnabled = true
            } else {
                catalog.sources.append(.init(integration: .nxnative, isEnabled: true))
            }
        })
        for (game, colors, symbol) in [(one, [Color.indigo, .black], "flag.checkered"),
                                       (two, [Color.teal, .black], "moon.stars")] {
            let art = ImageRenderer(content: LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { Image(systemName: symbol).font(.largeTitle).foregroundStyle(.white) }
                .frame(width: 420, height: 420))
            let png = NSBitmapImageRep(cgImage: art.cgImage!).representation(using: .png, properties: [:])!
            try ArtworkPicks.shared.save(png, titleID: game.titleId!, slot: .icon)
        }
        precondition(vm.visibleCatalogGames.count >= 2, "The fixture source and both games must be visible on Spotlight")
        vm.spotlight.select(.game(one.id))
        var chosen = NoticeFocus()
        chosen.enter(keys: 1)
        vm.undoOffers.offer(L10n.text("Recent searches cleared")) {}
        try withHost(UndoNoticeLayer(offers: vm.undoOffers, tips: vm.tips, isBlocked: false, isBelowCard: false,
                                     focus: .constant(chosen), onUndo: {}, onTurnOffTips: {}), locale, home: true) { _, capture in
            try capture("accueil-avis-fr")
        }
        vm.undoOffers.drop()
        let tips = Tips(defaults: UserDefaults(suiteName: root.appendingPathComponent("att-home-tips").path)!)
        tips.libraryAppeared(games: Tips.longLibrary, enabled: true)
        precondition(tips.shown == .search)
        chosen.enter(keys: 2)
        chosen.move(by: 1)
        try withHost(UndoNoticeLayer(offers: vm.undoOffers, tips: tips, isBlocked: false, isBelowCard: false,
                                     focus: .constant(chosen), onUndo: {}, onTurnOffTips: {}), locale, home: true) { _, capture in
            try capture("accueil-astuce-fr")
        }
        account = RcloneAccount(hasClient: true, isSignedIn: true)
        vm.cloudLibrary.configure(remote: "fixture", root: "Games", enabled: false, sourcesRoot: nil)
        defer { account = nil }
        SettingsCloudLibrarySection(viewModel: vm, model: vm.cloudLibrary, settings: SettingsEditor(settings),
            advanced: .constant(true), onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in }).confirmDisconnect()
        let input = Input(viewModel: vm)
        let dialog = vm.settingsNotice!
        try withHost(input.settingsNoticeOverlay(dialog), locale, home: true) { _, capture in
            try capture("accueil-drive-fr")
        }
        input.settingsNoticeInput(.cancel)
        print(capturesOnly ? "Attentions: three French captures on Spotlight with two synthetic games."
            : "Attentions: undo, recent searches, one row back, copy and its way back passed.")
    }

    /// X held reaches the notice; X alone keeps its role, also when the notice leaves before the release.
    @MainActor static func checkNoticeHold() async throws {
        for layout in GamepadLayout.allCases {
            for browsing in [false, true] {
                for row in layout.bindings(browsing: browsing) {
                    let over = GamepadLayout.noticeBinding(over: row)
                    precondition(over.tap == row.tap && over.hold == (row.button == .x ? .notice : row.hold), "\(layout) \(row.button)")
                }
            }
        }
        let service = GameControllerService.shared
        let before = (service.onAction, service.showsNotice, service.onPadUse)
        defer { (service.onAction, service.showsNotice, service.onPadUse) = before }
        var actions: [GamepadAction] = [], shows = true
        service.onAction = { actions.append($0) }
        service.onPadUse = nil
        service.showsNotice = { shows }
        // The service answers on the next turn of the main queue, which a nested run loop does not drain.
        func wait(_ milliseconds: Int) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }
        func x(_ pressed: Bool) async throws { service.handleInput(.button(.x, pressed)); try await wait(50) }
        try await x(true); try await x(false)
        precondition(actions == [.secondaryAction], "Tap: \(actions)")
        actions = []
        try await x(true); try await wait(700); try await x(false)
        precondition(actions == [.notice], "Hold: \(actions)")
        actions = []
        try await x(true); shows = false; try await x(false)
        precondition(actions == [.secondaryAction], "The notice left first: \(actions)")
        actions = []
        try await x(true)
        precondition(actions == [.secondaryAction], "Without a notice X acts at once: \(actions)")
        try await x(false)
        print("Notice gesture: X tapped, held, outlived and without a notice passed.")
    }
}

extension SettingsConfirmationProbe.Input {
    /// The shell's own keys, without the screens it asks about.
    @MainActor var noticeKeys: [() -> Void] { viewModel.undoOffers.offer == nil ? [] : [{ viewModel.undoOffers.perform() }] }
}
