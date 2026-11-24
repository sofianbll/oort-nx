import AppKit
import Combine
import NXLibraryCore
import ArcanePorting

/// One inventory for change detection, previews, row details and the save summary.
enum SettingsDraftFields {
    typealias Field = AppSettingsDraft.Field

    static func fields(profiles: LocalProfileStore?, languages: [(code: String, label: String)],
                       legacyToolchainOverride: Bool = false) -> [Field] {
        let soundPacks = SoundPackLibrary().choices()
        let deadzone = GameControllerService.shared.legacyDeadzone
        let dockIcon = AppViewModel.legacyDockIcon
        return [
            .init("controllerDeadzone", \.launcherChoices.controllerDeadzone) {
                ($0 ?? deadzone).formatted(.number.precision(.fractionLength(2)).locale(L10n.context.formatLocale))
            },
            .init("iconAppearance", \.launcherChoices.dockIconAppearance, previews: true) {
                SettingsLookSection.iconMode($0 ?? dockIcon).label
            },
            .init("toolchainOverride", \.toolchainOverride, important: true) { onOff($0 ?? legacyToolchainOverride) },
            .init("multiplayerVPN", \.multiplayerVPN, important: true) { L10n.text($0.label) },
            .init("multiplayerDefault", \.multiplayerDefault, important: true) { L10n.text($0.label) },
            .init("multiplayerLocalMode", \.multiplayerLocalMode, important: true) { L10n.text($0.label) },
            .init("multiplayerAdapter", \.multiplayerAdapter, important: true) { $0 ?? L10n.text("Automatic") },
            .init("nextendoClientID", \.nextendoClientID, important: true) {
                $0 ?? L10n.text(NextendoLaunch.buildClientID == nil ? "Not set" : "Built-in value")
            },
            .init("cloudSaves", \.cloudSaves, important: true) {
                if case .folder = $0 { return "\($0.title) · \($0.detail)" }
                return $0.title
            },
            .init("cloudSavesPickedFolder", \.cloudSavesPickedFolder, important: true) {
                $0.isEmpty ? L10n.text("None chosen yet.") : CloudSaves.displayPath($0)
            },
            .init("appLanguage", \.appLanguage, previews: true) { $0.nativeName },
            .init("appRegion", \.appRegion, previews: true) {
                $0.flatMap { L10n.context.formatLocale.localizedString(forRegionCode: $0) } ?? L10n.text("Automatic (Mac)")
            },
            .init("startOn", \.startOn) {
                let title = switch $0 { case .spotlight: "Spotlight"; case .collection: "Collection"; case .last: "Where I left" }
                return L10n.text(title)
            },
            toggle("restoreLastGame", \.restoreLastGame),
            toggle("startInFullscreen", \.startInFullscreen),
            toggle("checkAppUpdatesAtLaunch", \.checkAppUpdatesAtLaunch),
            toggle("introAnimation", \.introAnimation),
            .init("showProfilePicker", \.profileStartup) { [weak profiles] in
                switch $0 {
                case .ask: L10n.text("Who's playing?")
                case .last: L10n.text("Last profile")
                case .profile(let id): profiles?.profiles.first { $0.id == id }?.name ?? L10n.text("Not selected")
                }
            },
            toggle("showButtonHints", \.showButtonHints, previews: true),
            .init("buttonNames", \.buttonNames, previews: true) {
                $0 == .automatic ? L10n.text("Automatic") : $0 == .playstation ? "PlayStation" : $0 == .xbox ? "Xbox" : "Nintendo"
            },
            toggle("viewButtonSwitches", \.viewButtonSwitches),
            .init("startingTab", \.startingTab, describe: { L10n.text($0) }),
            .init("spotlightOrder", \.spotlightOrder) {
                L10n.text($0.isEmpty ? "Spotlight uses its own order." : "Your own order of games and cards.")
            },
            toggle("interfaceSounds", \.interfaceSounds, previews: true),
            .init("soundVolume", \.soundVolume, previews: true, describe: percent),
            toggle("quietLaunch", \.quietLaunch, previews: true),
            .init("soundPack", \.soundPackID, previews: true) { id in
                soundPacks.first { $0.key == id }?.name ?? id
            },
            .init("colorThemeID", \.colorThemeID, previews: true) { id in
                ThemeStore.shared.palettes.first { $0.id == id }?.name ?? id
            },
            .init("wallpaperID", \.wallpaperID, previews: true) { ThemeStore.shared.wallpaperTitle(for: $0) },
            .init("settingsWallpaperID", \.settingsWallpaperID, previews: true) { ThemeStore.shared.settingsWallpaperTitle(for: $0) },
            .init("backgroundSizing", \.backgroundSizing, previews: true) { $0.title },
            .init("wallpaperBrightness", \.wallpaperBrightness, previews: true) { $0.title },
            toggle("animatedBackground", \.animatedBackground, previews: true),
            .init("keepWallpaperOnGames", \.keepWallpaperOnGames, previews: true) { onOff(!$0) },
            .init("backgroundShade", \.backgroundShade, previews: true) { $0.label },
            toggle("readableText", \.readableText, previews: true),
            toggle("showClock", \.showClock, previews: true),
            toggle("reduceMotion", \.reduceMotion, previews: true),
            .init("librarySort", \.librarySort) { L10n.text($0.title) },
            .init("launchStyle", \.launchStyle, previews: true) { $0.title },
            toggle("launchMotion", \.launchMotion, previews: true),
            .init("launchShade", \.launchShade, previews: true) { $0.title },
            .init("tileBadgePosition", \.tileBadgePosition, previews: true) { L10n.text($0.titleKey) },
            .init("surprisePool", \.surprisePool) {
                let title = switch $0 { case .installed: "Installed"; case .notPlayed: "Not played yet"; case .all: "All games" }
                return L10n.text(title)
            },
            toggle("showsSessionCard", \.showsSessionCard),
            .init("inGameHomeButton", \.inGameHomeButton) { L10n.text($0.title) },
            toggle("steamInBackground", \.steamInBackground),
            toggle("checkEngineAtLaunch", \.checkEngineAtLaunch),
            toggle("gameInboxEnabled", \.gameInboxEnabled),
            toggle("refreshLibraryAtLaunch", \.refreshLibraryAtLaunch),
            toggle("notifyPortingEnds", \.notifyPortingEnds),
            toggle("gameDefaults.fullscreen", \.gameDefaults.fullscreen),
            .init("gameDisplay", \.gameDisplay) { id in
                if id.isEmpty { return L10n.text(GameDisplay.likeArcane) }
                return NSScreen.screens.compactMap(GameDisplay.init(screen:)).first { $0.id.uuidString == id }?.name
                    ?? L10n.text(GameDisplay.disconnected)
            },
            toggle("gameDefaults.enable60FPS", \.gameDefaults.enable60FPS),
            toggle("gameDefaults.isDockedMode", \.gameDefaults.isDockedMode),
            toggle("gameDefaults.enableMetalFXUpscale", \.gameDefaults.enableMetalFXUpscale),
            toggle("gameDefaults.enableMetalHUD", \.gameDefaults.enableMetalHUD),
            .init("gameDefaults.language", \.gameDefaults.language) { id in
                languages.first { $0.code == id }?.label ?? (id.isEmpty ? L10n.text("Game Default") : id)
            },
            .init("gameDefaults.renderScale", \.gameDefaults.renderScale, describe: percent),
            toggle("gameDefaults.rumble", \.gameDefaults.rumble),
            .init("gameDefaults.rumbleGain", \.gameDefaults.rumbleGain) { $0.formatted(.number.locale(L10n.context.formatLocale)) },
            toggle("showsCloudPlayIcon", \.showsCloudPlayIcon, previews: true),
            toggle("showsCloudDetailsLink", \.showsCloudDetailsLink, previews: true),
            .init("cloudTileBadges", \.cloudTileBadges, previews: true) { L10n.text($0.titleKey) },
        ] + SpotlightCard.allCases.filter { $0 != .inbox }.map { card in
            toggle("card-\(card.rawValue)", \AppSettings.[spotlightCard: card])
        }
    }

    static func toggle(_ id: String, _ key: WritableKeyPath<AppSettings, Bool>, previews: Bool = false) -> Field {
        .init(id, key, previews: previews, describe: onOff)
    }

    static func onOff(_ value: Bool) -> String { L10n.text(value ? "On" : "Off") }
    private static func percent(_ value: Double) -> String { value.formatted(.percent.locale(L10n.context.formatLocale)) }

    static func row(_ id: String, in section: SettingsSection) -> String {
        if section == .startUp {
            if id == "appRegion" { return "Region" }
            if id == "restoreLastGame" { return "Restore last selected game" }
        }
        return title(id)
    }

    static func title(_ id: String) -> String {
        if let card = SpotlightCard.allCases.first(where: { id == "card-\($0.rawValue)" }) { return card.title }
        return SettingsCatalog.all.first { $0.id == id }?.title ?? id
    }

    static func effect(_ id: String) -> String? {
        switch id {
        case "multiplayerVPN": "Local play uses this VPN. macOS network settings stay unchanged."
        case "cloudSaves": "This applies to all ported games at their next launch. No saves are deleted."
        case "toolchainOverride": "This changes the build compatibility gate. Existing apps are not changed."
        default: SettingsCatalog.all.first { $0.id == id }?.about
        }
    }

    static func summary(_ changes: [AppSettingsDraft.Change]) -> String {
        changes.map { change in
            let title = L10n.text(title(change.id))
            let value = L10n.format("%@: %@ → %@", [title, change.before, change.after])
            let effect = effect(change.id).map { " — " + L10n.text($0) } ?? ""
            return "- \(value)\(effect)".replacingOccurrences(of: "\n", with: " ")
        }.joined(separator: "\n")
    }
}

/// Sections edit the draft through the same bindings they used for committed values.
final class SettingsEditor: ObservableObject {
    let store: AppSettingsStore
    private var observation: AnyCancellable?
    var settings: AppSettings {
        get { store.editingSettings }
        set { store.editingSettings = newValue }
    }

    init(_ store: AppSettingsStore) {
        self.store = store
        observation = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
}
