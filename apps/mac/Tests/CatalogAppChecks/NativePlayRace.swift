import AppKit
import ObjectiveC
@testable import OortMac
import OortLibrary
import NxnativeAdapter

private let env = ProcessInfo.processInfo.environment
private let root = URL(fileURLWithPath: env["OORT_PLAY_FIXTURE_DIR"]!, isDirectory: true)
private let target = root.appendingPathComponent("Fixture.app").resolvingSymlinksInPath()
private let bundleID = env["OORT_PLAY_FIXTURE_ID"]!

extension NSWorkspace {
    @objc dynamic func raceOpen(at url: URL, configuration: OpenConfiguration,
                                completionHandler: ((NSRunningApplication?, Error?) -> Void)?) {
        precondition(url.resolvingSymlinksInPath().path == target.path && !configuration.allowsRunningApplicationSubstitution)
        let external = OpenConfiguration()
        external.activates = false
        external.addsToRecentItems = false
        external.allowsRunningApplicationSubstitution = false
        // The outside app appears after Oort's last snapshot and before its native handoff.
        raceOpen(at: url, configuration: external) { outside, failure in
            precondition(outside != nil && failure == nil)
            configuration.addsToRecentItems = false
            self.raceOpen(at: url, configuration: configuration) { returned, error in
                precondition(returned == outside && error == nil, "LaunchServices reused the outside instance")
                completionHandler?(returned, error)
            }
        }
    }
}

@main struct NativePlayRace {
    @MainActor static func main() async throws {
        assertFixtureHome()
        suppressProbeNotifications()
        precondition(bundleID.hasPrefix("io.example.oort.playproof."))
        func live() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath().path == target.path }
        }
        defer { live().forEach { $0.forceTerminate() } }
        method_exchangeImplementations(class_getInstanceMethod(NSWorkspace.self,
            #selector(NSWorkspace.openApplication(at:configuration:completionHandler:)))!,
            class_getInstanceMethod(NSWorkspace.self,
            #selector(NSWorkspace.raceOpen(at:configuration:completionHandler:)))!)
        let settings = AppSettingsStore()
        settings.settings.refreshLibraryAtLaunch = false
        settings.settings.checkEngineAtLaunch = false
        var game = PortedGame(name: "Fixture", url: target, platform: .macApp, sizeBytes: 0,
                              modificationDate: .now, bundleId: bundleID, titleId: "010000000000D999")
        game.status = .built
        let entry = CatalogGame(nxnative: game)
        let model = AppViewModel(settingsStore: settings, catalog: .init(games: [entry]),
                                 repository: .init(store: .init(directory: AppData.supportRoot)), registerNotifications: false)
        let history = PlaySessionStore()
        model.playSessionStore = history
        var result: PlayResult?
        precondition(model.play(entry) { if case .result(let answer) = $0 { result = answer } } == .accepted(.pending))
        let deadline = ContinuousClock.now + .seconds(8)
        let started = root.appendingPathComponent("started")
        while (result == nil || !FileManager.default.fileExists(atPath: started.path)), .now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let apps = live()
        precondition(apps.count == 1 && result == .accepted(.gameOpened))
        let sample = try String(contentsOf: started, encoding: .utf8)
        precondition(sample == "\(apps[0].processIdentifier) 0")
        precondition(history.sessions.isEmpty && history.totalDuration(for: entry.id) == 0)
        print("Exact native Play joined one external process; no windows, recorded sessions, or duration.")
    }
}
