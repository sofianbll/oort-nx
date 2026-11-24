import Foundation
import NXLibraryCore
import ArcanePorting

extension AppViewModel {
    @MainActor func restoreActivity() async {
        guard !hasLoadedActivity else { return }
        let history = await activityStore.load()
        let builds = await porting.buildQueueStore.load()
        guard !hasLoadedActivity else { return }
        let hasNewResults = !activityResults.entries.isEmpty
        activityResults.restore(history)
        if cloudLibrary.moveJournalUnreadable {
            showSettingsNotice(title: L10n.text("Move library"),
                               message: L10n.format("The saved library move cannot be read or lacks Drive identities. Cloud transfers are paused. Keep this recovery record: %@.",
                                                    [cloudLibrary.moveJournal.file.path]), cancelTitle: "Close")
        }
        if let pending = cloudLibrary.pendingMove, cloudLibrary.libraryMove == nil,
           !activityResults.entries.contains(where: { $0.id == pending.id && $0.job == .move(pending.request) && $0.canRetry }) {
            activityResults.record(id: pending.id, job: .move(pending.request), name: pending.request.destination,
                                   outcome: .failed(L10n.text(LibraryMoveActivity.unfinished)))
        }
        hasLoadedActivity = true
        if hasNewResults { persistActivity() }
        porting.restoreBuildQueue(builds)
        if let pending = cloudLibrary.pendingMove, let approvedTool = pending.toolIdentity,
           cloudLibrary.resolvedDriveTool.flatMap(RcloneDownload.identity(of:)) == approvedTool {
            startLibraryMove(pending.request, id: pending.id, verifyOnly: true)
        }
    }

    func recordActivity(_ id: UUID, job: ActivityHistory.Job, name: String?, outcome: ActivityHistory.Outcome) {
        activityResults.record(id: id, job: job, name: name, outcome: outcome)
        persistActivity()
    }

    func clearActivity(_ id: UUID? = nil) {
        guard hasLoadedActivity, !cloudLibrary.isRestoringQueue, !cloudLibrary.isPublishingReconfirmation else { return }
        let pending = cloudLibrary.pendingMove.flatMap { pending in
            activityResults.entries.first { $0.id == pending.id }
        }
        activityResults.clear(id)
        if let pending { activityResults.restore([pending]) }
        persistActivity()
    }

    private func persistActivity() {
        guard hasLoadedActivity else { return }
        hasActivityWrites = true
        activityStore.save(activityResults.entries)
    }

    @MainActor func retryActivity(_ id: UUID) {
        // Keep the last result on disk until this attempt actually produces another one.
        let results = activityResults
        let queued = results.retry(id) { result in
            switch result.job {
            case .build(let request): return porting.retryBuild(request)
            case .cloud(let entry): return retryCloudOperation(entry, token: id)
            case .move(let move): return startLibraryMove(move, id: id) != nil
            }
        }
        if !queued, results.entries.contains(where: { $0.id == id && $0.canRetry }) {
            showSettingsNotice(title: L10n.text("Retry"), message: L10n.text("This activity cannot be retried right now."))
        }
    }
}
