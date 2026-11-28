// swift-tools-version: 6.0
import PackageDescription

// The names and folders below come from architecture/names.json; change them there and run scripts/generate.
// BEGIN GENERATED NAMES (architecture/names.json, scripts/generate_names.py)
let packageName = "OortNX"
let core = (name: "OortCore", path: "core/OortCore")
let library = (name: "OortLibrary", path: "core/OortLibrary")
let nxnative = (name: "NxnativeAdapter", path: "engines/nxnative/NxnativeAdapter")
let mac = (name: "OortMac", path: "apps/mac/OortMac")
let coreTests = (name: "OortCoreTests", path: "core/Tests/OortCoreTests")
let libraryTests = (name: "OortLibraryTests", path: "core/Tests/OortLibraryTests")
let nxnativeTests = (name: "NxnativeAdapterTests", path: "engines/nxnative/Tests/NxnativeAdapterTests")
let macTests = (name: "OortMacTests", path: "apps/mac/Tests/OortMacTests")
// END GENERATED NAMES

// The core (its two modules and their tests) builds on every system; the Mac's targets are declared on a Mac
// only, so that Linux and Windows build and test the core with this same manifest (R3).
let coreTargets: [Target] = [
    .target(name: core.name, path: core.path, swiftSettings: [.swiftLanguageMode(.v6)]),
    .target(name: library.name,
            dependencies: [.byName(name: core.name), .product(name: "Crypto", package: "swift-crypto")],
            path: library.path,
            // The string catalogue is copied as written (L10n.Catalog reads it): SwiftPM compiles one only on Apple
            // systems. The exclusion only takes it out of the processed folder.
            exclude: ["Resources/Localizable.xcstrings"],
            resources: [.copy("Resources/Localizable.xcstrings"), .process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: libraryTests.name, dependencies: [.byName(name: library.name)], path: libraryTests.path),
    .testTarget(name: coreTests.name, dependencies: [.byName(name: core.name)], path: coreTests.path),
]

#if os(macOS)
let macProducts: [Product] = [
    .library(name: nxnative.name, targets: [nxnative.name]),
    .executable(name: mac.name, targets: [mac.name]),
]
let macTargets: [Target] = [
    .target(name: nxnative.name, dependencies: [.byName(name: library.name)], path: nxnative.path,
            swiftSettings: [.swiftLanguageMode(.v6)]),
    .executableTarget(
        name: mac.name,
        dependencies: [.byName(name: library.name), .byName(name: nxnative.name)],
        path: mac.path
    ),
    .testTarget(
        name: nxnativeTests.name,
        dependencies: [.byName(name: library.name), .byName(name: nxnative.name)],
        path: nxnativeTests.path
    ),
    // What only the Mac does (its Trash, FSEvents, the network monitor, the update of the app, SwiftUI motion).
    .testTarget(name: macTests.name, dependencies: [.byName(name: mac.name)], path: macTests.path),
]
#else
let macProducts: [Product] = []
let macTargets: [Target] = []
#endif

let package = Package(
    name: packageName,
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [.library(name: library.name, targets: [library.name])] + macProducts,
    // On Apple systems Crypto is CryptoKit; elsewhere it is the same API on BoringSSL.
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1")],
    targets: coreTargets + macTargets,
    swiftLanguageModes: [.v5]
)
