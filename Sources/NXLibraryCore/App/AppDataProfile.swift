import Foundation

/// Immutable location policy. The build declares its profile; filenames and branch names do not select it.
public struct AppDataProfile: Sendable {
    public let home: URL
    public let isDevelopment: Bool
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, isDevelopment: Bool) {
        self.home = home
        self.isDevelopment = isDevelopment
    }
    /// Folders are built as folders (`isDirectory: true`), never by asking the disk, so a root is the same URL
    /// before and after it is created: equal to `file.deletingLastPathComponent()` on a fresh Mac too.
    public var stableSupportRoot: URL { home.appendingPathComponent("Library/Application Support/NXLibrary", isDirectory: true) }
    public var supportRoot: URL {
        isDevelopment ? home.appendingPathComponent("Library/Application Support/NXLibrary-Development", isDirectory: true) : stableSupportRoot
    }
    public var cacheRoot: URL { home.appendingPathComponent("Library/Caches/" + (isDevelopment ? "NXLibrary-Development" : "NXLibrary"), isDirectory: true) }
    public var preferencesDomain: String { isDevelopment ? "local.nxlibrary.development" : "local.nxlibrary" }
}

/// All app-owned stores use this composition-root policy, including their default initializers.
/// Game installations, their runtime preferences and saves are separate, explicitly operated-on resources.
public enum AppData {
    public static let profile = configuredProfile()
    private static func configuredProfile() -> AppDataProfile {
        #if DEBUG
        if let home = integrationFixtureHome { return AppDataProfile(home: home, isDevelopment: true) }
        #endif
        return AppDataProfile(isDevelopment: Bundle.main.object(forInfoDictionaryKey: "NXLibraryDevelopmentProfile") as? Bool == true)
    }
    public static var supportRoot: URL { profile.supportRoot }
    public static var cacheRoot: URL { profile.cacheRoot }
    // Each packaged profile has its own bundle ID. Foundation already binds
    // standard preferences to that ID and rejects reopening it as a suite.
    public static var preferences: UserDefaults { configuredPreferences() }
    private static func configuredPreferences() -> UserDefaults {
        #if DEBUG
        if let fixturePreferences { return fixturePreferences }
        #endif
        return .standard
    }
    #if DEBUG
    public static let integrationFixtureHome: URL? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--integration-fixture") || arguments.contains("--render-integration-fixture") ||
                arguments.contains("--render-sound-fixture") || arguments.contains("--render-onboarding-fixture") else { return nil }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("oort-integrations-\(UUID())", isDirectory: true)
        try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return home
    }()
    private static let fixturePreferences = integrationFixtureHome.map {
        UserDefaults(suiteName: $0.appendingPathComponent("preferences").path)!
    }
    #endif
    public static func validateBuildIdentity(_ info: [String: Any]) throws {
        let development = info["NXLibraryDevelopmentProfile"] as? Bool == true
        let release = info["NXLibraryRelease"] as? Bool == true
        let identifier = info["CFBundleIdentifier"] as? String
        guard (development && !release && identifier == "local.nxlibrary.development")
                || (release && !development && identifier == "local.nxlibrary") else {
            throw DevelopmentProfileError.invalidConfiguration
        }
    }
    /// `checks` validate the module's own files in the copy (Porting: `prepare()`).
    public static func prepare(checks: [String: DevelopmentProfileImporter.Check],
                               contents: DevelopmentProfileImporter.Contents = .legacy,
                               sanitizeLibrary: (URL) throws -> Void = { _ in }) throws {
        // An unmarked/mispackaged executable must not silently open the live profile.
        try validateBuildIdentity(Bundle.main.infoDictionary ?? [:])
        guard profile.isDevelopment else { return }
        let defaults = preferences
        _ = try DevelopmentProfileImporter(checks: checks).prepare(profile: profile, contents: contents,
                                                                   sanitizeLibrary: sanitizeLibrary, sourcePreferences: {
            UserDefaults.standard.persistentDomain(forName: "local.nxlibrary") ?? [:]
        }, savePreferences: { values in
            defaults.setPersistentDomain(values, forName: profile.preferencesDomain)
            guard CFPreferencesAppSynchronize(profile.preferencesDomain as CFString) else {
                throw DevelopmentProfileError.preferencesUnavailable
            }
        })
    }
}
