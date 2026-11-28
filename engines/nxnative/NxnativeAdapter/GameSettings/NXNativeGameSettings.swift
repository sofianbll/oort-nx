import Foundation
import OortLibrary

/// A game's settings as they apply now: the build's list, each setting's value, and the keys the player's
/// `env.txt` sets, which win in the engine and so cannot be changed here.
public struct GameSettingsSnapshot: Equatable {
    public let settings: [LauncherSetting]
    public let values: [String: String]
    public let fixed: Set<String>
    public let savedMultiplayerMode: MultiplayerMode?

    public init(settings: [LauncherSetting], values: [String: String], fixed: Set<String>,
                savedMultiplayerMode: MultiplayerMode? = nil) {
        self.settings = settings
        self.values = values
        self.fixed = fixed
        self.savedMultiplayerMode = savedMultiplayerMode
    }

    public func setting(_ env: String) -> LauncherSetting? { settings.first { $0.env == env } }
    public func value(_ env: String) -> String? { values[env] }
    public func isOffered(_ env: String) -> Bool { setting(env) != nil }

    /// Offered, and its `needs` holds.
    public func visible(_ env: String) -> Bool {
        setting(env)?.needsSatisfied(values) ?? false
    }
}

public enum GameSettingsError: LocalizedError, Equatable {
    case notOffered(String)
    case refused(String, String)

    public var errorDescription: String? {
        switch self {
        case .notOffered(let env): return L10n.format("This build has no %@ setting.", [String(describing: env)])
        case .refused(let env, let value): return L10n.format("This build does not take %@=%@.", [String(describing: env), String(describing: value)])
        }
    }
}

/// The settings of a game built with saved choices (its Info.plist has DMSettings): kept as `launcher.<env>` in the
/// app's preferences domain, where they differ from the build's tested default. A build
/// from before saved choices has no adapter and keeps `env.txt` (`GameRuntimeConfig.save`).
public struct NXNativeGameSettings {
    public static let remotePlayKey = "DM_NET_VPN"
    private static let interfaceKey = "DM_NETWORK_INTERFACE"
    private static let multiplayerKey = "arcaneMultiplayerMode"
    /// The keys NX Library wrote into every game's env.txt up to 0.1.2.
    public static let managedKeys: Set<String> = [
        "DM_FPS_TARGET", "DM_METAL_HUD", "DM_OPMODE", "DM_RENDER_SCALE", "DM_PRESENT_UPSCALE",
        "DM_LANG", "DM_RUMBLE", "DM_RUMBLE_GAIN", "DM_FULLSCREEN",
    ]

    public let settings: [LauncherSetting]
    public let domain: String
    public let envURL: URL
    private let bundleEnvURL: URL
    private let store: SavedChoicesStore
    private let preferences: UserDefaults
    private let legacyKey: String

    public static func forGame(_ game: PortedGame,
                               store: SavedChoicesStore = SystemSavedChoices(),
                               supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                                   .appendingPathComponent("Library/Application Support/nxnative"),
                               preferences: UserDefaults = AppData.preferences) -> NXNativeGameSettings? {
        guard let titleId = game.titleId, !titleId.isEmpty else { return nil }
        let plist = game.url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["DMSettings"] is [Any],
              let file = LauncherSettingsReader.load(for: game.url),
              let domain = (info["CFBundleIdentifier"] as? String) ?? game.effectiveBundleId else { return nil }
        return NXNativeGameSettings(
            settings: file.settings, domain: domain,
            envURL: supportDirectory.appendingPathComponent(titleId).appendingPathComponent("env.txt"),
            bundleEnvURL: game.url.appendingPathComponent("Contents/Resources/dm/env.txt"),
            store: store, preferences: preferences, legacyKey: GameRuntimeConfig.storageKey(for: game))
    }

    private func setting(_ env: String) -> LauncherSetting? { settings.first { $0.env == env } }

    // MARK: - Migration

    /// Moves the lines NX Library wrote into env.txt to saved choices: each managed key this build offers and
    /// accepts, replacing a saved choice (the env.txt line is what the game used). Every other line stays; a file
    /// with no settings left is removed. NX Library's own copy in its preferences goes too. Safe to repeat.
    public func migrate() throws {
        preferences.removeObject(forKey: legacyKey)
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else { return }
        var kept: [String] = []
        var moved = false
        for line in text.components(separatedBy: "\n") {
            if let (key, value) = Self.pair(line), Self.managedKeys.contains(key),
               let setting = setting(key), setting.accepts(value) {
                try store.set(setting.isDefault(value) ? nil : value, key, domain: domain)
                moved = true
            } else {
                kept.append(line)
            }
        }
        guard moved else { return }
        while kept.last == "" { kept.removeLast() }
        if kept.contains(where: { Self.pair($0) != nil }) {
            try (kept.joined(separator: "\n") + "\n").write(to: envURL, atomically: true, encoding: .utf8)
        } else {
            try FileManager.default.removeItem(at: envURL)
        }
    }

    // MARK: - Reading and writing

    /// The value Play's child process sees. Does not migrate or change a saved choice.
    public func effectiveLaunchValue(_ env: String,
                                     environment: [String: String] = NSWorkspaceLauncher.inheritedGameEnvironment()) -> String? {
        guard let setting = setting(env) else { return nil }
        return explicitLaunchValue(env, environment: environment) ?? setting.defaultValue
    }

    public func multiplayerLaunch(settings app: AppSettings, adapters: RemotePlayAdapters,
                                  environment: [String: String] = NSWorkspaceLauncher.inheritedGameEnvironment())
        -> (environment: [String: String], warning: RemotePlayAdapters.Connection?) {
        let key = NextendoLaunch.networkKey
        guard let network = NextendoLaunch.networkSetting(in: settings) else { return ([:], nil) }
        let mode = multiplayerMode(default: app.multiplayerDefault, environment: environment)
        let explicit = explicitLaunchValue(key, environment: environment, includeSavedChoices: false)
        let selected: String
        switch mode {
        case .offline: selected = "offline"
        case .online: selected = "nextendo"
        case .local:
            let preferred = app.multiplayerLocalMode.rawValue
            // shortcut: auto also enables Nextendo on online builds, use LDN until the engine offers local-only auto.
            let safe = preferred == "auto" && network.accepts("nextendo") ? "ldn" : preferred
            selected = ([safe] + (network.accepts("nextendo") ? [] : ["auto"]) + ["ldn", "lan"])
                .first(where: network.accepts) ?? "offline"
        }
        let effective = explicit ?? selected
        var overrides: [String: String] = network.accepts(selected) && explicit == nil ? [key: selected] : [:]
        guard ["ldn", "lan", "auto"].contains(effective),
              explicitLaunchValue(Self.remotePlayKey, environment: environment, includeSavedChoices: false) == nil,
              explicitLaunchValue(Self.interfaceKey, environment: environment, includeSavedChoices: false) == nil
        else { return (overrides, nil) }
        if setting(Self.remotePlayKey)?.accepts("0") == true { overrides[Self.remotePlayKey] = "0" }
        if let local = adapters.localInterface { overrides[Self.interfaceKey] = local }
        let connection = adapters.connection(for: app.multiplayerVPN, manual: app.multiplayerAdapter)
        if app.multiplayerVPN == .none {
            if app.multiplayerAdapter != nil, case .connected(let name, _) = connection {
                overrides[Self.interfaceKey] = name
            }
            return (overrides, nil)
        }
        guard setting(Self.remotePlayKey)?.accepts("1") == true else { return (overrides, .disconnected) }
        if case .connected(let name, _) = connection {
            overrides[Self.remotePlayKey] = "1"
            overrides[Self.interfaceKey] = name
            return (overrides, nil)
        }
        return (overrides, connection)
    }

    public func multiplayerMode(default defaultMode: MultiplayerMode, environment: [String: String] = [:]) -> MultiplayerMode {
        let key = NextendoLaunch.networkKey
        let offered = Self.multiplayerModes(in: settings)
        let explicit = explicitLaunchValue(key, environment: environment, includeSavedChoices: false)
        let mode = explicit.flatMap(Self.mode) ?? savedMultiplayerMode() ?? defaultMode
        return offered.contains(mode) ? mode : .offline
    }

    public func setMultiplayerMode(_ mode: MultiplayerMode) throws {
        guard Self.multiplayerModes(in: settings).contains(mode) else {
            throw GameSettingsError.refused(NextendoLaunch.networkKey, mode.rawValue)
        }
        try store.set(mode.rawValue, Self.multiplayerKey, domain: domain)
    }

    private func savedMultiplayerMode() -> MultiplayerMode? {
        let network = NextendoLaunch.networkKey
        if let saved = store.value(Self.multiplayerKey, domain: domain).flatMap(MultiplayerMode.init(rawValue:)) {
            return saved
        }
        if let legacy = store.value(network, domain: domain).flatMap(Self.mode) { return legacy }
        // The old VPN switch did not enable multiplayer by itself.
        if store.value(Self.remotePlayKey, domain: domain) == "1",
           setting(network)?.defaultValue.flatMap(Self.mode) == .local { return .local }
        return nil
    }

    private static func mode(_ value: String) -> MultiplayerMode? {
        switch value {
        case "offline": return .offline
        case "ldn", "lan", "auto": return .local
        case "nextendo": return .online
        default: return nil
        }
    }

    private func explicitLaunchValue(_ env: String, environment: [String: String],
                                     includeSavedChoices: Bool = true) -> String? {
        if let inherited = environment[env] { return inherited }
        var ignoreSaved = environment["DM_SAVED_CHOICES"]
        for url in [envURL, bundleEnvURL] {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                guard let equals = trimmed.firstIndex(of: "=") else { continue }
                let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
                // The host preserves whitespace immediately after '='.
                let value = trimmed[trimmed.index(after: equals)...]
                if key == env { return String(value) }
                if key == "DM_SAVED_CHOICES", ignoreSaved == nil { ignoreSaved = String(value) }
            }
        }
        if includeSavedChoices, ignoreSaved != "0",
           let saved = store.value(env, domain: domain), setting(env)?.accepts(saved) == true {
            return saved
        }
        return nil
    }

    /// What each setting is now: the player's env.txt, then a saved choice this build accepts, then the default.
    public func snapshot(migrating: Bool = true) -> GameSettingsSnapshot {
        if migrating { try? migrate() }
        let env = envValues()
        var values: [String: String] = [:]
        var fixed: Set<String> = []
        for setting in settings {
            if let value = env[setting.env] {
                values[setting.env] = value
                fixed.insert(setting.env)
            } else if let saved = store.value(setting.env, domain: domain), setting.accepts(saved) {
                values[setting.env] = saved
            } else {
                values[setting.env] = setting.defaultValue ?? ""
            }
        }
        return GameSettingsSnapshot(settings: settings, values: values, fixed: fixed, savedMultiplayerMode: savedMultiplayerMode())
    }

    public static func multiplayerMode(in snapshot: GameSettingsSnapshot, default defaultMode: MultiplayerMode) -> MultiplayerMode {
        let explicit = snapshot.fixed.contains(NextendoLaunch.networkKey) ? snapshot.value(NextendoLaunch.networkKey) : nil
        let mode = explicit.flatMap(Self.mode) ?? snapshot.savedMultiplayerMode ?? defaultMode
        return snapshot.multiplayerModes.contains(mode) ? mode : .offline
    }

    /// The build default removes the key.
    public func set(_ env: String, to value: String) throws {
        guard let setting = setting(env) else { throw GameSettingsError.notOffered(env) }
        guard setting.accepts(value) else { throw GameSettingsError.refused(env, value) }
        try store.set(setting.isDefault(value) ? nil : value, env, domain: domain)
    }

    /// Every setting back to the build's tested default.
    public func resetAll() throws {
        for setting in settings { try store.set(nil, setting.env, domain: domain) }
        try store.set(nil, Self.multiplayerKey, domain: domain)
    }

    /// The raw choices kept for this game, to put back exactly. Nothing from env.txt, which is the player's own file.
    public func savedChoices() -> [String: String] {
        (settings.map(\.env) + [Self.multiplayerKey]).reduce(into: [:]) { $0[$1] = store.value($1, domain: domain) }
    }

    /// Puts back the requested keys exactly as `savedChoices` read them, including absent keys.
    public func restore(_ choices: [String: String], only keys: Set<String>? = nil) throws {
        for env in settings.map(\.env) + [Self.multiplayerKey] where keys?.contains(env) != false {
            try store.set(choices[env], env, domain: domain)
        }
    }

    // MARK: - The typed view

    /// The typed settings Add game and the new-game defaults use, from the values that apply now.
    public func runtimeConfig() -> GameRuntimeConfig {
        var config = GameRuntimeConfig.parseEnvContent((try? String(contentsOf: envURL, encoding: .utf8)) ?? "")
        let values = snapshot().values
        if let v = values["DM_FPS_TARGET"] { config.enable60FPS = v != "30" }
        if let v = values["DM_METAL_HUD"] { config.enableMetalHUD = v == "1" }
        if let v = values["DM_OPMODE"] { config.isDockedMode = v != "0" }
        if let v = values["DM_RENDER_SCALE"], let x = LauncherSetting.number(v) { config.renderScale = x }
        if let v = values["DM_PRESENT_UPSCALE"] { config.enableMetalFXUpscale = v == "metalfx" }
        if let v = values["DM_LANG"], !v.isEmpty { config.language = v }
        if let v = values["DM_RUMBLE"] { config.rumble = v != "0" }
        if let v = values["DM_RUMBLE_GAIN"], let x = LauncherSetting.number(v) { config.rumbleGain = Int(x.rounded()) }
        if let v = values["DM_FULLSCREEN"] { config.fullscreen = v == "1" }
        return config
    }

    /// Writes the typed fields `config` changed from `base`, where this build offers and takes them: a value the
    /// typed view cannot show (120 fps, a 0.5 strength) stays unless the player changed that field.
    public func apply(_ config: GameRuntimeConfig, changedFrom base: GameRuntimeConfig) throws {
        let new = typedValues(config)
        let old = typedValues(base)
        for (env, value) in new where old[env] != value {
            guard let setting = setting(env), setting.accepts(value) else { continue }
            try store.set(setting.isDefault(value) ? nil : value, env, domain: domain)
        }
    }

    private func typedValues(_ c: GameRuntimeConfig) -> [String: String] {
        [
            "DM_FPS_TARGET": c.enable60FPS ? "60" : "30",
            "DM_METAL_HUD": c.enableMetalHUD ? "1" : "0",
            "DM_OPMODE": c.isDockedMode ? "1" : "0",
            "DM_RENDER_SCALE": LauncherSetting.rangeString(c.renderScale),
            "DM_PRESENT_UPSCALE": c.enableMetalFXUpscale ? "metalfx" : "off",
            // "auto" is the build's own language.
            "DM_LANG": c.language == "auto" || c.language.isEmpty ? (setting("DM_LANG")?.defaultValue ?? "") : c.language,
            "DM_RUMBLE": c.rumble ? "1" : "0",
            "DM_RUMBLE_GAIN": LauncherSetting.rangeString(Double(c.rumbleGain)),
            "DM_FULLSCREEN": c.fullscreen ? "1" : "0",
        ]
    }

    // MARK: - env.txt

    public static func playerEnvironment(for game: PortedGame,
                                         supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                                             .appendingPathComponent("Library/Application Support/nxnative")) -> String? {
        guard let titleID = game.titleId, ImportService.normalizedTitleId(titleID) != nil else { return nil }
        let file = supportDirectory.appendingPathComponent(titleID).appendingPathComponent("env.txt")
        return try? String(contentsOf: file, encoding: .utf8)
    }

    private func envValues() -> [String: String] {
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            if let (key, value) = Self.pair(line), values[key] == nil { values[key] = value }
        }
        return values
    }

    /// A `KEY=VALUE` line, as the launcher reads it; nil for comments and blank lines.
    static func pair(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
        let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return (key, trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces))
    }
}
