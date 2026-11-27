import XCTest
import ArcanePorting
import OortLibrary

final class CloudTransferPresentationTests: XCTestCase {
    func testTransferLifecycleAndActions() {
        let sample = CloudArchiveProgress(.downloading, kind: .app,
            transfer: .init(bytesTransferred: 40, totalBytes: 100))
        let queued = CloudTransferPresentation(progress: sample, queued: true)
        let preparing = CloudTransferPresentation(progress: nil, queued: false)
        let running = CloudTransferPresentation(progress: sample, queued: false)
        let verifying = CloudTransferPresentation(progress: .init(.verifying, downloadComplete: true), queued: false)
        let waiting = CloudTransferPresentation(progress: .init(.readyToInstall), queued: false)

        XCTAssertEqual(queued, .queued)
        XCTAssertEqual(preparing, .running(nil))
        XCTAssertEqual(running, .running(0.4))
        XCTAssertEqual(verifying, .verifying(1))
        XCTAssertEqual(waiting, .waitingForGame)
        XCTAssertEqual([queued, preparing, running, verifying, waiting].map(\.canCancel), Array(repeating: true, count: 5))
        XCTAssertFalse(CloudTransferPresentation.ready.canCancel)
        XCTAssertFalse(CloudTransferPresentation.failed.canCancel)
        XCTAssertEqual(verifying.coverFraction, 1)
        XCTAssertEqual(waiting.coverFraction, 1)
    }

    func testGaugeIsExclusiveAndUnknownTotalIsNotAPercentage() {
        for kind in [CloudArtifactKind.app, .cache, nil] {
            for direction in [CloudArchiveProgress.Phase.downloading, .uploading] {
                let unknown = CloudTransferPresentation(progress: .init(direction, kind: kind,
                    transfer: .init(bytesTransferred: 40, totalBytes: 0)), queued: false)
                XCTAssertEqual(unknown, .running(nil))
                XCTAssertEqual(unknown.gauge(hasCover: true, hasDownloadPill: true), .cover)
                XCTAssertEqual(unknown.gauge(hasCover: false, hasDownloadPill: true), .bar)
            }
        }
        let measured = CloudTransferPresentation.running(0.4)
        XCTAssertEqual(measured.gauge(hasCover: false, hasDownloadPill: true), .download)
        XCTAssertEqual(measured.gauge(hasCover: false, hasDownloadPill: false), .bar)
        for state in [CloudTransferPresentation.queued, .verifying(nil), .waitingForGame, .ready, .failed] {
            XCTAssertEqual(state.gauge(hasCover: false, hasDownloadPill: false), .none)
        }
        XCTAssertNil(Motion.transfer(true))
        XCTAssertNil(Motion.buildArt(true, .fill))
    }

    func testManagementEntryNeverAppearsTwice() {
        XCTAssertEqual(CloudGameManagementPlacement(nextToPlay: true, detailsLink: true), .primaryActions)
        XCTAssertEqual(CloudGameManagementPlacement(nextToPlay: true, detailsLink: false), .primaryActions)
        XCTAssertEqual(CloudGameManagementPlacement(nextToPlay: false, detailsLink: true), .detailsLink)
        XCTAssertEqual(CloudGameManagementPlacement(nextToPlay: false, detailsLink: false), .detailsLink)
        XCTAssertNil(CloudGameManagementPlacement(nextToPlay: false, detailsLink: false, cloudEnabled: false))
    }
}
