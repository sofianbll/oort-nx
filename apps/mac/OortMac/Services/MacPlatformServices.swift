import OortLibrary

/// Every Mac implementation of the core's joints, given in one place: by the app before anything else
/// (`NXLibraryApp.init`), and by every probe that runs the core (`Tests/CatalogAppChecks/ProbeStart.swift`).
enum MacPlatformServices {
    static func register() {
        PlatformServices.register(imageResizer: ImageIOResizer(), languageDetector: NaturalLanguageDetector())
    }
}
