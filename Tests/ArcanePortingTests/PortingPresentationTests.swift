import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class PortingPresentationTests: XCTestCase {
    func testCloudPillIsAfterOptionsAndPointerAndControllerUseTheSameIndex() {
        let all = DetailsFocus.Bands(screenshots: 3, actions: 5, more: 2)
        let pills = PortingPills.normal
        var focus = DetailsFocus()
        focus.setPillLimit(pills.count + 1)
        XCTAssertTrue(focus.right(in: all))
        XCTAssertTrue(focus.right(in: all))
        XCTAssertEqual(focus.pill, pills.detailsCloudIndex)
        focus.focus(zone: DetailsFocus.actionsZone, index: 0, in: all)
        focus.focus(zone: DetailsFocus.topZone, index: 3, in: all)
        XCTAssertEqual(focus.zone, DetailsFocus.topZone)
        XCTAssertEqual(focus.pill, 3)
        XCTAssertEqual(PortingPills.porting.detailsCloudIndex, 1)
        XCTAssertEqual(PortingPills.failed(.failed).detailsCloudIndex, 3)
        XCTAssertEqual(PortingPills.failed(.failed).detailsPresentation(cloudOnly: true), .normalAfterFailure(.failed))
    }

    private func progress(_ events: [BuildEvent]) -> PortingProgress {
        var progress = PortingProgress()
        events.forEach { progress.apply($0) }
        return progress
    }

    private var inShaders: PortingProgress {
        progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil), .step("compiling"),
                  .progress(fraction: 0.5, done: nil, total: nil, unit: nil, eta: 420)])
    }

    private var finishing: PortingProgress {
        progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil),
                  .stageEnd(name: "Mac shaders", ok: true, elapsed: 600, summary: nil),
                  .stage(k: 6, n: 7, name: "Mac host", step: nil),
                  .stageEnd(name: "Mac host", ok: true, elapsed: 30, summary: nil),
                  .stage(k: 7, n: 8, name: "Pipeline archive", step: nil)])
    }

    private func game(app: Bool, failure: PortingFailure? = nil) -> PortedGame {
        var game = PortedGame(name: "LumenTale",
                              url: URL(fileURLWithPath: app ? "/Applications/LumenTale.app" : "/Games/LumenTale"),
                              platform: .macApp, sizeBytes: 0, modificationDate: Date(timeIntervalSince1970: 0))
        game.status = app ? .built : .notBuilt
        game.portingFailure = failure
        return game
    }

    // MARK: - ETA

    func testETAAddsTheLastFinishingTimeToTheShaders() {
        XCTAssertEqual(PortingETA.text(inShaders, lastFinishingSeconds: 150), "About 10 min left")
    }

    func testActivityUsesLocalizedStagesAndCompactEstimates() {
        let french = AppLocale(language: .french, region: "FR")
        XCTAssertEqual(BuildStageCopy.title("Mac shaders", context: french), "Compilation des shaders")
        XCTAssertEqual(BuildStageCopy.title("unpack base", context: french), "Extraction des fichiers du jeu")
        XCTAssertEqual(BuildStageCopy.title("Prewarm pipelines", context: french), "Préparation du premier lancement")
        XCTAssertEqual(BuildStageCopy.title("unexpected engine stage", context: french), L10n.text("Porting", context: french))
        XCTAssertEqual(PortingETA.text(inShaders, lastFinishingSeconds: 150, context: french), "encore ~10 min")
        XCTAssertEqual(PortingETA.text(inShaders, lastFinishingSeconds: 150, context: french, compact: true), "~10 min")
        XCTAssertNil(PortingProgress().activityFraction)
        XCTAssertEqual(inShaders.activityFraction, 0.45)
    }

    func testETAWithoutAPreviousPortingShowsTheShadersOnly() {
        XCTAssertEqual(PortingETA.text(inShaders, lastFinishingSeconds: nil), "Shaders: about 7 min")
    }

    func testETANeverShowsLessThanAMinute() {
        let almost = progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil), .step("compiling"),
                               .progress(fraction: 0.99, done: nil, total: nil, unit: nil, eta: 20)])
        XCTAssertEqual(PortingETA.text(almost, lastFinishingSeconds: nil), "Shaders: about 1 min")
    }

    func testNoETABeforeTheShaders() {
        let preparing = progress([.stage(k: 3, n: 7, name: "rewrite", step: nil)])
        XCTAssertNil(PortingETA.text(preparing, lastFinishingSeconds: 150))
    }

    func testETAWhileFinishingCountsDownTheLastTime() {
        XCTAssertEqual(PortingETA.text(finishing, lastFinishingSeconds: 150), "About 2 min left")
        XCTAssertEqual(PortingETA.text(finishing, lastFinishingSeconds: nil), "Finishing up")

        // Live ETA during Pipeline archive takes precedence
        var pipelineArchive = finishing
        pipelineArchive.apply(.progress(fraction: 0.5, done: 1000, total: 2000, unit: "pipelines", eta: 5400))
        XCTAssertEqual(PortingETA.text(pipelineArchive, lastFinishingSeconds: 150), "Pipelines: about 1 hr 30 min")
        XCTAssertEqual(PortingETA.text(pipelineArchive, lastFinishingSeconds: nil), "Pipelines: about 1 hr 30 min")
    }

    func testPipelineEstimateDoesNotClaimToIncludePackingTheApp() {
        let p = progress([.stage(k: 5, n: 8, name: "Mac shaders", step: nil),
                          .stageEnd(name: "Mac shaders", ok: true, elapsed: 100, summary: nil),
                          .stage(k: 7, n: 8, name: "Pipeline archive", step: nil),
                          .progress(fraction: 0.5, done: 1000, total: 2000, unit: "pipelines", eta: 3600)])
        XCTAssertEqual(PortingETA.text(p, lastFinishingSeconds: nil), "Pipelines: about 1 hr")
    }

    func testPrewarmReportsActivityInsteadOfAnOlderFinishingEstimate() throws {
        var p = finishing
        p.apply(.stageEnd(name: "Pipeline archive", ok: true, elapsed: 60, summary: nil))
        p.apply(.stage(k: 8, n: 9, name: "Prewarm pipelines", step: "local GPU"))
        let before = p.overall
        let heartbeat = try XCTUnwrap(BuildEventParser.parse(
            #"{"ev":"progress","done":null,"total":null,"frac":null,"eta":null,"elapsed":3600}"#))
        p.apply(heartbeat)
        XCTAssertEqual(p.overall, before, "elapsed time is not a completed-work counter")
        XCTAssertNil(p.finishingETA)
        XCTAssertNil(p.activityFraction)
        for previousTime: Double? in [nil, 60, 7200] {
            XCTAssertEqual(PortingETA.text(p, lastFinishingSeconds: previousTime), "Preparing the first launch")
        }
        p.apply(.stageEnd(name: "Prewarm pipelines", ok: true, elapsed: 3600, summary: nil))
        p.apply(.stage(k: 9, n: 9, name: "Mac app", step: nil))
        XCTAssertEqual(PortingETA.text(p, lastFinishingSeconds: nil), "Finishing up")
    }

    func testStoppingPrewarmClearsTheActivityCaption() {
        var p = finishing
        p.apply(.stage(k: 8, n: 9, name: "Prewarm pipelines", step: nil))
        XCTAssertEqual(PortingETA.text(p, lastFinishingSeconds: 60), "Preparing the first launch")
        p.finish(success: false)
        XCTAssertNil(PortingETA.text(p, lastFinishingSeconds: 60))
    }

    func testETAFormatsHoursAndMinutesWhenOverAnHour() {
        let oneHour = progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil), .step("compiling"),
                                .progress(fraction: 0.1, done: nil, total: nil, unit: nil, eta: 3600)])
        XCTAssertEqual(PortingETA.text(oneHour, lastFinishingSeconds: nil), "Shaders: about 1 hr")

        let longShaders = progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil), .step("compiling"),
                                    .progress(fraction: 0.5, done: nil, total: nil, unit: nil, eta: 15165)])
        XCTAssertEqual(PortingETA.text(longShaders, lastFinishingSeconds: nil), "Shaders: about 4 hr 13 min")
        XCTAssertEqual(PortingETA.text(longShaders, lastFinishingSeconds: 120), "About 4 hr 15 min left")

        let longFinishing = progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil),
                                      .stageEnd(name: "Mac shaders", ok: true, elapsed: 600, summary: nil),
                                      .stage(k: 6, n: 7, name: "Mac host", step: nil)])
        XCTAssertEqual(PortingETA.text(longFinishing, lastFinishingSeconds: 3600), "About 1 hr left")
        XCTAssertEqual(PortingETA.text(longFinishing, lastFinishingSeconds: 3900), "About 1 hr 5 min left")
    }

    // MARK: - Stage Elapsed Time

    func testElapsedFormatsSecondsMinutesAndHours() {
        XCTAssertEqual(PortingETA.elapsed(0), "0 s")
        XCTAssertEqual(PortingETA.elapsed(6), "6 s")
        XCTAssertEqual(PortingETA.elapsed(59.4), "59 s")
        XCTAssertEqual(PortingETA.elapsed(60), "1:00")
        XCTAssertEqual(PortingETA.elapsed(61), "1:01")
        XCTAssertEqual(PortingETA.elapsed(397), "6:37")
        XCTAssertEqual(PortingETA.elapsed(3599), "59:59")
        XCTAssertEqual(PortingETA.elapsed(3600), "1:00:00")
        XCTAssertEqual(PortingETA.elapsed(3665), "1:01:05")
        // 252 minutes 45 seconds (15165 s) -> 4 hours 12 minutes 45 seconds
        XCTAssertEqual(PortingETA.elapsed(15165), "4:12:45")
    }

    func testQueuedBuildOnlyReplacesPrimaryPillUntilItStarts() {
        let existing = game(app: true, failure: .failed)
        let queued = PortingPills.make(game: existing, portingGameID: UUID(), queued: true)
        XCTAssertEqual(queued, .queued)
        XCTAssertEqual(queued.detailsPresentation(cloudOnly: true), .queued)
        XCTAssertEqual(queued.count, PortingPills.normal.count)
        XCTAssertEqual(queued.detailsCloudIndex, PortingPills.normal.detailsCloudIndex)
        XCTAssertEqual((0..<4).filter(queued.cancelsQueuedBuild(at:)), [0])
        let promoted = PortingPills.make(game: existing, portingGameID: existing.id, queued: true)
        XCTAssertEqual(promoted, .porting)
        XCTAssertFalse(promoted.cancelsQueuedBuild(at: 0))
        XCTAssertEqual(PortingPills.make(game: existing, portingGameID: nil), .normalAfterFailure(.failed))
    }

    // MARK: - Tile look

    func testTileFollowsThePortingPhase() {
        let porting = game(app: false)
        let preparing = progress([.stage(k: 3, n: 7, name: "rewrite", step: "checking the inputs")])
        XCTAssertEqual(PortingTileLook.make(game: porting, portingGameID: porting.id, progress: preparing, resting: .normal),
                       .preparing(step: 3, count: 7, title: "Rewrite", detail: "checking the inputs"))
        XCTAssertEqual(PortingTileLook.make(game: porting, portingGameID: porting.id, progress: inShaders, resting: .normal),
                       .filling(0.45))
        XCTAssertEqual(PortingTileLook.make(game: porting, portingGameID: UUID(), progress: inShaders,
                                            resting: .toBuild), .toBuild)
    }

    /// Every mix of app and game files, here, in the cloud, nowhere or not checked yet.
    func testTileKeepsItsColoursOneGestureFromPlaying() {
        func look(_ playable: Bool = false, app: Bool?, here: Bool = false, files: Bool?) -> PortingTileLook {
            .resting(playable: playable, appInCloud: app, filesHere: here, filesInCloud: files)
        }
        for app in [true, false, nil] { for files in [true, false, nil] {
            XCTAssertEqual(look(true, app: app, files: files), .normal)
            XCTAssertEqual(look(app: app, here: true, files: files), app == true ? .toDownload : .toBuild)
            XCTAssertEqual(look(app: true, files: files), .toDownload)
        } }
        XCTAssertEqual(look(app: false, files: true), .toDownloadFiles)
        XCTAssertEqual(look(app: nil, files: true), .toDownloadFiles)
        XCTAssertEqual(look(app: false, files: false), .missing)
        XCTAssertEqual(look(app: nil, files: false), .unchecked)
        XCTAssertEqual(look(app: false, files: nil), .unchecked)
    }

    func testMissingAppKeepsUnavailableActions() {
        var missing = game(app: true)
        missing.status = .appMissing
        XCTAssertNotEqual(PortingPills.make(game: missing, portingGameID: nil), .normal)
    }

    func testMissingSourceFilesDoNotOfferPlayOrAttachSourcesAsPrimaryAction() {
        var missing = game(app: false)
        missing.sources = [GameFileItem(url: URL(fileURLWithPath: "/missing-\(UUID())/base.nsp"), kind: .base, sizeBytes: 1)]
        XCTAssertNotEqual(PortingPills.make(game: missing, portingGameID: nil), .normal)
    }

    func testWorkingAppStaysPlayableWhenSourcesAreUnavailable() {
        var existing = game(app: true)
        existing.status = .builtSourcesMissing
        existing.sources = [GameFileItem(url: URL(fileURLWithPath: "/missing-\(UUID())/base.nsp"), kind: .base, sizeBytes: 1)]
        XCTAssertEqual(PortingTileLook.make(game: existing, portingGameID: nil, progress: nil, resting: .normal), .normal)
        XCTAssertEqual(PortingPills.make(game: existing, portingGameID: nil), .normal)
        XCTAssertTrue(existing.isPlayableLocally)
    }

    // MARK: - Pills

    func testPillsFollowThePorting() {
        let fresh = game(app: false)
        XCTAssertEqual(PortingPills.make(game: fresh, portingGameID: fresh.id), .porting)
        XCTAssertEqual(PortingPills.porting.count, 1)
        XCTAssertEqual(PortingPills.make(game: fresh, portingGameID: nil), .normal)
        XCTAssertEqual(PortingPills.make(game: game(app: false, failure: .failed), portingGameID: nil),
                       .failed(.failed))
        XCTAssertEqual(PortingPills.failed(.failed).count, 3)
        XCTAssertEqual(PortingPills.make(game: game(app: true, failure: .cancelled), portingGameID: nil),
                       .normalAfterFailure(.cancelled))
        XCTAssertEqual(PortingPills.normalAfterFailure(.failed).count, 3)
    }

    // MARK: - The failure survives a relaunch

    func testFailureIsSavedWithTheGame() throws {
        let saved = try JSONEncoder().encode(game(app: false, failure: .failed))
        XCTAssertEqual(try JSONDecoder().decode(PortedGame.self, from: saved).portingFailure, .failed)
        var old = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        old.removeValue(forKey: "portingFailure")
        let legacy = try JSONSerialization.data(withJSONObject: old)
        XCTAssertNil(try JSONDecoder().decode(PortedGame.self, from: legacy).portingFailure)
    }

    // MARK: - Spotlight

    /// The porting game is the first game: right after the Add game card, never before the cards.
    func testThePortingGameSitsRightAfterAddGame() {
        let a = UUID(), b = UUID()
        let row = SpotlightRow.build(gameIDs: [a, b], enabledCards: [.collection, .addGame], order: [], front: [b])
        XCTAssertEqual(row, [.card(.collection), .card(.addGame), .game(b), .game(a)])
        // The player moved Add game to the end: the porting game still follows it.
        let moved = SpotlightRow.build(gameIDs: [a, b], enabledCards: [.collection, .addGame],
                                       order: ["card:collection", "game:\(a.uuidString)", "game:\(b.uuidString)", "card:addGame"],
                                       front: [b])
        XCTAssertEqual(moved, [.card(.collection), .game(a), .card(.addGame), .game(b)])
        // Without the card: first among the games.
        let noCard = SpotlightRow.build(gameIDs: [a, b], enabledCards: [.collection], order: [], front: [b])
        XCTAssertEqual(noCard, [.card(.collection), .game(b), .game(a)])
        XCTAssertEqual(SpotlightRow.build(gameIDs: [a, b], enabledCards: [.collection], order: [], front: [UUID()]),
                       SpotlightRow.build(gameIDs: [a, b], enabledCards: [.collection], order: []))
    }

    /// The porting game leads, then the games Steam downloads this session, in the row's order.
    func testPortingThenDownloadsLeadTheRow() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let row = SpotlightRow.build(gameIDs: [a, b, c, d], enabledCards: [.collection, .addGame], order: [],
                                     front: [d, b])
        XCTAssertEqual(row, [.card(.collection), .card(.addGame), .game(d), .game(b), .game(a), .game(c)])
        XCTAssertEqual(SpotlightRow.leaders(porting: d, downloads: [c, a, d], row: [a, b, c, d]), [d, a, c])
        XCTAssertEqual(SpotlightRow.leaders(porting: nil, downloads: [c], row: [a, b, c, d]), [c])
        XCTAssertEqual(SpotlightRow.leaders(porting: nil, downloads: [], row: [a, b]), [])
        // A game no longer in the row (filtered out, or the download removed) leads nothing.
        XCTAssertEqual(SpotlightRow.leaders(porting: UUID(), downloads: [UUID()], row: [a, b]), [])
    }

    /// A game seen downloading stays remembered for the session, also once Steam has finished it.
    func testSessionDownloadsRememberEveryGameSeenDownloading() {
        func steam(_ appID: UInt32, downloading: Bool, id: UUID = UUID()) -> CatalogGame {
            var game = SteamCatalogGame(id: id, appID: appID, name: "G\(appID)")
            game.installations = [.init(libraryURL: URL(fileURLWithPath: "/tmp/steam"),
                                        contentURL: URL(fileURLWithPath: "/tmp/steam/steamapps/common/G\(appID)"),
                                        availability: downloading ? .unavailable : .available,
                                        isDownloading: downloading)]
            return CatalogGame(steam: game)
        }
        let downloading = steam(1, downloading: true), installed = steam(2, downloading: false)
        var session = SessionDownloads()
        XCTAssertTrue(session.note([downloading, installed]))
        XCTAssertEqual(session.ids, [downloading.id])
        XCTAssertFalse(session.note([downloading, installed]))
        let finished = steam(1, downloading: false, id: downloading.id)
        XCTAssertFalse(session.note([finished, installed]))
        XCTAssertEqual(session.ids, [downloading.id])
    }

    func testPillMovesStopAtTheLimit() {
        var state = SpotlightState(focus: .pills, pillIndex: 2)
        state.setPillLimit(1)
        XCTAssertEqual(state.pillIndex, 0)
        XCTAssertFalse(state.moveSideways(by: 1, screenshotCount: 0))
        var details = DetailsFocus()
        details.pill = 2
        details.setPillLimit(1)
        XCTAssertEqual(details.pill, 0)
        XCTAssertFalse(details.right(in: DetailsFocus.Bands(screenshots: 0, actions: 0, more: 0)))
    }

    func testLockIcon() {
        XCTAssertEqual(MaterialIcon.lock.rawValue, "\u{E897}")
    }

    func testCatalogTileLookIsDownloadingOnlyWhileSteamDownloads() {
        let library = URL(fileURLWithPath: "/tmp/steam"), content = URL(fileURLWithPath: "/tmp/steam/steamapps/common/G")
        var steam = SteamCatalogGame(appID: 10, name: "Steam game")
        steam.installations = [.init(libraryURL: library, contentURL: content, availability: .unavailable, isDownloading: true)]
        XCTAssertEqual(PortingTileLook.make(catalog: CatalogGame(steam: steam)), .downloading)
        steam.installations = [.init(libraryURL: library, contentURL: content, availability: .available)]
        XCTAssertEqual(PortingTileLook.make(catalog: CatalogGame(steam: steam)), .normal)
        XCTAssertEqual(PortingTileLook.make(catalog: CatalogGame(nxnative: CatalogTestSupport.completeLegacyGame())), .normal)
    }
}
