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
        hasLoadedActivity = true
        if hasNewResults { persistActivity() }
        porting.restoreBuildQueue(builds)
    }

    func recordActivity(_ id: UUID, job: ActivityHistory.Job, name: String?, outcome: ActivityHistory.Outcome) {
        activityResults.record(id: id, job: job, name: name, outcome: outcome)
        persistActivity()
    }

    func clearActivity(_ id: UUID? = nil) {
        guard hasLoadedActivity, !cloudLibrary.isRestoringQueue, !cloudLibrary.isPublishingReconfirmation else { return }
        activityResults.clear(id)
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
