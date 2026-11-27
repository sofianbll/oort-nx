import Foundation
import OortLibrary

/// What copying one game's settings to another would change: only what both builds offer, the other build takes and
/// its env.txt leaves free. Network play stays each game's own choice.
public struct GameSettingsCopy: Equatable {
    public struct Change: Equatable, Identifiable {
        public var id: String { env }
        public let env: String
        public let value: String
        public let label: String
        public let from: String
        public let to: String

        public var line: String { L10n.format("%@: %@ → %@", [L10n.text(label), L10n.text(from), L10n.text(to)]) }
    }

    static let excluded: Set<String> = [NextendoLaunch.networkKey, NXNativeGameSettings.remotePlayKey, "DM_NETWORK_INTERFACE"]
    public let changes: [Change]

    public init(from source: GameSettingsSnapshot, to target: GameSettingsSnapshot) {
        changes = target.settings.compactMap { setting in
            guard !Self.excluded.contains(setting.env), !target.fixed.contains(setting.env), source.isOffered(setting.env),
                  let value = source.value(setting.env), setting.accepts(value) else { return nil }
            let current = target.value(setting.env) ?? setting.defaultValue ?? ""
            guard current != value else { return nil }
            return Change(env: setting.env, value: value, label: setting.label,
                          from: GameSettingValues.label(setting, current), to: GameSettingValues.label(setting, value))
        }
    }
}

extension NXNativeGameSettings {
    /// All of it or none of it.
    public func apply(_ copy: GameSettingsCopy) throws {
        let before = savedChoices()
        do { for change in copy.changes { try set(change.env, to: change.value) } }
        catch {
            try? restore(before, only: Set(copy.changes.map(\.env)))
            throw error
        }
    }
}
