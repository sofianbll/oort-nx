import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class FirstRunSetupTests: XCTestCase {
    func testSteamChoiceRestoresBothOnAndOffAfterInterruptedPorting() {
        for choice in [true, false] {
            var first = FirstRunSetup()
            first.chooseSteam(choice)
            first.openPorting()
            let resumed = FirstRunSetup(completed: false, savedPage: first.pageToRemember,
                                        savedSteamChoice: first.steamChoiceToRemember)
            XCTAssertEqual(resumed.page, .requirements)
            XCTAssertEqual(resumed.steamChoice, choice)
            XCTAssertEqual(resumed.steamChoiceToRemember, choice)
        }
    }

    func testCompletedSetupDropsSavedChoiceButKeepsItUntilTheShellAppliesIt() {
        var flow = FirstRunSetup(savedSteamChoice: true)
        flow.finish()
        XCTAssertEqual(flow.steamChoice, true)
        XCTAssertNil(flow.steamChoiceToRemember)
        XCTAssertNil(FirstRunSetup(completed: true, savedSteamChoice: true).steamChoice)
        XCTAssertNil(FirstRunSetup().steamChoiceToRemember)
    }

    func testSourceReviewWaitsForASingleReadyTitleAndConsumesEachArrivalOnce() {
        var entry = FirstRunSetup.ReviewEntry()
        let id = UUID()
        XCTAssertFalse(entry.consume(id, isReady: false, titleCount: 0))
        XCTAssertFalse(entry.consume(id, isReady: true, titleCount: 2))
        XCTAssertTrue(entry.consume(id, isReady: true, titleCount: 1))
        XCTAssertFalse(entry.consume(id, isReady: true, titleCount: 1))
        XCTAssertFalse(entry.consume(nil, isReady: true, titleCount: 1))
    }

    func testAnotherAcceptedSelectionCanReviewWithoutChangingRoute() {
        var entry = FirstRunSetup.ReviewEntry()
        let first = UUID(), second = UUID()
        XCTAssertTrue(entry.consume(first, isReady: true, titleCount: 1))
        XCTAssertTrue(entry.consume(second, isReady: true, titleCount: 1))
        XCTAssertFalse(entry.consume(second, isReady: true, titleCount: 1))
    }

    func testNewTourResumesOnEveryScreenAndCanReopenWithoutRestartingOnQuit() {
        var flow = FirstRunSetup(completed: false)
        for page in FirstRunSetup.Page.tour {
            XCTAssertEqual(flow.page, page)
            XCTAssertEqual(FirstRunSetup(savedPage: flow.pageToRemember).page, page)
            XCTAssertEqual(flow.moveTour(1), page != .look)
        }
        flow.finish()
        flow.openTour()
        XCTAssertEqual(flow.page, .welcome)
        XCTAssertTrue(flow.isCompleted)
        XCTAssertNil(flow.pageToRemember)
    }

    func testInterruptedOldSetupResumesWhereItWas() {
        XCTAssertEqual(FirstRunSetup(completed: false, savedPage: "games").page, .games)
        XCTAssertEqual(FirstRunSetup(completed: false, savedPage: "requirements").page, .requirements)
    }

    func testUnknownSavedPageStartsOnWelcome() {
        XCTAssertEqual(FirstRunSetup(completed: false, savedPage: "unknown").page, .welcome)
        XCTAssertEqual(FirstRunSetup(completed: false, savedPage: nil).page, .welcome)
    }

    func testPortingCardOpensRequirements() {
        var flow = FirstRunSetup(completed: false)
        flow.openPorting()
        XCTAssertEqual(flow.page, .requirements)
        XCTAssertEqual(flow.pageToRemember, "requirements")
        flow.returnToFound()
        XCTAssertEqual(flow.page, .found)
    }

    func testCompletedSetupNeverReturnsToFound() {
        var flow = FirstRunSetup(completed: true)
        XCTAssertEqual(flow.page, .requirements, "Settings → Open Setup starts on the requirements")
        flow.returnToFound()
        XCTAssertEqual(flow.page, .requirements)
    }

    func testFocusMovesThroughFoundRows() {
        typealias F = FirstRunSetup.Focus
        XCTAssertEqual(F.initialOnFound, .openLibrary)
        XCTAssertEqual(F.openLibrary.movedOnFound(.up, hasSteam: true), .portingCard)
        XCTAssertEqual(F.portingCard.movedOnFound(.up, hasSteam: true), .steamToggle)
        XCTAssertEqual(F.portingCard.movedOnFound(.up, hasSteam: false), .portingCard)
        XCTAssertEqual(F.steamToggle.movedOnFound(.down, hasSteam: true), .portingCard)
        XCTAssertEqual(F.portingCard.movedOnFound(.down, hasSteam: true), .openLibrary)
        XCTAssertEqual(F.openLibrary.movedOnFound(.down, hasSteam: true), .openLibrary)
        XCTAssertEqual(F.steamToggle.movedOnFound(.up, hasSteam: true), .steamToggle)
        XCTAssertEqual(F.steamToggle.movedOnFound(.left, hasSteam: true), .steamToggle)
    }

    func testNewUserContinuesToGamesBeforeSetupIsCompleted() {
        var flow = FirstRunSetup(completed: false, savedPage: "requirements")
        XCTAssertEqual(flow.page, .requirements)
        flow.advance()
        XCTAssertEqual(flow.page, .games)
        XCTAssertFalse(flow.isCompleted)
        XCTAssertEqual(flow.pageToRemember, "games")
    }

    func testSkipIsRememberedEvenWhenNoGamesHaveBeenAdded() {
        var flow = FirstRunSetup(completed: false)
        flow.advance()
        flow.finish()
        XCTAssertTrue(flow.isCompleted)
        XCTAssertEqual(flow.page, .requirements)
        XCTAssertNil(flow.pageToRemember)
        let nextLaunch = FirstRunSetup(completed: flow.isCompleted, savedPage: "games")
        XCTAssertTrue(nextLaunch.isCompleted)
        flow.advance()
        XCTAssertTrue(flow.isCompleted, "A stale Continue action must not restart onboarding")
    }

    func testInterruptedSetupResumesOnTheGamesPage() {
        var flow = FirstRunSetup(completed: false)
        flow.advance()
        let resumed = FirstRunSetup(completed: false, savedPage: flow.pageToRemember)
        XCTAssertEqual(resumed.page, .games)
        XCTAssertFalse(resumed.isCompleted)
    }

    func testManualReopenVisitsBothPagesWithoutClearingCompletion() {
        var flow = FirstRunSetup(completed: true)
        flow.advance()
        XCTAssertEqual(flow.page, .games)
        XCTAssertTrue(flow.isCompleted)
        XCTAssertNil(flow.pageToRemember)
        flow.goBack()
        XCTAssertEqual(flow.page, .requirements)
        XCTAssertTrue(flow.isCompleted)
    }

    func testExistingUsersIgnoreStaleOrUnknownProgress() {
        XCTAssertTrue(FirstRunSetup(completed: true, savedPage: "games").isCompleted)
        XCTAssertEqual(FirstRunSetup(completed: true, savedPage: "welcome").page, .requirements)
    }

    func testBackReturnsToRequirementsWithoutCompletingSetup() {
        var flow = FirstRunSetup(completed: false, savedPage: "games")
        flow.goBack()
        XCTAssertEqual(flow.page, .requirements)
        XCTAssertFalse(flow.isCompleted)
    }

    func testLibraryIsNotReportedEmptyWhileDiscoveryIsRunning() {
        XCTAssertEqual(FirstRunSetup.libraryState(isScanning: true, gameCount: 0), .scanning)
        XCTAssertEqual(FirstRunSetup.libraryState(isScanning: true, gameCount: 3), .scanning)
        XCTAssertEqual(FirstRunSetup.libraryState(isScanning: false, gameCount: 0), .empty)
        XCTAssertEqual(FirstRunSetup.libraryState(isScanning: false, gameCount: 1), .ready)
    }

    func testKeyboardAndControllerNavigationReachSkipAndBack() {
        var focus = FirstRunSetup.Focus.apps
        focus = focus.moved(.down)
        XCTAssertEqual(focus, .file)
        focus = focus.moved(.down)
        XCTAssertEqual(focus, .folder)
        focus = focus.moved(.down)
        XCTAssertEqual(focus, .finish)
        XCTAssertEqual(focus.moved(.left), .back)
        XCTAssertEqual(FirstRunSetup.Focus.back.moved(.right), .finish)
        XCTAssertEqual(focus.moved(.up), .folder)
        XCTAssertEqual(FirstRunSetup.Focus.apps.moved(.up), .apps)
    }

    func testRequirementsScreenDoesNotContainTheGameFolders() {
        let all = SetupItemID.allCases.map {
            SetupItem(id: $0, title: $0.rawValue, state: .ready, chip: "", about: "", detail: "")
        }
        let requirements = SetupCheck.requirements(all)
        XCTAssertEqual(requirements.map(\.id), [.xcode, .metal, .engine, .runtime, .keys])
        XCTAssertEqual(SetupGrid.rowCounts(requirements.count, maxPerRow: 3), [3, 2])
    }

    func testUnavailableGameFolderDoesNotReopenTheTechnicalSetup() {
        let folder = SetupItem(id: .library, title: "Game apps", state: .warning, chip: "", about: "", detail: "")
        XCTAssertFalse(SetupCheck.shouldReopen(previous: [.library: .ready], current: [folder]))
    }

    func testSteamChoiceSurvivesThePortingPath() {
        var setup = FirstRunSetup()
        XCTAssertNil(setup.steamChoice)
        setup.chooseSteam(true)
        setup.openPorting()
        setup.advance()
        setup.goBack()
        setup.returnToFound()
        XCTAssertEqual(setup.steamChoice, true)
        setup.chooseSteam(false)
        setup.openPorting()
        setup.finish()
        XCTAssertEqual(setup.steamChoice, false)
    }

    func testFinishedSetupTakesNoSteamChoice() {
        var setup = FirstRunSetup(completed: true)
        setup.chooseSteam(true)
        XCTAssertNil(setup.steamChoice)
    }

    func testLocalInventoryListsReadyAndUnidentifiedFilesWithoutTouchingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Moon.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let id = "0100000000011000"
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "org.nxnative.\(id)", "DMTitleID": id, "CFBundleName": "Moon"
        ], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let identified = root.appendingPathComponent("Moon [\(id)].xci")
        let unknown = root.appendingPathComponent("Unknown.xci")
        for file in [identified, unknown] { try Data([0xAF]).write(to: file) }

        let first = OnboardingInventory.read(apps: [root], files: root, existing: [])
        XCTAssertEqual(first.entries.map(\.name), ["Moon", "Unknown.xci"])
        let game = try XCTUnwrap(first.entries.first?.game)
        XCTAssertTrue(game.isPlayableLocally)
        XCTAssertEqual(game.sources.map { $0.url.resolvingSymlinksInPath().path },
                       [identified.resolvingSymlinksInPath().path])
        XCTAssertNil(first.entries.last?.game)
        let second = OnboardingInventory.read(apps: [root], files: root, existing: [game])
        XCTAssertTrue(second.entries.first?.alreadyInLibrary == true)
        XCTAssertEqual(try Data(contentsOf: unknown), Data([0xAF]))
    }

    func testConsentCopiesOnlyLibraryDataAndLeavesTheStableSourceIntact() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = AppDataProfile(home: home, isDevelopment: true)
        let origin = profile.stableSupportRoot
        let importer = DevelopmentProfileImporter()
        let sourceDB = CatalogStore(directory: origin)
        let source = try sourceDB.loadOrMigrate()
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        let excluded = ["prod.keys", "settings.json", "cloud-transfer-queue.json", "SaveBackups"]
        for item in excluded { try Data([0xAA]).write(to: origin.appendingPathComponent(item)) }
        XCTAssertTrue(DevelopmentProfileImporter.offersLibraryCopy(for: profile))
        let copied = try importer.prepare(profile: profile, contents: .library,
                                          sanitizeLibrary: DevelopmentProfileImporter.clearCopiedOperations,
                                          sourcePreferences: { XCTFail("Copy does not read preferences"); return [:] },
                                          savePreferences: { XCTAssertTrue($0.isEmpty) })
        XCTAssertTrue(copied)
        XCTAssertFalse(DevelopmentProfileImporter.offersLibraryCopy(for: profile))
        for item in excluded {
            XCTAssertFalse(FileManager.default.fileExists(atPath: profile.supportRoot.appendingPathComponent(item).path))
            XCTAssertEqual(try Data(contentsOf: origin.appendingPathComponent(item)), Data([0xAA]))
        }
        XCTAssertEqual(try sourceDB.loadOrMigrate(), source)
        XCTAssertEqual(try CatalogStore(directory: profile.supportRoot).loadOrMigrate().games, source.games)
    }
}
