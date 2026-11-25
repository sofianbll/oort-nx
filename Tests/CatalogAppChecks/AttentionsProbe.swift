import AppKit
import ArcanePorting
import NXLibraryCore
import SwiftUI

/// Undo, recent searches, one row back, copied settings, tips and empty screens, off screen with synthetic games.
extension SettingsConfirmationProbe {
    @MainActor static func checkAttentions(vm: AppViewModel, settings: AppSettingsStore, output: URL, locale: AppLocale) throws {
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

        func withHost<V: View>(_ view: V, _ locale: AppLocale, size: CGSize = .init(width: 1440, height: 810), light: Bool = false,
                               _ check: (() -> Void, (String) throws -> Void) throws -> Void) throws {
            let old = L10n.context
            L10n.setContext(locale)
            defer { L10n.setContext(old) }
            let host = NSHostingView(rootView: ZStack { if light { Color.white } else { SeleneBackdrop(still: true) }; view }
                .environment(\.nxAppLocale, locale)
                .environment(\.colorScheme, .dark)
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
        for (tag, locale) in locales {
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
                                             onUndo: {}, onTurnOffTips: {}), locale, light: light) { _, capture in
                    try capture("avis-\(light ? "clair-" : "")\(tag)")
                }
            }
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
            input.settingsNoticeInput(.navigateLeft)
            input.settingsNoticeInput(.confirm)
            precondition(vm.runtimeSettings.settingsSnapshot(for: two)?.value("DM_RUMBLE") == "0")
            precondition(vm.undoOffers.perform() && vm.runtimeSettings.settingsSnapshot(for: two)?.value("DM_RUMBLE") == "1")
            vm.gameForSettingsSheet = nil
            for env in ["DM_RUMBLE": "1", "DM_DYNAMIC_RESOLUTION": "0"] { vm.runtimeSettings.setGameSetting(env.key, to: env.value, for: one) }

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
                send(.secondaryAction)
                precondition(settings.editingSettings.viewButtonSwitches, "The group stays one press away")
            }
            settings.endDraft()
        }
        L10n.setContext(locale)
        print("Attentions: undo, recent searches, one row back, copy and its way back passed.")
    }
}
