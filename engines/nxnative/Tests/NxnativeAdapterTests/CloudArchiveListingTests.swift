import Foundation
import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class CloudArchiveListingTests: XCTestCase {
    func testDuplicateDriveTitleFoldersCannotBeReportedAsAbsent() async throws {
        let title = "0100000000004000"
        for names in [("Orbit", "Orbit"), ("Caf\u{e9}", "Cafe\u{301}"), ("Orbit", "orbit")] {
            let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
                if args[1] == "fixture:Games" {
                    return .init(status: 0, stdout: """
                        [{"Name":"\(names.0) [\(title)]","Path":"\(names.0) [\(title)]","Size":-1,"IsDir":true,"ID":"First"},
                         {"Name":"\(names.1) [\(title)]","Path":"\(names.1) [\(title)]","Size":-1,"IsDir":true,"ID":"Second"}]
                        """, stderr: "")
                }
                XCTFail("An ambiguous title reached \(args[0]) \(args[1])")
                return .init(status: 3, stdout: "", stderr: "directory not found")
            }
            let archive = CloudGameArchive(backend: backend)
            do {
                _ = try await archive.latest(titleID: title)
                XCTFail("An ambiguous listing succeeded")
            } catch CloudLibraryFailure.incomplete {
            } catch StorageBackendError.invalidResponse {
            } catch CloudArchiveError.invalidManifest {
            } catch {
                XCTFail("Expected ambiguity, received \(error)")
            }
            let imported = try await archive.latestManifestsForImport()
            XCTAssertEqual(imported.manifests, [])
            XCTAssertEqual(imported.invalidTitles, [title])
            do {
                let app = FileManager.default.temporaryDirectory.appendingPathComponent("fixture.game.app")
                _ = try await archive.upload(.init(titleID: title, locations: [.app: app]), kinds: [.app])
                XCTFail("An ambiguous title allowed Send")
            } catch CloudLibraryFailure.incomplete {}
        }
    }

    func testDuplicateManifestDirectoriesAreRefusedBeforeListingByName() async throws {
        let title = "0100000000004000"
        let folder = "Orbit [\(title)]"
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            switch args[1] {
            case "fixture:Games":
                return .init(status: 0, stdout: """
                    [{"Name":"\(folder)","Path":"\(folder)","Size":-1,"IsDir":true,"ID":"Title"}]
                    """, stderr: "")
            case "fixture:Games/\(folder)":
                return .init(status: 0, stdout: """
                    [{"Name":"manifests","Path":"manifests","Size":-1,"IsDir":true,"ID":"First"},
                     {"Name":"manifests","Path":"manifests","Size":-1,"IsDir":true,"ID":"Second"}]
                    """, stderr: "")
            default:
                XCTFail("The ambiguous manifest path reached \(args[0]) \(args[1])")
                return .init(status: 3, stdout: "", stderr: "directory not found")
            }
        }
        do {
            _ = try await CloudGameArchive(backend: backend).latest(titleID: title)
            XCTFail("An ambiguous manifest directory appeared absent")
        } catch CloudLibraryFailure.incomplete {}
    }
}
