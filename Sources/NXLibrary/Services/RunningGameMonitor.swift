import AppKit
import Combine
import NXLibraryCore
import ArcanePorting

/// Which library games are running, and Resume and Close Game for them. The running set is
/// read from the system's process list (`RunningAppsTracker`) whenever it may have changed: on
/// launch and terminate notifications, on changes to `NSWorkspace.runningApplications`, and when
/// Arcane comes forward. Notifications alone miss a game whose launcher quits from its settings
/// window (it becomes a background process before it exits). A game that stops ends its play session, and when it
/// quit in front with no other library game open, Arcane comes back to the front (`GameFocus`).
@MainActor
final class RunningGameMonitor: ObservableObject {
    /// Time a game gets to quit after Close Game, in nanoseconds (5 s) before it is force-quit.
    static let forceQuitDelay: UInt64 = 5_000_000_000

    @Published private(set) var runningGameIDs: Set<UUID> = []
    /// The latest play session a game's quit ended, for the session card (nil when it was too short for one).
    @Published private(set) var endedSession: SessionSummary?
    @Published private(set) var pausedGameIDs: Set<UUID> = []

    @MainActor private final class HomeMenuWatch {
        let app: NSRunningApplication
        var lookup: Task<Void, Never>?
        var quit: Task<Void, Never>?
        var host: HomeMenu.Host?
        var session: HomeMenu.Session?
        var notifications: [NSObjectProtocol] = []
        var exit: DispatchSourceProcess?
        var attributedExit: (() -> Void)?

        init(app: NSRunningApplication) { self.app = app }

        deinit {
            lookup?.cancel()
            quit?.cancel()
            exit?.cancel()
            for token in notifications { DistributedNotificationCenter.default().removeObserver(token) }
        }
    }

    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []
    private var sessions: PlaySessionStore?
    private var tracker: RunningAppsTracker?
    private var processListObservation: NSKeyValueObservation?
    private var activeToken: NSObjectProtocol?
    private var games: [PortedGame] = []
    private var closeTasks: [String: Task<Void, Never>] = [:]
    private var focus = GameFocus()
    private var focusToken: NSObjectProtocol?
    private var homeMenus: [UUID: HomeMenuWatch] = [:]
    private var engineFolder: () -> String = { "" }

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.center = center
    }

    /// Seeds the running set from the workspace, ends stale play sessions once, then follows launches and quits.
    func start(sessions: PlaySessionStore, engineFolder: @escaping () -> String) {
        guard tokens.isEmpty else { return }
        self.sessions = sessions
        self.engineFolder = engineFolder
        let tracker = RunningAppsTracker(snapshot: Self.runningBundleIDs)
        self.tracker = tracker
        sessions.reconcile(runningBundleIDs: tracker.running)
        recompute()
        tokens = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map {
            center.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        focusToken = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor in self?.activated(bundleID) }
        }
        activeToken = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        processListObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        for token in tokens { center.removeObserver(token) }
        tokens = []
        if let focusToken { center.removeObserver(focusToken) }
        focusToken = nil
        if let activeToken { NotificationCenter.default.removeObserver(activeToken) }
        activeToken = nil
        processListObservation?.invalidate()
        processListObservation = nil
        for task in closeTasks.values { task.cancel() }
        closeTasks = [:]
        homeMenus.removeAll()
        pausedGameIDs = []
    }

    /// The library changed: new and removed games are matched again.
    func setGames(_ games: [PortedGame]) {
        self.games = games
        recompute()
    }

    func isRunning(_ game: PortedGame) -> Bool {
        runningGameIDs.contains(game.id)
    }

    func isRunningForProfileSwitch(_ game: PortedGame) -> Bool {
        homeMenus[game.id]?.host?.isAlive == true || Self.runningApplication(for: game) != nil
    }

    /// Brings a running game's app forward, resuming its host if paused. Never starts a second copy.
    func resume(_ game: PortedGame, application: NSRunningApplication? = nil) {
        if let watch = homeMenus[game.id], application == nil || watch.app == application,
           let host = watch.host, host.isAlive {
            if watch.session?.phase == .quitting { return }
            let app = NSRunningApplication(processIdentifier: host.pid)
            // A restarted Arcane does not receive the old pause notification; the engine hides its host.
            if let request = watch.session?.resumeRequest(hostIsHidden: app?.isHidden == true) {
                if #available(macOS 14, *), let bundleID = game.effectiveBundleId {
                    NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
                }
                Self.postHomeMenu(request)
                Self.activate(app ?? watch.app)
                return
            }
        }
        guard let app = application ?? Self.runningApplication(for: game) else { return }
        Self.activate(app)
    }

    /// Asks the game to quit; after 5 s it is force-quit if it is still running.
    /// The caller asks the player first (Close Game confirmation).
    func close(_ game: PortedGame, forceIfUnresponsive: Bool = true) {
        if pausedGameIDs.contains(game.id) {
            quitPaused(game.id, forceIfUnresponsive: forceIfUnresponsive)
            return
        }
        guard let bundleID = game.effectiveBundleId,
              let app = Self.runningApplication(for: game) else {
            // Nothing to close: the game ended without being noticed. Read the process list again.
            refresh()
            return
        }
        app.terminate()
        guard forceIfUnresponsive else { return }
        closeTasks[bundleID]?.cancel()
        // The instance we asked to quit, not a fresh lookup: a relaunch within the delay must not be force-quit.
        closeTasks[bundleID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.forceQuitDelay)
            guard !Task.isCancelled else { return }
            if !app.isTerminated { app.forceTerminate() }
            self?.closeTasks[bundleID] = nil
        }
    }

    /// The live process of a game, if one is running.
    nonisolated static func runningApplication(for game: PortedGame) -> NSRunningApplication? {
        guard let bundleID = game.effectiveBundleId else { return nil }
        return runningApplication(bundleID: bundleID)
    }

    nonisolated static func runningApplication(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    /// Activates an app with cooperative activation.
    nonisolated static func activate(_ app: NSRunningApplication) {
        app.activate()
    }

    // MARK: - Notifications

    /// Every live process's bundle ID, background ones included.
    nonisolated private static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
    }

    /// Reads the process list again; a game no longer in it ends its play session and any pending force-quit.
    func refresh() {
        guard let tracker else { return }
        let ended = tracker.refresh().ended
        var comesForward = false
        for bundleID in ended {
            let others = libraryBundleIDs.intersection(tracker.running).subtracting(ended)
            let othersRunning = !others.isEmpty || SteamPlayCoordinator.shared.hasRunningGame
            if focus.gameEnded(bundleID, othersRunning: othersRunning) { comesForward = true }
            let survivingHosts = Set(homeMenus.compactMap { id, watch in watch.host?.isAlive == true ? id : nil })
            for session in sessions?.end(bundleID: bundleID, preserving: survivingHosts) ?? [] {
                if let game = games.first(where: { $0.id == session.gameID }) {
                    showEnded(session, game: game, store: sessions)
                }
            }
            closeTasks[bundleID]?.cancel()
            closeTasks[bundleID] = nil
        }
        recompute()
        if comesForward { comeForward() }
    }

    func endAttributedPlay(_ game: PortedGame, pid: pid_t, date: Date?,
                           store: PlaySessionStore?, onExit: @escaping () -> Void) {
        let finish = { [weak self] in
            for session in store?.end(gameID: game.id) ?? [] { self?.showEnded(session, game: game, store: store) }
            onExit()
        }
        if let watch = homeMenus[game.id], watch.app.processIdentifier == pid,
           watch.app.launchDate == date, watch.host?.isAlive == true {
            watch.attributedExit = finish
        } else {
            finish()
        }
    }

    private func showEnded(_ session: PlaySession, game: PortedGame, store: PlaySessionStore?) {
        if let summary = SessionSummary(session: session, game: game, total: store?.totalDuration(for: game.id) ?? 0) {
            endedSession = summary
        }
    }

    private var libraryBundleIDs: Set<String> { Set(games.compactMap(\.effectiveBundleId)) }

    /// The app is one of the library's nxnative games.
    func isLibraryGame(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier.map(libraryBundleIDs.contains) == true
    }

    /// A library game in front is noted; another app that is still in front a second later, while that game runs,
    /// means the player left the game (an app macOS brings forward as a game quits does not count).
    private func activated(_ bundleID: String?) {
        if let bundleID, libraryBundleIDs.contains(bundleID) {
            focus.gameCameForward(bundleID)
            return
        }
        guard let game = focus.gameInFront else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, Self.runningApplication(bundleID: game) != nil,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier != game else { return }
            self.focus.otherAppStayedForward(whileRunning: game)
        }
    }

    /// Arcane back in front after the game in front quit (`LibraryWindow`), never over a library game.
    private func comeForward() {
        LibraryWindow.comeForward { [weak self] app in
            self?.isLibraryGame(app) == true
                || SteamPlayCoordinator.shared.isRunningGame(pid: app.processIdentifier)
        }
    }

    private func recompute() {
        let ids = RunningGames.matchingIDs(in: games, runningBundleIDs: tracker?.running ?? [])
        if ids != runningGameIDs { runningGameIDs = ids }
        reconcileHomeMenus(ids)
    }

    // MARK: - Engine Home menu

    private func reconcileHomeMenus(_ ids: Set<UUID>) {
        for (id, watch) in homeMenus where !ids.contains(id) || watch.app.isTerminated {
            // LaunchServices can register the host instead of the wrapper when its window appears.
            if watch.host?.isAlive == true { continue }
            stopHomeMenu(id)
        }
        for game in games where ids.contains(game.id) && homeMenus[game.id] == nil {
            guard let app = NativePlayTarget(game.url)?.running().first,
                  let url = app.bundleURL else { continue }
            let watch = HomeMenuWatch(app: app)
            homeMenus[game.id] = watch
            let id = game.id
            let pid = app.processIdentifier
            watch.lookup = Task { [weak self, weak watch] in
                guard let folder = self?.engineFolder(),
                      await InstalledEngineCapabilities.shared.supportsHomeMenu(in: url, engineFolder: folder) else { return }
                let executable = HomeMenu.hostExecutable(in: url)
                // The launcher may take a while to start its child (first launch / external disk).
                for attempt in 0..<140 {
                    guard !Task.isCancelled, let self, let watch, self.homeMenus[id] === watch,
                          !watch.app.isTerminated else { return }
                    if let host = HomeMenu.Host.find(appPID: pid, executable: executable) {
                        self.observeHomeMenu(host, for: id, watch: watch)
                        return
                    }
                    try? await Task.sleep(nanoseconds: attempt < 20 ? 250_000_000 : 1_000_000_000)
                }
            }
        }
    }

    private func observeHomeMenu(_ host: HomeMenu.Host, for id: UUID, watch: HomeMenuWatch) {
        watch.host = host
        watch.session = .init(pid: host.pid)
        let source = DispatchSource.makeProcessSource(identifier: host.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self, weak watch] in
            guard let self, let watch, self.homeMenus[id] === watch else { return }
            self.stopHomeMenu(id)
        }
        watch.exit = source
        source.resume()

        let events: [(String, HomeMenu.Session.Event)] = [("paused", .paused), ("resumed", .resumed)]
        watch.notifications = events.map { name, event in
            let notification = Notification.Name(HomeMenu.notification(name, pid: host.pid))
            return DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) {
                [weak self, weak watch] _ in
                MainActor.assumeIsolated {
                    guard let self, let watch, self.homeMenus[id] === watch, host.isAlive else { return }
                    watch.session?.receive(event, from: host.pid)
                    if watch.session?.phase == .paused, !self.pausedGameIDs.contains(id) {
                        self.pausedGameIDs.insert(id)
                        self.comeForward()
                    } else if watch.session?.phase == .running {
                        if self.pausedGameIDs.contains(id) { self.pausedGameIDs.remove(id) }
                        watch.quit?.cancel()
                    }
                }
            }
        }
        if !host.isAlive { stopHomeMenu(id) }
    }

    private func quitPaused(_ id: UUID, forceIfUnresponsive: Bool) {
        guard let watch = homeMenus[id], let host = watch.host, host.isAlive else {
            stopHomeMenu(id)
            return
        }
        guard let request = watch.session?.requestQuit() else { return }
        Self.postHomeMenu(request)
        watch.quit?.cancel()
        watch.quit = Task { [weak self, weak watch] in
            try? await Task.sleep(nanoseconds: Self.forceQuitDelay)
            guard !Task.isCancelled, let self, let watch, self.homeMenus[id] === watch,
                  watch.session?.phase == .quitting else { return }
            guard host.isAlive else { self.stopHomeMenu(id); return }
            if forceIfUnresponsive { host.terminate() }
            watch.session?.quitTimedOut()
        }
    }

    private func stopHomeMenu(_ id: UUID) {
        if let watch = homeMenus.removeValue(forKey: id), let host = watch.host {
            watch.session?.receive(.exited, from: host.pid)
            watch.attributedExit?()
        }
        if pausedGameIDs.contains(id) { pausedGameIDs.remove(id) }
    }

    private static func postHomeMenu(_ name: String) {
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(name), object: nil,
                                                                       userInfo: nil, deliverImmediately: true)
    }
}
