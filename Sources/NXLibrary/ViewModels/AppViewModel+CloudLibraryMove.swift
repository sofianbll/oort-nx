import Foundation
import NXLibraryCore
import ArcanePorting

struct LibraryMoveActivity {
    static let unfinished = "Could not finish moving games. Try again to move the remaining files."
    let id: UUID
    let request: LibraryMoveRequest
    var fraction: Double?
    var isCancelling = false
}

extension AppViewModel {
    @MainActor @discardableResult
    func startLibraryMove(_ request: LibraryMoveRequest, id: UUID = UUID(), executable: URL? = nil,
                          onConflicts: (([String]) -> Void)? = nil) -> UUID? {
        let cloud = cloudLibrary
        let preference = cloud.preference
        let currentRoot = preference.root.split(separator: "/").joined(separator: "/")
        guard canStartLibraryMove, !cloud.moveJournalUnreadable, preference.remote == request.plan.remote,
              currentRoot == request.plan.source || (cloud.pendingMove != nil && currentRoot == request.destination),
              CloudDriveFolders.canMove(from: request.plan.source, to: request.destination) else { return nil }
        let pending: LibraryMoveJournal.Pending
        if let previous = cloud.pendingMove {
            guard previous.request == request else { return nil }
            pending = previous
        } else {
            pending = .init(id: id, request: request,
                            sourcesRoot: preference.sourcesRoot.split(separator: "/").joined(separator: "/"))
        }
        let id = pending.id
        let chosen = executable ?? cloud.chosenExecutable
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
                guard let tool = await Task.detached(priority: .utility, operation: {
                    chosen ?? RcloneStorageBackend.findExecutable()
                }).value else { throw StorageBackendError.backendUnavailable }
                guard cloud.libraryMove?.isCancelling != true else { throw CancellationError() }
                if cloud.pendingMove == nil {
                    do { try cloud.moveJournal.begin(pending) }
                    catch {
                        // Publication may have succeeded before a local sync error.
                        cloud.recoverPendingMove()
                        throw error
                    }
                    cloud.setPendingMove(pending)
                }
                let folders = CloudDriveFolders(remote: request.plan.remote, executable: tool)
                let conflicts = try await folders.move(request.plan, to: request.destination) { done, total in
                    await MainActor.run { cloud.libraryMove?.fraction = total > 0 ? Double(done) / Double(total) : nil }
                    if done < total, await MainActor.run(body: { cloud.libraryMove?.isCancelling == true }) {
                        throw CancellationError()
                    }
                }
                onConflicts?(conflicts)
                if conflicts.isEmpty {
                    cloud.configure(remote: request.plan.remote, root: request.destination, enabled: true,
                                    sourcesRoot: pending.sourcesRoot)
                    guard AppData.preferences.synchronize() else { throw StorageBackendError.publicationFailed }
                    try cloud.moveJournal.finish(pending)
                    cloud.setPendingMove(nil)
                    restoreCloudQueue()
                    importCloudGames()
                    outcome = .succeeded
                } else {
                    outcome = .failed(L10n.text("Library files conflict."))
                }
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed((error as? RcloneConfiguration.Failure)?.localizedDescription
                    ?? L10n.text(LibraryMoveActivity.unfinished))
            }
            recordActivity(id, job: job, name: request.destination, outcome: outcome)
        }
        return id
    }

    @MainActor func cancelLibraryMove(_ id: UUID) {
        guard cloudLibrary.libraryMove?.id == id else { return }
        cloudLibrary.libraryMove?.isCancelling = true
    }
}
