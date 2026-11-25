import Foundation

/// The display brand and the fork's identity. The public project page
/// is the contact Wikidata asks clients for; no personal data goes in it.
public enum AppIdentity {
    public static let name = "Arcane"
    public static let displayName = "Oort NX"
    /// The name players knew before Arcane; only the one-time welcome says it.
    public static let formerName = "NX Library"
    /// The module that ports games to the Mac. A name, like the app's, so it is never translated.
    public static let portingName = "Porting"
    public static let projectPage = "https://github.com/sofianbll/oort-nx"
    /// The player guide: the README online, so it opens on every Mac and survives a move of the source folder.
    public static let documentationPage = URL(string: projectPage + "#readme")!

    /// The public funding page has French and English versions.
    public static func fundingPage(for language: AppLanguage) -> URL {
        let path = language == .french ? "financer/" : "en/funding/"
        return URL(string: "https://sofianbll.github.io/oort-nx/" + path)!
    }

    /// The running app's version, "0" when the bundle has none (tests, command-line runs).
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    public static func userAgent(version: String = AppIdentity.version) -> String {
        "\(name)/\(version) (macOS; +\(projectPage))"
    }
}
