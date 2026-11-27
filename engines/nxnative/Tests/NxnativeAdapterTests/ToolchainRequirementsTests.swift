import XCTest
@testable import OortLibrary
@testable import NxnativeAdapter

final class ToolchainRequirementsTests: XCTestCase {
    func testCandidateRequirementsCertifyTheInstalledXcode27_2Compiler() {
        XCTAssertEqual(ToolchainRequirements.current.minimumXcode, "27.2")
        XCTAssertEqual(ToolchainRequirements.current.fallbackMetal, "32023.922")
        XCTAssertEqual(ToolchainRequirements.current.metalDownload(for: "32023.922"),
                       ["-downloadComponent", "MetalToolchain", "-buildVersion", "27B47"])
    }
    func testMetalDownloadPinsTheCertifiedAsset() {
        let requirements = ToolchainRequirements(minimumXcode: "27.1", fallbackMetal: "32023.921",
                                                 metalAssets: ["32023.921": "27A266a"])
        XCTAssertEqual(requirements.metalDownload(for: "32023.921"),
                       ["-downloadComponent", "MetalToolchain", "-buildVersion", "27A266a"])
        XCTAssertNil(requirements.metalDownload(for: "32024.1"))
        XCTAssertEqual(ToolchainRequirements.anyMetalDownload, ["-downloadComponent", "MetalToolchain"])
    }

    func testCurrentCoversItsOwnFallback() {
        let current = ToolchainRequirements.current
        XCTAssertNotNil(current.metalAssets[current.fallbackMetal])
    }

    func testXcodeVersionParse() {
        XCTAssertEqual(ToolchainRequirements.xcodeVersion(from: "Xcode 27.1\nBuild version 27A9275\n"), "27.1")
        XCTAssertNil(ToolchainRequirements.xcodeVersion(from: "xcode-select: error"))
    }
}
