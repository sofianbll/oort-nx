// swift-tools-version: 6.2
import PackageDescription

// The mobile app's code: NX2Apple's host layer (ShellModel, ShellControllers, ShellHost, see PROVENANCE.md) and Oort NX's
// screens over it. The app target is in project.yml; this package also builds and tests on the Mac.
let package = Package(
    name: "OortMobile",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26), .macCatalyst(.v26)],
    products: [
        .library(name: "OortMobile", targets: ["OortMobile"]),
        .library(name: "ShellHost", targets: ["ShellHost"]),
        // The optional Google Drive connector. Only the app's CloudDrive.swift names it; the screens know no service.
        .library(name: "OortDrive", targets: ["OortDrive"]),
    ],
    dependencies: [.package(name: "NXLibrary", path: "..")],
    targets: [
        .target(name: "ShellModel", resources: [.process("Resources")]),
        .target(name: "ShellControllers", dependencies: ["ShellModel"]),
        .target(name: "ShellHost", dependencies: ["ShellModel", "ShellControllers", .product(name: "OortCore", package: "NXLibrary")], resources: [.process("Resources")]),
        .target(name: "OortMobile", dependencies: ["ShellModel", "ShellControllers", "ShellHost",
                                                   .product(name: "OortCore", package: "NXLibrary")],
                resources: [.process("Resources")]),
        .target(name: "OortDrive", dependencies: [.product(name: "OortCore", package: "NXLibrary")]),
        .testTarget(name: "OortDriveTests", dependencies: ["OortDrive", .product(name: "OortCore", package: "NXLibrary")]),
        .testTarget(name: "ShellHostTests", dependencies: ["ShellHost", "ShellModel", "ShellControllers"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ShellControllersTests", dependencies: ["ShellControllers", "ShellModel"]),
        .testTarget(name: "OortMobileTests", dependencies: ["OortMobile", "ShellHost", "ShellModel"]),
    ]
)
