import Combine
import Foundation
import OortLibrary
import NxnativeAdapter

/// The one refresh behind every « Library refresh »: the game apps, the enabled sources and the cloud, at the same time.
/// Asking again replaces the refresh that runs. A source that is off and a Mac that is offline are never asked.
@MainActor
final class LibraryRefreshModel: ObservableObject {
    /// How long the toast stays; the activity center keeps the same words.
    static let hold: Duration = .seconds(8)

    @Published private(set) var current: LibraryRefresh?
    @Published private(set) var announces = false
    private(set) var cloudFailure: CloudLibraryFailure?
    weak var sources: CatalogSourcesModel?
    private unowned let app: AppViewModel
    private let isOnline: @Sendable () async -> Bool
    private var work: Task<Void, Never>?
    private var leaving: Task<Void, Never>?
    private var shown: AnyCancellable?

    init(app: AppViewModel, isOnline: @escaping @Sendable () async -> Bool = { await ConnectivityWatcher.isOnline() }) {
        self.app = app
        self.isOnline = isOnline
        // The shell, the menu and the activity center already follow the app's model.
        shown = objectWillChange.sink { [weak app] in app?.objectWillChange.send() }
    }

    private var parts: Set<LibraryRefresh.Part> {
        var parts: Set<LibraryRefresh.Part> = []
        if app.catalogSnapshot.source(.nxnative)?.isEnabled == true { parts.insert(.apps) }
        if sources?.configuration.isEnabled == true { parts.insert(.steam) }
        let cloud = app.cloudLibrary
        if cloud.preference.enabled, cloud.preference.remote != nil, !cloud.needsDriveTool, !cloud.hasPendingMove { parts.insert(.cloud) }
        return parts
    }

    func start() {
        work?.cancel()
        leaving?.cancel()
        let refresh = LibraryRefresh(parts: parts), known = Set(app.catalogGames.map(\.id))
        cloudFailure = nil
        current = refresh
        announces = true
        work = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for part in refresh.states.keys {
                    group.addTask { [weak self] in
                        guard let state = await self?.read(part, of: refresh.id) else { return }
                        await self?.end(part, state, of: refresh.id, known: known)
                    }
                }
            }
            self?.finish(refresh.id)
        }
    }

    func cancel() {
        guard current?.isRunning == true else { return }
        work?.cancel()
        current?.cancel()
        app.cloudLibrary.stopReading()
        if sources?.status == .scanning { sources?.cancel() }
        leave()
    }

    func clear() {
        guard current?.isRunning == false else { return }
        current = nil
        announces = false
    }

    #if DEBUG
    /// A state on screen without a refresh, for a capture.
    func preview(_ refresh: LibraryRefresh, failure: CloudLibraryFailure? = nil) {
        cloudFailure = failure
        current = refresh
        announces = true
    }
    #endif

    private func end(_ part: LibraryRefresh.Part, _ state: LibraryRefresh.State, of id: UUID, known: Set<UUID>) {
        guard current?.id == id, !Task.isCancelled else { return }
        current?.end(part, state)
        current?.noteAdded(app.catalogGames.count { !known.contains($0.id) })
    }

    private func finish(_ id: UUID) {
        guard current?.id == id, !Task.isCancelled else { return }
        current?.cancel()
        leave()
    }

    private func leave() {
        leaving?.cancel()
        leaving = Task { [weak self] in
            try? await Task.sleep(for: Self.hold)
            if !Task.isCancelled { self?.announces = false }
        }
    }

    private func read(_ part: LibraryRefresh.Part, of id: UUID) async -> LibraryRefresh.State {
        guard current?.id == id, !Task.isCancelled else { return .cancelled }
        switch part {
        case .apps:
            guard let work else { return .cancelled }
            return await readApps(work)
        case .steam: return await readSteam()
        case .cloud: return await readCloud()
        }
    }

    private func readApps(_ work: Task<Void, Never>) async -> LibraryRefresh.State {
        app.loadLibrary(request: .refresh(work))
        // A transfer may move an app: the scan waits for it, and runs by itself then.
        guard !app.cloudLibrary.isWorking else { return .stale(L10n.text("After the cloud transfer")) }
        for await _ in app.$isScanningLibrary.values where !app.isScanningLibrary && app.pendingLibraryScan == nil { break }
        return app.libraryScanWarnings.isEmpty ? .read : .stale(app.libraryScanWarnings.joined(separator: "\n"))
    }

    private func readSteam() async -> LibraryRefresh.State {
        guard let sources else { return .read }
        sources.refresh()
        await sources.settled()
        // What the state says is Settings › Sources' own words (SteamSourceEntries); a failure's own message comes first.
        let state = L10n.text(SteamSourceEntries.state(sources.status, found: sources.observedGameCount).detail.key)
        switch sources.status {
        case .failed: return .stale(sources.errorMessage ?? state)
        case .partial: return .stale(state)
        case .cancelled: return .cancelled
        default: return .read
        }
    }

    private func readCloud() async -> LibraryRefresh.State {
        let cloud = app.cloudLibrary
        let online = await isOnline()
        guard !Task.isCancelled else { return .cancelled }
        guard online else { return stale(.offline) }
        if cloud.archive == nil { await cloud.checkDriveScope()?.value }
        guard !Task.isCancelled else { return .cancelled }
        guard cloud.archive != nil else { return stale(cloud.connectionCheck?.failure ?? .unavailable) }
        await app.refreshCloudGames()
        guard !Task.isCancelled else { return .cancelled }
        if let failure = cloud.checkFailure ?? cloud.connectionCheck?.failure ?? cloud.referenceCheck?.failure { return stale(failure) }
        return .read
    }

    private func stale(_ failure: CloudLibraryFailure) -> LibraryRefresh.State {
        cloudFailure = failure
        let shown = app.cloudLibrary.lastCompleteCheck.map {
            L10n.format("The cloud games shown are those of %@.",
                        [$0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: L10n.context.formatLocale))])
        }
        return .stale([failure.message(), shown].compactMap { $0 }.joined(separator: " "))
    }

    // MARK: - Words

    static func title(_ refresh: LibraryRefresh, context: AppLocale = L10n.context) -> String {
        switch refresh.outcome {
        case .running: return L10n.text("In progress", context: context)
        case .upToDate, .changed: return L10n.text("Library up to date", context: context)
        case .incomplete: return L10n.text("Partly refreshed", context: context)
        case .cancelled: return L10n.text("Cancelled", context: context)
        }
    }

    /// What changed, what is still read, or what failed and why.
    static func detail(_ refresh: LibraryRefresh, context: AppLocale = L10n.context) -> String? {
        switch refresh.outcome {
        case .running: return refresh.reading.map { L10n.text($0.titleKey, context: context) }.joined(separator: " · ")
        case .changed(let count): return L10n.count("%lld new games", count, context: context)
        case .incomplete where refresh.stale.count == 1 && refresh.stale[0].part == .cloud:
            return refresh.stale[0].reason // It names Google Drive already.
        case .incomplete:
            return refresh.stale.map { "\(L10n.text($0.part.titleKey, context: context)) · \($0.reason)" }.joined(separator: "\n")
        case .upToDate, .cancelled: return nil
        }
    }
}
