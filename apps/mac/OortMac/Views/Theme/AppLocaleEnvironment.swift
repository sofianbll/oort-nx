import SwiftUI
import OortLibrary
#if DEBUG
import os
#endif

private struct AppLocaleEnvironmentKey: EnvironmentKey {
    #if DEBUG
    static var defaultValue: AppLocale {
        AppLocaleDefault.oortProbeLocale.withLock { $0 } ?? AppLocale(language: .english, region: "US")
    }
    #else
    static let defaultValue = AppLocale(language: .english, region: "US")
    #endif
}

#if DEBUG
/// Probes only (run_cloud_shelf.py): the locale of views used outside a mounted hierarchy. Release builds do not
/// contain it.
enum AppLocaleDefault {
    static let oortProbeLocale = OSAllocatedUnfairLock<AppLocale?>(initialState: nil)
}
#endif

extension EnvironmentValues {
    /// Declares a view's dependency on app-language changes without replacing its identity or state.
    var nxAppLocale: AppLocale {
        get { self[AppLocaleEnvironmentKey.self] }
        set { self[AppLocaleEnvironmentKey.self] = newValue }
    }
}
