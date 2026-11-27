// swift-tools-version: 6.0
import PackageDescription

// Windows and Linux build only the portable core: OortCore plus the NXLibraryCore files listed below, which
// import nothing from Apple. On a Mac, `OORT_PORTABLE=1 swift build` builds the same subset to check it.
#if os(Windows) || os(Linux)
let portableOnly = true
#else
let portableOnly = Context.environment["OORT_PORTABLE"] == "1"
#endif

// Paths under Sources/NXLibraryCore. scripts/check_portable_core.py keeps this list honest.
let portableSources = [
    "App/AppIdentity.swift",
    "Artwork/ArtworkNames.swift",
    "Artwork/CriticRatingQuery.swift",
    "Artwork/GameTitleKey.swift",
    "Artwork/HTMLPlainText.swift",
    "Artwork/SteamStoreSearch.swift",
    "Artwork/WikidataLookup.swift",
    "Artwork/WikipediaLookup.swift",
    "Catalog/CatalogDocument.swift",
    "Catalog/CatalogErrorCopy.swift",
    "Catalog/CatalogErrors.swift",
    "Catalog/CatalogGame.swift",
    "Catalog/CatalogGameOptions.swift",
    "Catalog/CatalogGamePresentation.swift",
    "Catalog/CatalogJSON.swift",
    "Catalog/CatalogLibraryProjection.swift",
    "Catalog/CatalogPersonalizations.swift",
    "Catalog/CatalogRecovery.swift",
    "Catalog/CatalogRepositoryError.swift",
    "Catalog/CatalogScanError.swift",
    "Catalog/CatalogSourceRecord.swift",
    "Catalog/GamePlay.swift",
    "Catalog/MacShortcutRecord.swift",
    "Catalog/SteamCatalogGame+Record.swift",
    "Details/GameOptionsPresentation.swift",
    "Library/ActivitySummary.swift",
    "Library/CarriedPlaytime.swift",
    "Library/CloudDriveScope.swift",
    "Library/CloudLibraryActivation.swift",
    "Library/CloudLibraryPreference.swift",
    "Library/LibraryFilter.swift",
    "Library/LocalProfile.swift",
    "Library/PlaySession.swift",
    "Library/ProfileKeypad.swift",
    "Library/ProfilePageCards.swift",
    "Mods/LocalMod.swift",
    "Players/PlayerControllerResolution.swift",
    "Players/PlayerPlan.swift",
    "Players/PlayerPlanStore.swift",
    "Selene/ButtonPrompts.swift",
    "Selene/MaterialIcon.swift",
    "Selene/MoonlightAppearance.swift",
    "Selene/OortSynth.swift",
    "Selene/SeleneCanvas.swift",
    "Selene/SelenePalette.swift",
    "Selene/SeleneTokens.swift",
    "Selene/SoundCue.swift",
    "Selene/SoundPackEvent.swift",
    "Selene/SpotlightRow.swift",
    "Settings/AppLocale.swift",
    "Settings/AppSettings.swift",
    "Settings/AppSettingsDraft.swift",
    "Settings/IntegrationEntry.swift",
    "Settings/L10n.swift",
    "Settings/SettingsCatalog.swift",
    "Settings/SettingsCategory.swift",
    "Settings/SettingsReset.swift",
    "Settings/SettingsRowAction.swift",
    "Settings/SettingsSection.swift",
    "Steam/InstallationFileObservation.swift",
    "Steam/NativeMacApplication.swift",
    "Steam/SteamKeyValues.swift",
    "Steam/SteamMetadata.swift"
]

// Paths under Tests/NXLibraryCoreTests: the tests that need nothing outside the portable core.
let portableTests: [String] = [
    "ActivitySummaryTests.swift",
    "ArcaneNameTests.swift",
    "ButtonPromptsTests.swift",
    "EngineRuntimeRequirementsTests.swift",
    "MaterialIconTests.swift",
    "OortSynthTests.swift",
    "PlayerPlanTests.swift",
    "SeleneCanvasTests.swift",
    "SelenePaletteTests.swift",
    "SettingsRowActionTests.swift",
    "SettingsRowButtonsTests.swift",
    "ShellOverlayInputTests.swift",
    "WallpaperBrightnessTests.swift"
]

let package: Package = portableOnly ? Package(
    name: "NXLibrary",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "NXLibraryCore", targets: ["NXLibraryCore"]),
        .executable(name: "oort-core", targets: ["oort-core"]),
    ],
    targets: [
        .target(name: "OortCore"),
        .target(name: "NXLibraryCore", dependencies: ["OortCore"], path: "Sources/NXLibraryCore",
                sources: portableSources, resources: [.process("Resources")],
                swiftSettings: [.define("OORT_PORTABLE")]),
        .testTarget(name: "NXLibraryCoreTests", dependencies: ["NXLibraryCore"], path: "Tests/NXLibraryCoreTests",
                    sources: portableTests),
        .testTarget(name: "OortCoreTests", dependencies: ["OortCore"]),
        // The desktop app's logic, spoken to as JSON lines (desktop/PROTOCOL.md).
        .target(name: "OortCompanion", dependencies: ["OortCore", "NXLibraryCore"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "oort-core", dependencies: ["OortCompanion"],
                          swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "OortCompanionTests", dependencies: ["OortCompanion"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
    ],
    swiftLanguageModes: [.v5]
) : Package(
    name: "NXLibrary",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "NXLibraryCore", targets: ["NXLibraryCore"]),
        .library(name: "ArcanePorting", targets: ["ArcanePorting"]),
        .executable(name: "NXLibrary", targets: ["NXLibrary"]),
    ],
    targets: [
        .target(name: "OortCore"),
        .target(name: "NXLibraryCore", dependencies: ["OortCore"], path: "Sources/NXLibraryCore",
                resources: [.process("Resources")]),
        .target(name: "ArcanePorting", dependencies: ["NXLibraryCore"], path: "Sources/ArcanePorting"),
        .executableTarget(
            name: "NXLibrary",
            dependencies: ["NXLibraryCore", "ArcanePorting"],
            path: "Sources/NXLibrary"
        ),
        .testTarget(
            name: "NXLibraryCoreTests",
            dependencies: ["NXLibraryCore"],
            path: "Tests/NXLibraryCoreTests"
        ),
        .testTarget(
            name: "ArcanePortingTests",
            dependencies: ["NXLibraryCore", "ArcanePorting"],
            path: "Tests/ArcanePortingTests"
        ),
        .testTarget(name: "OortCoreTests", dependencies: ["OortCore"]),
    ],
    swiftLanguageModes: [.v5]
)
