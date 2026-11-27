// swift-tools-version: 6.0
import PackageDescription

// The names and folders below come from architecture/names.json; change them there and run scripts/generate.
// BEGIN GENERATED NAMES (architecture/names.json, scripts/generate_names.py)
let packageName = "NXLibrary"
let core = (name: "OortCore", path: "core/OortCore")
let library = (name: "NXLibraryCore", path: "core/OortLibrary")
let nxnative = (name: "ArcanePorting", path: "engines/nxnative/NxnativeAdapter")
let mac = (name: "NXLibrary", path: "apps/mac/OortMac")
let coreTests = (name: "OortCoreTests", path: "core/Tests/OortCoreTests")
let libraryTests = (name: "NXLibraryCoreTests", path: "core/Tests/OortLibraryTests")
let nxnativeTests = (name: "ArcanePortingTests", path: "engines/nxnative/Tests/NxnativeAdapterTests")
// END GENERATED NAMES

let package = Package(
    name: packageName,
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: library.name, targets: [library.name]),
        .library(name: nxnative.name, targets: [nxnative.name]),
        .executable(name: mac.name, targets: [mac.name]),
    ],
    targets: [
        .target(name: core.name, path: core.path, swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: library.name, dependencies: [.byName(name: core.name)], path: library.path,
                resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: nxnative.name, dependencies: [.byName(name: library.name)], path: nxnative.path,
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: mac.name,
            dependencies: [.byName(name: library.name), .byName(name: nxnative.name)],
            path: mac.path
        ),
        .testTarget(
            name: libraryTests.name,
            dependencies: [.byName(name: library.name)],
            path: libraryTests.path
        ),
        .testTarget(
            name: nxnativeTests.name,
            dependencies: [.byName(name: library.name), .byName(name: nxnative.name)],
            path: nxnativeTests.path
        ),
        .testTarget(name: coreTests.name, dependencies: [.byName(name: core.name)], path: coreTests.path),
    ],
    swiftLanguageModes: [.v5]
)
