import Foundation
import OortLibrary

/// The build advertises modes in the same settings contract the game launcher consumes.
public enum NextendoLaunch {
    public static let networkKey = "DM_NETWORK"
    public static let clientIDKey = "DM_NEXTENDO_CLIENT_ID"
    public static let loginDirectoryKey = "DM_NEXTENDO_LOGIN_DIR"
    public static let presenceKey = "DM_NEXTENDO_PRESENCE"

    public static func guestEnvironment() -> [String: String] { [networkKey: "offline", presenceKey: "0"] }

    public static func presenceEnvironment(profile: LocalProfile?, in app: URL) throws -> [String: String] {
        guard profile?.sharesCurrentGame != true else { return [:] }
        guard supports(presenceKey, in: app) else { throw NextendoError.presenceHost }
        return [presenceKey: "0"]
    }

    public static func tokenStore(profileID: UUID?, originalID: UUID?, root: URL = AppData.supportRoot) -> NextendoTokenStore {
        guard let profileID, profileID != originalID else { return .init() }
        return .init(directory: root.appendingPathComponent("profile-credentials", isDirectory: true)
            .appendingPathComponent(profileID.uuidString, isDirectory: true))
    }

    /// Prove the installed host knows the override, not just that the selected source checkout does.
    public static func supportsProfileLogin(in app: URL) -> Bool {
        supports(loginDirectoryKey, in: app)
    }

    private static func supports(_ key: String, in app: URL) -> Bool {
        let host = app.appendingPathComponent("Contents/MacOS/dmhost")
        guard let data = try? Data(contentsOf: host, options: .mappedIfSafe) else { return false }
        return data.range(of: Data((key + "\0").utf8)) != nil
    }

    public static func networkSetting(in settings: [LauncherSetting]) -> LauncherSetting? {
        settings.first { $0.env == networkKey && $0.kind == "choice" && $0.options?.isEmpty == false }
    }

    public static func requiresSignIn(setting: LauncherSetting?, mode: String?) -> Bool {
        (mode == "nextendo" || mode == "auto") && setting?.accepts("nextendo") == true
    }

    public static func environment(setting: LauncherSetting?, mode: String?, clientID: String?,
                                   tokenStore: NextendoTokenStore? = nil,
                                   sessionAvailable: (String) async throws -> Bool) async throws -> [String: String] {
        guard requiresSignIn(setting: setting, mode: mode) else { return [:] }
        guard let clientID, NextendoAuthorization.validClientID(clientID) else { throw NextendoError.clientID }
        guard try await sessionAvailable(clientID) else { throw NextendoError.signedOut }
        var environment = [clientIDKey: clientID]
        if let tokenStore { environment[loginDirectoryKey] = tokenStore.directory.path }
        return environment
    }

    static let buildFlag = "--nextendo"

    static func engineSupportsBuild(at repo: URL) -> Bool {
        // Like EngineSourceCapabilities, inspect the selected checkout without executing it.
        guard let cli = try? String(contentsOf: repo.appendingPathComponent("scripts/build_ipa_from_nsp.py"), encoding: .utf8)
        else { return false }
        return cli.contains("'\(buildFlag)'") || cli.contains("\"\(buildFlag)\"")
    }

    public static func engineSupportsSignIn(at repo: URL) -> Bool {
        guard engineSupportsBuild(at: repo),
              let table = try? String(contentsOf: repo.appendingPathComponent("dm/games/settings.tsv"), encoding: .utf8)
        else { return false }
        return table.split(whereSeparator: \.isNewline).contains { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            return fields.count > 2 && fields[0] == "DM_NETWORK" && fields[1] == "choice"
                && fields[2].split(separator: ",").contains { $0.hasPrefix("nextendo=") }
        }
    }

    public static var buildClientID: String? {
        (Bundle.main.object(forInfoDictionaryKey: "DMNextendoClientID") as? String)
            .flatMap { NextendoAuthorization.validClientID($0) ? $0 : nil }
    }
}
