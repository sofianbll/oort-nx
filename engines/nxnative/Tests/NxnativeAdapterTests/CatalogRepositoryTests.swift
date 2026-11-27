import XCTest
@testable import OortLibrary
@testable import NxnativeAdapter

final class CatalogRepositoryTests: XCTestCase {
    private func mixed() throws -> (SteamTestFixture, CatalogStore, CatalogDocument) {
        let f = try SteamTestFixture.temporary(in: self)
        _ = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: f.root)
        let store = CatalogStore(directory: f.root)
        var document = try store.loadOrMigrate()
        var steam = SteamCatalogGame(appID: 10, name: "Fixture Switch game")
        steam.isFavorite = true; steam.isHidden = true
        document.games.append(.init(steam: steam))
        return (f, store, try store.save(document, expectedRevision: document.revision))
    }

    func testNXNativeUpdateRetainsWholePayloadPersonalReferenceAndSteamRecord() throws {
        let (_, store, original) = try mixed()
        let repository = CatalogRepository(store: store)
        let id = original.games[0].id
        let updated = try repository.updateNXNative(id: id) { $0.titleId = "0100000000000002"; $0.isFavorite = false }
        var expected = try XCTUnwrap(original.games[0].nxnativeGame)
        expected.titleId = "0100000000000002"; expected.isFavorite = false
        XCTAssertEqual(updated.games[0].nxnativeGame, expected)
        XCTAssertEqual(updated.games[0].personalizationReference, original.games[0].personalizationReference)
        XCTAssertEqual(updated.games[1], original.games[1])
        XCTAssertEqual(try repository.load(), updated)
    }

    func testCloudImportIsIdempotentAndExplicitRemovalSurvivesReload() throws {
        let (fixture, store, original) = try mixed()
        let repository = CatalogRepository(store: store)
        let existing = try XCTUnwrap(original.nxnativeGames.first?.titleId)
        let title = "0100000000000042"
        let app = CloudGameManifest.Artifact(kind: .app, size: 10, sha256: "", md5: "",
            unpackedSize: 20, entryCount: 1, inventorySHA256: "", engineCommit: nil, shaderChain: nil, options: [:])
        let manifests = [existing.lowercased(), title, title].map {
            CloudGameManifest(version: 1, titleID: $0, createdAt: .distantPast, artifacts: [app],
                              gameName: "Synthetic", bundleName: "../Escape.app")
        }
        let imported = try repository.importCloudGames(manifests, in: fixture.root)
        XCTAssertEqual(imported.games.count, original.games.count + 1)
        XCTAssertEqual(Array(imported.games.prefix(original.games.count)), original.games)
        XCTAssertEqual(try repository.importCloudGames(manifests, in: fixture.root), imported)
        let pending = try XCTUnwrap(imported.nxnativeGames.first { $0.titleId == title })
        XCTAssertEqual(pending.url, fixture.root.appendingPathComponent("\(title).app", isDirectory: true))
        XCTAssertEqual(pending.cloudImportPending, true)
        let removed = try repository.removeNXNative(id: pending.id)
        let reopened = CatalogRepository(store: CatalogStore(directory: fixture.root))
        XCTAssertEqual(try reopened.importCloudGames(manifests, in: fixture.root), removed)
        XCTAssertEqual(removed.games, original.games)
    }

    func testCloudImportAdoptsExactNUPProgramWithoutCopyingLocalPathsOrChangingAnotherEdition() throws {
        let (fixture, store, _) = try mixed()
        let repository = CatalogRepository(store: store)
        let title = "0400123400000002"
        let other = "0400123400000001"
        let program = NUPProgramSelection(programID: 0x0400123400000002, applicationID: 0x0400123400000000,
                                          addOnContentBaseID: 0x0400123400001000)
        let input = URL(fileURLWithPath: "/fixture/private/Game.nup")
        let sources: [GameFileItem] = [
            .init(url: input, kind: .base, titleId: title, versionString: "v0", sizeBytes: 5,
                  sourceLayout: .container, nupProgram: program),
            .init(url: input, kind: .update, titleId: title, versionString: "v65536", sizeBytes: 6,
                  sourceLayout: .container, nupProgram: program),
        ]
        let folder = "Fixture [\(title)]"
        let selection = try XCTUnwrap(CloudGameSources.ArchivedSelection(folder: folder, files: sources, titleID: title))
        let data = try JSONEncoder().encode(selection)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("/fixture/private"))
        let decoded = try JSONDecoder().decode(CloudGameSources.ArchivedSelection.self, from: data)
        let app = CloudGameManifest.Artifact(kind: .app, size: 10, sha256: "", md5: "",
            unpackedSize: 20, entryCount: 1, inventorySHA256: "", engineCommit: nil, shaderChain: nil, options: [:])
        func manifest(_ id: String, _ selection: CloudGameSources.ArchivedSelection? = nil) -> CloudGameManifest {
            .init(version: 1, titleID: id, createdAt: .distantPast, artifacts: [app], sourceSelection: selection)
        }
        let legacy = try repository.importCloudGames([manifest(title)], in: fixture.root)
        let priorID = try XCTUnwrap(legacy.nxnativeGames.first { $0.titleId == title }?.id)
        // A folder label alone cannot authorize a NUP from another exact edition.
        let changedFolder = String(decoding: data, as: UTF8.self).replacingOccurrences(of: folder, with: "Fixture [\(other)]")
        let wrong = try JSONDecoder().decode(CloudGameSources.ArchivedSelection.self, from: Data(changedFolder.utf8))
        let manifests = [manifest(title, decoded), manifest(other, wrong)]
        let imported = try repository.importCloudGames(manifests, in: fixture.root, sourceRoot: fixture.root)
        let game = try XCTUnwrap(imported.nxnativeGames.first { $0.titleId == title })
        XCTAssertEqual(game.id, priorID)
        XCTAssertEqual(game.sources.map(\.nupProgram), [program, program])
        XCTAssertEqual(game.sources.map(\.versionString), ["v0", "v65536"])
        XCTAssertEqual(game.sources.map(\.url), Array(repeating: CloudGameSources.importedFolder(for: priorID, in: fixture.root)
            .appendingPathComponent(folder).appendingPathComponent("Game.nup"), count: 2))
        XCTAssertEqual(SourceSelection.programIndex(for: game.sources, titleID: title, nupPrograms: true), 2)
        XCTAssertEqual(imported.nxnativeGames.first { $0.titleId == other }?.sources, [])
        XCTAssertEqual(try repository.importCloudGames(manifests, in: fixture.root, sourceRoot: fixture.root), imported)
    }

    func testScanUsesLatestFlagsAndDoesNotReplaceSteamOrLegacyBytes() throws {
        let (fixture, store, original) = try mixed()
        let bytes = try Data(contentsOf: fixture.root.appendingPathComponent("library.json"))
        let repository = CatalogRepository(store: store)
        var scanned = try XCTUnwrap(original.games[0].nxnativeGame)
        scanned.name = "Renamed"; scanned.isFavorite = true; scanned.isHidden = true
        _ = try repository.updateNXNative(id: scanned.id) { $0.isFavorite = false; $0.isHidden = false; $0.appIconOnMac = true }
        let result = try repository.mergeNXNative(scanned: [scanned], observedFrom: original.nxnativeGames)
        XCTAssertEqual(result.games[0].name, "Renamed")
        XCTAssertFalse(result.games[0].isFavorite); XCTAssertFalse(result.games[0].isHidden)
        XCTAssertEqual(result.nxnativeGames[0].appIconOnMac, true)
        XCTAssertEqual(result.games[1], original.games[1])
        XCTAssertEqual(try Data(contentsOf: fixture.root.appendingPathComponent("library.json")), bytes)
    }

    func testWrongIntegrationAndMissingIDRejectBeforeOperationEffects() throws {
        let (_, store, original) = try mixed()
        let repository = CatalogRepository(store: store)
        var calls = 0
        XCTAssertThrowsError(try repository.updateNXNative(id: original.games[1].id) { _ in calls += 1 })
        XCTAssertThrowsError(try repository.updateNXNative(id: UUID()) { _ in calls += 1 })
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try repository.load(), original)
    }

    func testMutationDoesNotReplayEffectsWhenPublicationFails() throws {
        let (fixture, store, original) = try mixed()
        let failing = CatalogStore(directory: fixture.root, publication: .init { _, _, _, _ in throw POSIXError(.ENOSPC) })
        let repository = CatalogRepository(store: failing)
        var calls = 0
        XCTAssertThrowsError(try repository.updateNXNative(id: original.games[0].id) { game in calls += 1; game.isFavorite = false })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try store.loadOrMigrate(), original)
    }

    func testConcurrentChangeIsNotOverwrittenAndOperationIsNotReplayed() throws {
        let (fixture, store, original) = try mixed()
        let repository = CatalogRepository(store: store)
        var calls = 0
        XCTAssertThrowsError(try repository.updateNXNative(id: original.games[0].id) { game in
            calls += 1
            var other = try CatalogStore(directory: fixture.root).loadOrMigrate()
            other.games[1].setHidden(false)
            _ = try CatalogStore(directory: fixture.root).save(other, expectedRevision: other.revision)
            game.isFavorite = false
        }) { XCTAssertEqual($0 as? CatalogStoreError, .staleRevision) }
        XCTAssertEqual(calls, 1)
        let actual = try repository.load()
        XCTAssertFalse(actual.games[1].isHidden)
        XCTAssertTrue(actual.games[0].isFavorite)
    }

    func testSourceLessRecordsUseUUIDAndCannotMergeOnMissingTitleID() throws {
        let (_, store, _) = try mixed()
        let repository = CatalogRepository(store: store)
        var a = CatalogTestSupport.completeLegacyGame(id: UUID()), b = CatalogTestSupport.completeLegacyGame(id: UUID())
        a.titleId = nil; b.titleId = nil
        a.name = "A"; b.name = "B"
        let added = try repository.mergeNXNative(scanned: [a, b])
        XCTAssertEqual(added.nxnativeGames.count, 3)
        a.name = "A changed"
        let refreshed = try repository.mergeNXNative(scanned: [a])
        XCTAssertEqual(refreshed.nxnativeGames.count, 3)
        XCTAssertEqual(refreshed.nxnativeGames.first { $0.id == a.id }?.name, "A changed")
        XCTAssertEqual(refreshed.nxnativeGames.first { $0.id == b.id }?.name, "B")
    }

    func testBatchPatchPreservesOtherIntegrationAndRejectsDuplicateIDs() throws {
        let (_, store, original) = try mixed()
        let repository = CatalogRepository(store: store)
        let updated = try repository.updateNXNativeGames { $0[0].status = .needsRebuild }
        XCTAssertEqual(updated.games[1], original.games[1])
        XCTAssertEqual(updated.nxnativeGames[0].status, .needsRebuild)
        XCTAssertThrowsError(try repository.updateNXNativeGames { $0.append($0[0]) })
        XCTAssertEqual(try repository.load(), updated)
    }
    func testBuildOutcomeUpdatesBuildOwnedFieldsAndKeepsCurrentPersonalAndSourceChoices() throws {
        let (_, store, original) = try mixed()
        let repository = CatalogRepository(store: store)
        var outcome = try XCTUnwrap(original.games[0].nxnativeGame)
        outcome.url = URL(fileURLWithPath: "/tmp/Finished.app")
        outcome.status = .built; outcome.sizeBytes = 9000; outcome.versionString = "3.0"
        outcome.appIconPending = true; outcome.pendingInstall = nil
        outcome.portingFailure = nil; outcome.portingFailureReason = nil
        _ = try repository.updateNXNative(id: outcome.id) {
            $0.isFavorite = false; $0.isHidden = false; $0.appIconOnMac = true
            $0.settings.language = "fr"; $0.name = "User choice"
        }
        let updated = try repository.recordNXNativeBuild(outcome)
        let game = try XCTUnwrap(updated.games[0].nxnativeGame)
        XCTAssertFalse(game.isFavorite); XCTAssertFalse(game.isHidden)
        XCTAssertEqual(game.settings.language, "fr"); XCTAssertEqual(game.name, "User choice")
        XCTAssertEqual(game.appIconOnMac, true)
        XCTAssertEqual(game.url.path, "/tmp/Finished.app"); XCTAssertEqual(game.sizeBytes, 9000)
        XCTAssertEqual(game.status, .built); XCTAssertEqual(game.versionString, "3.0")
        XCTAssertNil(game.pendingInstall); XCTAssertNil(game.portingFailureReason)
        XCTAssertEqual(game.sources, original.nxnativeGames[0].sources)
        XCTAssertEqual(updated.games[1], original.games[1])
    }

    func testOldScanCannotResetAnInProgressBuild() throws {
        let (_, store, original) = try mixed()
        let repository = CatalogRepository(store: store)
        let id = original.games[0].id
        _ = try repository.updateNXNative(id: id) { $0.status = .building }
        let refreshed = try repository.mergeNXNative(scanned: original.nxnativeGames, observedFrom: original.nxnativeGames)
        XCTAssertEqual(refreshed.nxnativeGames[0].status, .building)
    }

    func testOldScanCannotRevertACompletedBuildOrRunItsReconcileCallbackForThatGame() throws {
        let (_, store, original) = try mixed()
        let repository = CatalogRepository(store: store)
        var outcome = original.nxnativeGames[0]
        outcome.modificationDate = Date(timeIntervalSince1970: 1000)
        outcome.versionString = "3.0"; outcome.sizeBytes = 9000
        outcome.pendingInstall = nil; outcome.status = .built
        outcome.lastBuild = BuildRecord(startedAt: Date(timeIntervalSince1970: 900), endedAt: Date(timeIntervalSince1970: 1000), exitCode: 0)
        _ = try repository.recordNXNativeBuild(outcome)
        var accepted = Set<UUID>()
        let refreshed = try repository.mergeNXNative(scanned: original.nxnativeGames, observedFrom: original.nxnativeGames) { games, ids in
            accepted = ids
            for index in games.indices where ids.contains(games[index].id) { games[index].sizeBytes = 1234 }
        }
        XCTAssertFalse(accepted.contains(outcome.id))
        XCTAssertEqual(refreshed.nxnativeGames[0].versionString, "3.0")
        XCTAssertEqual(refreshed.nxnativeGames[0].sizeBytes, 9000)
        XCTAssertEqual(refreshed.nxnativeGames[0].modificationDate, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(refreshed.nxnativeGames[0].lastBuild, outcome.lastBuild)
    }

}
