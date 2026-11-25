import Foundation
import os

/// Immutable location policy. The build declares its profile; filenames and branch names do not select it.
public struct AppDataProfile: Sendable {
    public let home: URL
    public let isDevelopment: Bool
    public let isTrial2: Bool
    /// Oort NX's own identity, for good: macOS ties permissions, preferences and updates to it.
    public static let identifier = "io.github.sofianbll.oortnx"
    /// Arcane's, which Oort NX used up to 0.3.0. `LibraryMove` reads its folder and preferences once.
    public static let legacyIdentifier = "local.nxlibrary"
    private static let devIdentifier = identifier + ".dev"
    private static let trial2Identifier = devIdentifier + ".trial2"

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, isDevelopment: Bool, isTrial2: Bool = false) {
        self.home = home
        self.isDevelopment = isDevelopment
        self.isTrial2 = isDevelopment && isTrial2
    }
    /// Folders are built as folders (`isDirectory: true`), never by asking the disk, so a root is the same URL
    /// before and after it is created: equal to `file.deletingLastPathComponent()` on a fresh Mac too.
    public var stableSupportRoot: URL { home.appendingPathComponent("Library/Application Support/Oort NX", isDirectory: true) }
    /// Arcane's folder, where Oort NX kept its data up to 0.3.0.
    public var legacySupportRoot: URL { home.appendingPathComponent("Library/Application Support/NXLibrary", isDirectory: true) }
    public var supportRoot: URL {
        home.appendingPathComponent("Library/Application Support/" + folder, isDirectory: true)
    }
    public var cacheRoot: URL { home.appendingPathComponent("Library/Caches/" + folder, isDirectory: true) }
    private var folder: String { isTrial2 ? "Oort NX Dev Trial2" : isDevelopment ? "Oort NX Dev" : "Oort NX" }
    public var preferencesDomain: String {
        isTrial2 ? Self.trial2Identifier : isDevelopment ? Self.devIdentifier : Self.identifier
    }

    fileprivate static func isTrial2Identifier(_ identifier: String?) -> Bool { identifier == trial2Identifier }
    fileprivate static func isDevelopmentIdentifier(_ identifier: String?) -> Bool {
        identifier == devIdentifier || isTrial2Identifier(identifier)
    }
}

/// All app-owned stores use this composition-root policy, including their default initializers.
/// Game installations, their runtime preferences and saves are separate, explicitly operated-on resources.
public enum AppData {
    public static let profile = configuredProfile()
    private static func configuredProfile() -> AppDataProfile {
        #if DEBUG
        if let home = integrationFixtureHome { return AppDataProfile(home: home, isDevelopment: true) }
        #endif
        if AppDataProfile.isTrial2Identifier(Bundle.main.bundleIdentifier) {
            return AppDataProfile(isDevelopment: true, isTrial2: true)
        }
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
                arguments.contains("--render-sound-fixture") || arguments.contains("--render-onboarding-fixture") ||
                arguments.contains("--oort-ui-gallery") || arguments.contains("--render-oort-ui-gallery") ||
                arguments.contains("--render-file-picker") || arguments.contains("--render-command-palette") ||
                arguments.contains("--render-keyboard") else { return nil }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("oort-integrations-\(UUID())", isDirectory: true)
        try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return home
    }()
    // UserDefaults is thread-safe (Apple's documentation) without being Sendable; the reference never changes.
    nonisolated(unsafe) private static let fixturePreferences = integrationFixtureHome.map {
        UserDefaults(suiteName: $0.appendingPathComponent("preferences").path)!
    }
    #endif
    public static func validateBuildIdentity(_ info: [String: Any]) throws {
        let development = info["NXLibraryDevelopmentProfile"] as? Bool == true
        let release = info["NXLibraryRelease"] as? Bool == true
        let identifier = info["CFBundleIdentifier"] as? String
        guard (development && !release && AppDataProfile.isDevelopmentIdentifier(identifier))
                || (release && !development && identifier == AppDataProfile.identifier) else {
            throw DevelopmentProfileError.invalidConfiguration
        }
    }
    /// The copy of the old folder, then the repair of a copy made before it moved its paths.
    static func adoptLegacyLibrary(_ profile: AppDataProfile, checks: [String: DevelopmentProfileImporter.Check],
                                   legacyPreferences: () throws -> [String: Any], preferences: () throws -> [String: Any],
                                   savePreferences: ([String: Any]) throws -> Void) throws {
        let old = profile.legacySupportRoot, new = profile.supportRoot
        _ = try LibraryMove(from: old, to: new).prepare(preferences: legacyPreferences, savePreferences: savePreferences)
        // Never holds the launch: the old paths still open, and a locked or unreadable file is tried again next time.
        do { try LibraryPathRepair(from: old, to: new).prepare(checks: checks, preferences: preferences, savePreferences: savePreferences) }
        catch {
            Logger(subsystem: AppDataProfile.identifier, category: "Startup")
                .error("Library path repair waits: \(String(describing: error), privacy: .private)")
        }
    }
    /// `checks` validate the module's own files in the copy (Porting: `prepare()`).
    public static func prepare(checks: [String: DevelopmentProfileImporter.Check],
                               contents: DevelopmentProfileImporter.Contents = .legacy,
                               sanitizeLibrary: (URL) throws -> Void = { _ in }) throws {
        // An unmarked/mispackaged executable must not silently open the live profile.
        try validateBuildIdentity(Bundle.main.infoDictionary ?? [:])
        if !profile.isDevelopment {
            let defaults = preferences
            try adoptLegacyLibrary(profile, checks: checks, legacyPreferences: {
                UserDefaults.standard.persistentDomain(forName: AppDataProfile.legacyIdentifier) ?? [:]
            }, preferences: {
                UserDefaults.standard.persistentDomain(forName: profile.preferencesDomain) ?? [:]
            }, savePreferences: { values in
                for (key, value) in values { defaults.set(value, forKey: key) }
                guard CFPreferencesAppSynchronize(profile.preferencesDomain as CFString) else { throw LibraryMove.Failure.preferencesUnavailable }
            })
        }
        // The trial's stable data copy is explicit; opening it never runs the legacy import.
        guard profile.isDevelopment, !profile.isTrial2 else { return }
        let defaults = preferences
        _ = try DevelopmentProfileImporter(checks: checks).prepare(profile: profile, contents: contents,
                                                                   sanitizeLibrary: sanitizeLibrary, sourcePreferences: {
            UserDefaults.standard.persistentDomain(forName: AppDataProfile.identifier) ?? [:]
        }, savePreferences: { values in
            defaults.setPersistentDomain(values, forName: profile.preferencesDomain)
            guard CFPreferencesAppSynchronize(profile.preferencesDomain as CFString) else {
                throw DevelopmentProfileError.preferencesUnavailable
            }
        })
    }
}
