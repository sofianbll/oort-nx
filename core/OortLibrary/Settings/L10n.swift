import Foundation
import OortCore
import Synchronization

public enum L10n {
    private static let selected = Mutex(AppLocale(language: .english, region: "US"))
    public static var context: AppLocale { selected.withLock { $0 } }
    public static func setContext(_ context: AppLocale) { selected.withLock { $0 = context } }

    /// Resolves catalogue words, verbatim arguments, counts and dates in the reader's locale.
    public static func say(_ text: Screen.Text, context: AppLocale? = nil) -> String {
        let context = context ?? Self.context
        var arguments: [CVarArg] = text.words.map { say($0, context: context) } + text.args
        if let date = text.date {
            arguments.append(date.formatted(.dateTime.year().month().day().hour().minute().locale(context.formatLocale)))
        }
        if let count = text.count { return Self.count(text.key, count, arguments: arguments, context: context) }
        return arguments.isEmpty ? Self.text(text.key, context: context) : format(text.key, arguments, context: context)
    }

    /// Installed apps find their resources before considering SwiftPM's development location.
    public static func resources(in app: URL? = nil) -> Bundle? {
        let root = app ?? Bundle.main.bundleURL
        for folder in [root.appendingPathComponent("Contents/Resources"), root] {
            if let bundle = Bundle(url: folder.appendingPathComponent(GeneratedNames.resourceBundle)) { return bundle }
        }
        return app == nil ? Bundle.module : nil
    }

    /// The app's catalogue, read once from its resources.
    private static let defaultCatalog: Catalog? = resources().flatMap(Catalog.init(in:))
    /// Catalogues of explicit test or import bundles, each read once and never mixed with the app's.
    private static let injected = Mutex<[URL: Catalog]>([:])

    private static func catalog(_ bundle: Bundle?) -> Catalog? {
        guard let bundle else { return defaultCatalog }
        return injected.withLock { known in
            if let found = known[bundle.bundleURL] { return found }
            let read = Catalog(in: bundle)
            if let read { known[bundle.bundleURL] = read }
            return read
        }
    }

    public static func text(_ key: String, context: AppLocale? = nil, bundle: Bundle? = nil) -> String {
        displayCopy(value(key, language: (context ?? Self.context).language, bundle: bundle), key: key)
    }

    /// The catalogue's text for `key` in `language`, the form for `count` when it varies by plural; the key itself
    /// when the catalogue has none (as `Bundle` did with the compiled catalogue).
    package static func value(_ key: String, language: AppLanguage, count: Int? = nil, bundle: Bundle? = nil) -> String {
        catalog(bundle)?.text(key, language: language, count: count) ?? key
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
        let form = value(key, language: context.language, count: count)
        let value = String(format: form, locale: context.formatLocale, arguments: [count] + arguments)
        // shortcut: branded plurals only interpolate the count; if one needs other arguments, brand the variant before interpolation.
        return arguments.isEmpty ? displayCopy(value, key: key) : value
    }

    /// `Localizable.xcstrings`, read as it is written, on every system: SwiftPM compiles a string catalogue only on
    /// Apple systems. Each key holds a text per language, or plural forms (`one`, `other`).
    struct Catalog: Sendable {
        enum Entry: Sendable {
            case text(String)
            case plural(one: String?, other: String)
        }

        let entries: [String: [String: Entry]]

        init?(in bundle: Bundle) {
            guard let url = bundle.url(forResource: "Localizable", withExtension: "xcstrings"),
                  let data = try? Data(contentsOf: url) else { return nil }
            self.init(data: data)
        }

        init?(data: Data) {
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let strings = root["strings"] as? [String: Any] else { return nil }
            func unit(_ node: Any?) -> String? {
                ((node as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            }
            var entries: [String: [String: Entry]] = [:]
            entries.reserveCapacity(strings.count)
            for (key, node) in strings {
                guard let localizations = (node as? [String: Any])?["localizations"] as? [String: Any] else { continue }
                var languages: [String: Entry] = [:]
                for (language, localization) in localizations {
                    let plural = ((localization as? [String: Any])?["variations"] as? [String: Any])?["plural"] as? [String: Any]
                    if let plural, let other = unit(plural["other"]) {
                        languages[language] = .plural(one: unit(plural["one"]), other: other)
                    } else if let text = unit(localization) {
                        languages[language] = .text(text)
                    }
                }
                entries[key] = languages
            }
            self.entries = entries
        }

        func text(_ key: String, language: AppLanguage, count: Int?) -> String? {
            switch entries[key]?[language.rawValue] {
            case .text(let text): return text
            case .plural(let one, let other):
                guard let count, Self.isOne(count, language) else { return other }
                return one ?? other
            case nil: return nil
            }
        }

        /// CLDR's integer rule for `one` in the app's languages: 0 and 1 in French and Brazilian Portuguese, 1
        /// elsewhere, never in Chinese. Every other category falls back to `other`, as Apple's catalogue does.
        static func isOne(_ count: Int, _ language: AppLanguage) -> Bool {
            switch language {
            case .french, .portugueseBrazil: return count.magnitude <= 1
            case .chineseSimplified: return false
            default: return count.magnitude == 1
            }
        }
    }
}
