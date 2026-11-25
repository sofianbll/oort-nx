// From NX2Apple frontend-ios/Sources/ShellUI/ShellStyle.swift at a79d397 (MIT, Copyright (c) 2026 seedds, jhaizhou, LNPANDY and NX2Apple contributors): the catalog lookups only.
import Foundation

public enum ShellStrings {
    nonisolated(unsafe) public static var captureBundle: Bundle?
    public static var bundle: Bundle { captureBundle ?? .module }
    static func text(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: bundle) }

    /// A text of a game's `launcher.json` in the player's language, keyed by its English words. No entry: English.
    public static func setting(_ text: String, bundle: Bundle = ShellStrings.bundle) -> String {
        text.isEmpty ? text : bundle.localizedString(forKey: text, value: text, table: nil)
    }
}
