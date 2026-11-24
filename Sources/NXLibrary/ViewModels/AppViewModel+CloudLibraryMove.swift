import Foundation
import NXLibraryCore
import ArcanePorting

struct LibraryMoveActivity {
    static let unfinished = "Could not finish moving games. Try again to move the remaining files."
    let id: UUID
    let request: LibraryMoveRequest
    var fraction: Double?
    var isCancelling = false
    var isVerifying = false
    var canCancel: Bool { !isCancelling && !isVerifying }
}

extension AppViewModel {
    @MainActor @discardableResult
    func startLibraryMove(_ request: LibraryMoveRequest, id: UUID = UUID(),
                          onConflicts: (([String]) -> Void)? = nil) -> UUID? {
        let cloud = cloudLibrary
        let preference = cloud.preference
        let currentRoot = preference.root.split(separator: "/").joined(separator: "/")
        guard canStartLibraryMove, !cloud.moveJournalUnreadable, preference.remote == request.plan.remote,
              currentRoot == request.plan.source || (cloud.pendingMove != nil && currentRoot == request.destination),
              CloudDriveFolders.canMove(from: request.plan.source, to: request.destination) else { return nil }
        if let previous = cloud.pendingMove, previous.request != request { return nil }
        let id = cloud.pendingMove?.id ?? id
        let chosen = cloud.needsDriveToolChoice ? nil : cloud.resolvedDriveTool
        cloud.isChangingConnection = true
        cloud.libraryMove = .init(id: id, request: request)
        cloud.libraryMoveTask = Task { [self] in
            defer {
                cloud.libraryMove = nil
                cloud.libraryMoveTask = nil
                cloud.isChangingConnection = false
                resumeLibraryScanAfterCloud()
            }
            let job = ActivityHistory.Job.move(request)
            var outcome: ActivityHistory.Outcome
            do {
                guard let tool = chosen, RcloneStorageBackend.isExecutable(tool)
                else { throw StorageBackendError.backendUnavailable }
                guard cloud.libraryMove?.isCancelling != true else { throw CancellationError() }
                let lease = try cloud.moveJournal.acquire()
                defer { withExtendedLifetime(lease) {} }
                let folders = CloudDriveFolders(remote: request.plan.remote, executable: tool, reference: preference.referenceFolder)
                let pending: LibraryMoveJournal.Pending
                if let saved = try cloud.moveJournal.load() {
                    guard saved.request == request, saved.id == id else { throw CloudArchiveError.busy }
                    pending = saved
                    // A previous journal link/rename may have succeeded with a failed directory sync.
                    try cloud.moveJournal.sync()
                } else {
                    guard cloud.pendingMove == nil, cloud.matchesPersistedStorage() else { throw CloudArchiveError.busy }
                    guard CloudDriveFolders.isBound(request.plan, to: request.destination) else {
                        throw CloudDriveFolders.MoveFailure.missingIdentity
                    }
                    try await folders.preflightMove(request.plan, to: request.destination)
                    var sources = preference.sourcesRootOverride
                    if sources == nil {
                        sources = try await folders.originalSourcesRoot(request.plan, to: request.destination)
                    }
                    guard cloud.libraryMove?.isCancelling != true else { throw CancellationError() }
                    pending = .init(id: id, request: request, sourcesRoot: sources)
                    do { try cloud.moveJournal.begin(pending) }
                    catch {
                        // Publication may have succeeded before a local sync error.
                        cloud.recoverPendingMove()
                        throw error
                    }
                }
                cloud.setPendingMove(pending)
                let conflicts = try await folders.move(request.plan, to: request.destination) { done, total in
                    try await MainActor.run {
                        if cloud.libraryMove?.isCancelling == true { throw CancellationError() }
                        cloud.libraryMove?.fraction = total > 0 ? Double(done) / Double(total) : nil
                        cloud.libraryMove?.isVerifying = done == total
                    }
                }
                onConflicts?(conflicts)
                if conflicts.isEmpty {
                    let verified = try cloud.moveJournal.markVerified(pending)
                    cloud.setPendingMove(verified)
                    cloud.configure(remote: request.plan.remote, root: request.destination, enabled: true,
                                    sourcesRoot: pending.sourcesRoot)
                    guard AppData.preferences.synchronize() else { throw StorageBackendError.publicationFailed }
                    try cloud.moveJournal.finish(verified)
                    cloud.setPendingMove(nil)
                    outcome = .succeeded
                } else {
                    outcome = .failed(L10n.text("Library files conflict. Keep both copies until you have reconciled them, then retry."))
                }
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed((error as? CloudDriveFolders.MoveFailure)?.localizedDescription
                    ?? (error as? CloudLibraryFailure)?.localizedDescription
                    ?? (error as? CloudArchiveError)?.localizedDescription
                    ?? (error as? RcloneConfiguration.Failure)?.localizedDescription
                    ?? L10n.text(LibraryMoveActivity.unfinished))
            }
            recordActivity(id, job: job, name: request.destination, outcome: outcome)
            if case .succeeded = outcome {
                restoreCloudQueue()
                importCloudGames()
            }
        }
        return id
    }

    @MainActor func cancelLibraryMove(_ id: UUID) {
        guard let move = cloudLibrary.libraryMove, move.id == id, move.canCancel else { return }
        cloudLibrary.libraryMove?.isCancelling = true
    }
}
