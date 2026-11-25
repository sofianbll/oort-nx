import Foundation
import Observation
import OortCore
import ShellHost
import SwiftUI
import UserNotifications

/// The optional cloud library: off until the player turns it on, and nothing is opened before that.
@MainActor @Observable public final class CloudModel {
    enum Stage: Equatable { case off, code, signIn, ready }

    private(set) var stage = Stage.off
    private(set) var listing: ShelfListing?
    private(set) var problem: ShelfError?
    private(set) var looking = false
    private(set) var jobs: [ShelfJob] = []
    private(set) var installed: [String: (digest: String, version: String)] = [:]
    private(set) var installing: String?
    private(set) var network = CloudNetwork.State.free
    private(set) var inFlight: Int64 = 0
    private(set) var message: String?

    let module: CloudModule
    @ObservationIgnored private let settings: CloudSettings
    @ObservationIgnored private var link: CloudLink?
    @ObservationIgnored private var queue: ShelfQueue
    @ObservationIgnored private var running: (id: String, task: Task<Void, Never>)?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var watch: CloudNetwork?
    @ObservationIgnored private let frameworks: URL
    @ObservationIgnored private let games: URL
    @ObservationIgnored private let check: @Sendable (URL) -> String?
    /// The library reads its folders again.
    @ObservationIgnored var reload: () -> Void = {}

    public init(module: CloudModule, settings: CloudSettings, frameworks: URL, games: URL, check: @escaping @Sendable (URL) -> String?) {
        (self.module, self.settings, self.frameworks, self.games, self.check) = (module, settings, frameworks, games, check)
        queue = ShelfQueue(file: module.root.appendingPathComponent("queue.json"), keepOutOfBackup: Self.exclude)
        refreshDevice()
        if isOn { open() }
    }

    // MARK: On and off

    private var connectors: ShelfConnectors { ShelfConnectors([link?.connector ?? module.outline], choices: settings) }
    private var id: String { module.outline.id }
    var isOn: Bool { connectors.isOn(id) }
    var hosts: [String] { module.outline.hosts }
    var wifiOnly: Bool {
        get { access(keyPath: \.stage); return settings.wifiOnly }
        set { settings.wifiOnly = newValue; message = nil; wake() }
    }

    func turnOn() {
        try? connectors.turnOn(id, granting: module.outline.permissions)
        open()
    }

    /// Nil: the code was taken. Otherwise what to say.
    func take(_ text: String) -> String? {
        // A keyboard may have curled the quotes.
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/[“”«»]/, with: "\"")
        switch module.read(code) {
        case .wrong: return Oort.text("This is not a code from Oort NX on your Mac.")
        case .otherDevice: return Oort.text("This code is for an Android device.")
        case .good: break
        }
        settings.code = code
        open()
        return nil
    }

    /// Another code: the sign-in it replaces is erased first.
    func changeCode() async {
        await stop()
        try? await link?.connector.forgetAll()
        (link, settings.code, listing, problem) = (nil, nil, nil, nil)
        open()
    }

    func turnOff(deleting: Bool) async {
        await stop()
        await link?.abandon()
        try? await connectors.turnOff(id)
        settings.forget()
        queue.removeAll()
        watch?.stop()
        (link, watch, listing, problem, message) = (nil, nil, nil, nil, nil)
        if deleting { for title in titlesOnDevice() { installer.discard(title) } }
        jobs = []
        stage = .off
    }

    private func stop() async {
        retry?.cancel()
        let old = running
        running = nil
        old?.task.cancel()
        await old?.task.value
    }

    private func open() {
        guard isOn else { stage = .off; return }
        guard let code = settings.code else { stage = .code; return }
        if link == nil {
            link = module.link(code, settings) { [weak self] bytes in Task { @MainActor in self?.moved(bytes) } }
            guard link != nil else { settings.code = nil; stage = .code; return }
            let watch = module.network()
            self.watch = watch
            network = watch.now
            watch.start { [weak self] in Task { @MainActor in self?.networkChanged() } }
        }
        refreshDevice()
        stage = link!.isSignedIn() ? .ready : .signIn
        if stage == .ready { pump() }
    }

    /// The system finished something for the app while it was away.
    public func reconnect(_ done: @escaping @Sendable () -> Void) {
        guard let link else { return done() }
        link.reconnect(done)
        pump()
    }

    // MARK: Sign-in

    func signIn(_ browse: (URL, String) async throws -> URL) async {
        guard let link else { return }
        problem = nil
        let attempt = link.signIn()
        do {
            try await attempt.finish(try await browse(attempt.page, attempt.scheme))
            message = nil
            stage = .ready
            await look()
            pump()
        } catch let error as ShelfError { problem = error } catch { problem = nil }
    }

    // MARK: Listing

    func look() async {
        guard stage == .ready, let link, !looking else { return }
        looking = true
        defer { looking = false }
        refreshDevice()
        do {
            let source = try await connectors.source(id)
            let catalog = ShelfCatalog(source: source, crypto: link.crypto, scratch: scratch)
            listing = try await catalog.list(for: module.device, installed: installed.mapValues(\.digest))
            problem = nil
        } catch let error as ShelfError {
            problem = error
            if error == .signInNeeded { stage = .signIn }
        } catch { problem = .interrupted }
    }

    // MARK: Games

    struct Game: Identifiable, Equatable {
        let build: ShelfBuild
        let installedVersion: String?
        let isInstalled: Bool
        let job: ShelfJob?
        let isDownloaded: Bool
        var id: String { build.titleID }
    }

    var cloudGames: [Game] {
        let listed = listing?.games.map(\.build) ?? []
        let queued = jobs.map(\.build).filter { build in !listed.contains { $0.titleID == build.titleID } }
        return (listed + queued).map(game)
    }

    func game(_ id: String) -> Game? { cloudGames.first { $0.id == id } }

    private func game(_ build: ShelfBuild) -> Game {
        let here = installed[build.titleID], job = jobs.first { $0.id == build.titleID }
        return Game(build: job?.build ?? build, installedVersion: here?.version, isInstalled: here?.digest == (job?.build ?? build).digest, job: job,
                    isDownloaded: installer.isDownloaded(job?.build ?? build))
    }

    var freeSpace: Int64? { module.freeSpace(module.root) }
    var used: Int64 { installer.waitingBytes() }
    /// Bytes of a job, with those of the range under way.
    func received(_ job: ShelfJob) -> Int64 { min(job.received + (job.state == .running ? inFlight : 0), job.build.bytes) }

    func download(_ build: ShelfBuild) {
        queue.add(build)
        askForNotices()
        pump()
    }

    func pause(_ id: String) {
        queue.set(id, .paused)
        if running?.id == id { running?.task.cancel() }
        publish()
    }

    func resume(_ id: String) {
        queue.set(id, .waiting)
        pump()
    }

    /// Only what this download kept goes.
    func cancel(_ id: String) async {
        let job = queue[id]
        queue.remove(id)
        if running?.id == id { let task = running?.task; task?.cancel(); await task?.value }
        if job != nil { installer.discard(id) }
        refreshDevice()
        pump()
    }

    func install(_ id: String) async {
        guard let game = game(id), installing == nil else { return }
        let installer = installer
        installing = id
        message = nil
        let build = game.build, free = module.freeSpace
        let outcome = await Task.detached { Result { try installer.install(build, freeSpace: free) } }.value
        installing = nil
        switch outcome {
        case .success:
            queue.remove(id)
            refreshDevice()
            reload()
        case .failure(let error as ShelfError):
            queue.set(id, .failed, reason: error)
            // What was read is not what was signed: it is asked for again.
            if [.wrongDigest, .filesMissing].contains(error) { installer.discard(id) }
            publish()
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    /// After the library removed a game: its receipt, never its saves.
    func removed(_ id: String) {
        guard installed[id] != nil else { return }
        installer.forget(id)
        queue.remove(id)
        refreshDevice()
    }

    // MARK: The queue

    private func pump() {
        guard stage == .ready, running == nil, let job = queue.next else { return publish() }
        queue.set(job.id, .running)
        inFlight = 0
        publish()
        let store = store, module = module, connectors = connectors, id = id, network = watch, settings = settings
        running = (job.id, Task { [weak self] in
            var stopped: ShelfError?, cancelled = false
            do {
                let source = try await connectors.source(id)
                let download = ShelfDownload(source: source, store: store, rules: .init(allowsMeteredNetwork: !settings.wifiOnly, chunk: module.chunk),
                                             isMetered: { network?.now == .metered })
                if network?.now == CloudNetwork.State.none { throw ShelfError.offline }
                try await download.run(job.build) { progress in Task { @MainActor in self?.progressed(job.id, progress) } }
            } catch let error as ShelfError { stopped = error } catch { cancelled = true }
            self?.ended(job, stopped, cancelled: cancelled)
        })
    }

    private func ended(_ job: ShelfJob, _ error: ShelfError?, cancelled: Bool) {
        let mine = running?.id == job.id
        if mine { running = nil }
        inFlight = 0
        // Paused or taken away meanwhile: the player's word stays.
        if queue[job.id]?.state == .running {
            if let error {
                queue.set(job.id, error.waits ? .waiting : .failed, reason: error)
                if error == .signInNeeded { stage = .signIn; queue.set(job.id, .waiting, reason: error) }
                if error.waits { later(); publish(); return }
            } else if cancelled {
                queue.set(job.id, .waiting)
                publish()
                return
            } else {
                queue.progress(job.id, job.build.bytes)
                queue.set(job.id, .ready)
                tell(job.build.name)
            }
        }
        refreshDevice()
        if mine { pump() }
    }

    /// A wait, not a failure: again when the connection changes, or in half a minute.
    private func later() {
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.pump()
        }
    }

    func wake() {
        retry?.cancel()
        pump()
    }

    private func networkChanged() {
        network = watch?.now ?? .free
        if network != .none { wake() }
    }

    private func progressed(_ id: String, _ progress: ShelfProgress) {
        queue.progress(id, progress.received)
        inFlight = 0
        publish()
    }

    private func moved(_ bytes: Int64) { inFlight = bytes }

    private func publish() { jobs = queue.jobs }

    // MARK: This device

    private var scratch: URL { module.root.appendingPathComponent("scratch", isDirectory: true) }

    private var store: ShelfStore {
        let free = module.freeSpace
        return ShelfStore(root: module.root.appendingPathComponent("builds", isDirectory: true), crypto: module.hashing, available: { free($0) }, keepOutOfBackup: Self.exclude)
    }

    private var installer: CloudInstall { CloudInstall(store: store, crypto: module.hashing, frameworks: frameworks, games: games, check: check) }

    func refreshDevice() {
        let installer = installer
        installed = installer.installed()
        // A build that is gone from the device is no longer ready.
        for job in queue.jobs where job.state == .ready && !installer.isDownloaded(job.build) { queue.remove(job.id) }
        publish()
    }

    private func titlesOnDevice() -> [String] {
        let root = module.root.appendingPathComponent("builds")
        let incoming = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".incoming").path)) ?? []
        return Array(Set(((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter(ShelfNames.isTitleID)
            + incoming.map { String($0.prefix(16)) }.filter(ShelfNames.isTitleID)))
    }

    nonisolated static func exclude(_ url: URL) throws {
        var url = url, values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    // MARK: Notices

    private func askForNotices() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func tell(_ name: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = Oort.text("Downloaded. Ready to install.")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
