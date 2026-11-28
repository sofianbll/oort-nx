import XCTest
@testable import OortLibrary
@testable import OortMac

/// The app gives the core every Mac joint, before anything else at launch; probes start the same way
/// (CatalogAppChecks/ProbeStart.swift, checked by scripts/check_probes.py).
final class MacPlatformServicesTests: XCTestCase {
    func testRegisteringGivesTheCoreEveryMacJoint() {
        MacPlatformServices.register()
        XCTAssertTrue(PlatformServices.imageResizer is ImageIOResizer)
        XCTAssertTrue(PlatformServices.languageDetector is NaturalLanguageDetector)
    }

    func testTheAppRegistersBeforeAnythingElse() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../OortMac/NXLibraryApp.swift").standardized
        let source = try String(contentsOf: app, encoding: .utf8)
        let body = try XCTUnwrap(source.range(of: "    init() {\n")).upperBound
        let firstStatement = source[body...].split(separator: "\n").first { line in
            !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
        XCTAssertEqual(firstStatement?.trimmingCharacters(in: .whitespaces), "MacPlatformServices.register()")
    }
}
