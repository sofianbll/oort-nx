import Foundation
import NXLibraryCore

/// The Mac's observations that only its own owners can say, as the core's integration facts. No decision here:
/// IntegrationFacts.row decides each entry.
public enum IntegrationOverview {
    /// What the Mac offers and has: its entries, and a settings row for each. Its owners' facts are filled on top.
    public static var mac: IntegrationFacts {
        var facts = IntegrationFacts()
        facts.offers = [.switchGames, .steam, .macApps, .drive, .nextendo, .saves, .images]
        facts.settingsRows = true
        return facts
    }

    /// What blocks new builds, from the engine check's blocking lines: Metal is Apple's tools; a commit alone is the
    /// engine's version (already said by its own line); anything else is the build tools. The override lets it pass.
    public static func buildBlock(_ report: CompatibilityReport?, canPass: Bool, canBuild: Bool?) -> IntegrationFacts.BuildBlock? {
        if let report, !canPass {
            let blocking = Set(report.checks.filter { $0.status == .block }.map(\.id))
            if blocking.contains("metal") { return .appleTools }
            if !blocking.subtracting(["commit"]).isEmpty { return .buildTools }
            if !blocking.isEmpty { return .engineVersion }
        }
        return canBuild == false ? .buildTools : nil
    }

    /// Steam as its source observes it: the choice in force, the last reading and the games it read. The Mac does
    /// not look for Steam apart from reading it.
    @MainActor public static func steam(_ sources: CatalogSourcesModel) -> SteamFacts {
        SteamFacts(enabled: sources.configuration.isEnabled, read: sources.status, games: sources.observedGameCount)
    }

    public static func keys(_ status: LocalKeyStatus?) -> IntegrationFacts.Keys? {
        switch status {
        case .available?: .selected
        case .required?: .missing
        case .invalid(let issue)?: .invalid(issue.message)
        case nil: nil
        }
    }

    /// `owner(settings)`: the entry's settings row, declared in the same catalog as Search and Changed. It leaves the
    /// route and comes back to it (the router keeps the entry focused). Never activates the setting.
    @discardableResult
    public static func open(_ id: IntegrationID, _ facts: IntegrationFacts, in router: AppRouter) -> Bool {
        guard router.route == .integrations, let row = facts.row(id), row.manage?.target == .settings,
              let setting = SettingsCatalog.all.first(where: { $0.id == row.settingID })
        else { return false }
        router.integrationFocus = id
        router.openSettings(setting.group, rowID: setting.id)
        return true
    }

    public static func saves(_ saves: CloudSaves) -> IntegrationFacts.Saves {
        switch saves {
        case .off: .off
        case .iCloudDrive: .iCloudDrive
        case .folder: .folder
        }
    }
}
