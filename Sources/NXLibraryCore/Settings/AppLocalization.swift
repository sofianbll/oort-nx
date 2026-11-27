import Foundation
import Combine
import Synchronization
import OortCore

/// The selected locale is captured by background work, while views observe changes on the main thread.
public final class AppLocalization: ObservableObject {
    @MainActor public static let shared = AppLocalization()
    @Published public private(set) var context = AppLocale(language: .english, region: "US")

    public func configure(_ settings: AppSettings) {
        let next = AppLocale(language: settings.appLanguage, region: settings.appRegion)
        guard next != context else { return }
        L10n.setContext(next)
        context = next
    }
}

public enum L10n {
    private static let selected = Mutex(AppLocale(language: .english, region: "US"))
    public static var context: AppLocale { selected.withLock { $0 } }
    public static func setContext(_ context: AppLocale) { selected.withLock { $0 = context } }

    /// Installed apps find their resources before considering SwiftPM's development location.
    public static func resources(in app: URL? = nil) -> Bundle? {
        let root = app ?? Bundle.main.bundleURL
        for folder in [root.appendingPathComponent("Contents/Resources"), root] {
            if let bundle = Bundle(url: folder.appendingPathComponent("NXLibrary_NXLibraryCore.bundle")) { return bundle }
        }
        return app == nil ? Bundle.module : nil
    }

    private static func languageBundle(_ language: AppLanguage, in resources: Bundle) -> Bundle? {
        guard let path = resources.path(forResource: language.rawValue, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// At most one retained bundle per supported language; never cache interpolated user data or mutable copy.
    private static let defaultLanguageBundles: [AppLanguage: Bundle] = {
        guard let resources = resources() else { return [:] }
        var bundles: [AppLanguage: Bundle] = [:]
        for language in AppLanguage.allCases where language != .automatic {
            bundles[language] = languageBundle(language, in: resources)
        }
        return bundles
    }()

    public static func text(_ key: String, context: AppLocale? = nil, bundle: Bundle? = nil) -> String {
        let context = context ?? Self.context
        // Explicit test/import bundles must never reuse another bundle's resources.
        let localized: Bundle?
        if let bundle { localized = languageBundle(context.language, in: bundle) }
        else { localized = defaultLanguageBundles[context.language] }
        let value = localized?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
        return displayCopy(value, key: key)
    }

    private static func displayCopy(_ value: String, key: String) -> String {
        // The standalone key names the achievement tier, not the app.
        guard key != "Arcane", value.contains(AppIdentity.name) else { return value }
        return value.replacingOccurrences(of: AppIdentity.name, with: AppIdentity.displayName)
    }

    public static func format(_ key: String, _ arguments: [CVarArg], context: AppLocale? = nil) -> String {
        let context = context ?? Self.context
        return String(format: text(key, context: context), locale: context.formatLocale, arguments: arguments)
    }

    public static func count(_ key: String, _ count: Int, arguments: [CVarArg] = [], context: AppLocale? = nil) -> String {
        let context = context ?? Self.context
        let value = String(format: text(key, context: context), locale: context.formatLocale, arguments: [count] + arguments)
        // shortcut: branded plurals only interpolate the count; if one needs other arguments, brand the variant before interpolation.
        return arguments.isEmpty ? displayCopy(value, key: key) : value
    }
}

public extension L10n {
    /// A screen's words, said once for every renderer of this app: the catalogue's words that fill it first, then its
    /// verbatim arguments, its count (plural) and its date in the reader's locale.
    static func say(_ text: Screen.Text, context: AppLocale? = nil) -> String {
        let context = context ?? Self.context
        var arguments: [CVarArg] = text.words.map { say($0, context: context) } + text.args
        if let date = text.date {
            arguments.append(date.formatted(.dateTime.year().month().day().hour().minute().locale(context.formatLocale)))
        }
        if let count = text.count { return Self.count(text.key, count, arguments: arguments, context: context) }
        return arguments.isEmpty ? Self.text(text.key, context: context) : format(text.key, arguments, context: context)
    }
}
