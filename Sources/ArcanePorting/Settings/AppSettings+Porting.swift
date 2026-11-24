import Foundation
import NXLibraryCore

/// Porting's settings in `settings.json`, under the keys every version reads. The base keeps them as JSON
/// (`AppSettings.moduleValues`); a missing or unreadable value is its default, and an unreadable one stays in the
/// file until it is changed.
extension AppSettings {
    /// Nil leaves the older preference as a fallback until the user chooses a value here.
    public var toolchainOverride: Bool? {
        get { moduleValue("toolchainOverride", as: Bool.self) }
        set { moduleValues["toolchainOverride"] = newValue.map(CatalogJSON.bool) }
    }

    /// Optional public OAuth client ID. The token is never stored here.
    public var nextendoClientID: String? {
        get {
            moduleValues["nextendoClientID"]?.stringValue.flatMap {
                NextendoAuthorization.validClientID($0) ? $0 : nil
            }
        }
        set { moduleValues["nextendoClientID"] = newValue.map(CatalogJSON.string) }
    }

    /// What a new ported game starts with.
    public var gameDefaults: GameRuntimeConfig {
        get { moduleValue("gameDefaults", as: GameRuntimeConfig.self) ?? GameRuntimeConfig() }
        set { setModuleValue(newValue, forKey: "gameDefaults") }
    }

    /// Empty uses the display of Arcane's window at play time.
    public var gameDisplay: String {
        get { moduleValues["gameDisplay"]?.stringValue ?? "" }
        set { moduleValues["gameDisplay"] = newValue.isEmpty ? nil : .string(newValue) }
    }

    public var gameDisplayOverrides: [String: String] {
        get { moduleValue("gameDisplayOverrides", as: [String: String].self) ?? [:] }
        set { setModuleValue(newValue, forKey: "gameDisplayOverrides") }
    }

    /// The library's cloud saves folder, written into each game's preferences.
    public var cloudSaves: CloudSaves {
        get { moduleValue("cloudSaves", as: CloudSaves.self) ?? .off }
        set { setModuleValue(newValue, forKey: "cloudSaves") }
    }

    /// The last folder picked for cloud saves, so stepping back to Folder finds it.
    public var cloudSavesPickedFolder: String {
        get { moduleValues["cloudSavesPickedFolder"]?.stringValue ?? "" }
        set { moduleValues["cloudSavesPickedFolder"] = .string(newValue) }
    }

    private func moduleValue<Value: Decodable>(_ key: String, as type: Value.Type) -> Value? {
        try? moduleValues[key]?.decoded(as: type)
    }

    private mutating func setModuleValue(_ value: some Encodable, forKey key: String) {
        // Encoding these plain value types cannot fail; a failure would keep the previous value.
        if let json = try? CatalogJSON(encoding: value) { moduleValues[key] = json }
    }
}
