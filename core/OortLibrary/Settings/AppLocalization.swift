import Foundation
import Observation

/// The selected locale is captured by background work, while views observe changes on the main thread.
@Observable
public final class AppLocalization {
    @ObservationIgnored @MainActor public static let shared = AppLocalization()
    public private(set) var context = AppLocale(language: .english, region: "US")

    public func configure(_ settings: AppSettings) {
        let next = AppLocale(language: settings.appLanguage, region: settings.appRegion)
        guard next != context else { return }
        L10n.setContext(next)
        context = next
    }
}
