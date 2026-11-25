// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NXLibrary",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "NXLibraryCore", targets: ["NXLibraryCore"]),
        .library(name: "ArcanePorting", targets: ["ArcanePorting"]),
        .executable(name: "NXLibrary", targets: ["NXLibrary"]),
    ],
    targets: [
        .target(name: "OortCore", swiftSettings: [.swiftLanguageMode(.v6)]),
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
