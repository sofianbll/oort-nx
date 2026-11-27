import Foundation
import AppKit
import NXLibraryCore

public protocol AppLaunching {
    func open(_ url: URL, environment: [String: String], suppressInheritedPlayerMode: Bool,
              begin: Date, expectedArtifact: String?, onExit: (@Sendable () -> Void)?,
              completion: @escaping @Sendable (AppOpenResult) -> Void)
}

public enum AppOpenResult: Sendable {
    case started(NSRunningApplication)
    case joined(NSRunningApplication)
    case failed(String?)
    // A deliberate injected transport may accept a handoff without claiming a native start.
    case handedOff

    public var accepted: Bool {
        if case .failed = self { return false }
        return true
    }

    public var error: String? {
        if case .failed(let description) = self { return description }
        return nil
    }
}

public final class NSWorkspaceLauncher: AppLaunching {
    public init() {}

    public func open(_ url: URL, environment: [String: String], suppressInheritedPlayerMode: Bool,
                     begin: Date, expectedArtifact: String?, onExit: (@Sendable () -> Void)?,
                     completion: @escaping @Sendable (AppOpenResult) -> Void) {
        guard let target = NativePlayTarget(url) else {
            completion(.failed(L10n.format("The app bundle is missing: %@", [url.path])))
            return
        }
        let configuration = NativePlayTarget.openConfiguration()
        configuration.environment = Self.gameEnvironment(inheriting: ProcessInfo.processInfo.environment, explicit: environment,
                                                           suppressInheritedPlayerMode: suppressInheritedPlayerMode)
        let origin = UUID().uuidString
        configuration.environment[NativePlayTarget.originKey] = origin
        let proof = PlayAttribution(startedAt: begin, before: Set(target.running().map(\.processIdentifier)))
        guard expectedArtifact == nil || expectedArtifact == NativePlayTarget(target.url)?.artifact else {
            completion(.failed(nil))
            return
        }
        NSWorkspace.shared.openApplication(at: target.url, configuration: configuration) { app, error in
            if let error {
                completion(.failed(error.localizedDescription))
            } else if let app, target.matches(app) {
                let after = Set(target.running().map(\.processIdentifier))
                let pid = app.processIdentifier
                let candidate = proof.accepts(pid: pid, born: app.launchDate, after: after, belongsToGesture: true)
                let attributed = candidate && NativePlayTarget.receivedOrigin(origin, pid: pid) && !app.isTerminated
                completion(attributed ? .started(app) : .joined(app))
                if attributed, let onExit {
                    DispatchQueue.main.async {
                        Self.watchExit(of: app, onExit: onExit)
                    }
                }
            } else {
                completion(.failed(nil))
            }
        }
    }

    private static let inheritedKeys: Set<String> = [
        "LANG", "LANGUAGE", "LC_ALL", "LC_COLLATE", "LC_CTYPE", "LC_MESSAGES", "LC_MONETARY", "LC_NUMERIC", "LC_TIME", "TZ",
        "MTL_HUD_ENABLED", "MTL_HUD_ELEMENTS", "MTL_HUD_ALIGNMENT", "MTL_HUD_SCALE", "MTL_HUD_OPACITY",
        "MTL_HUD_LOG_ENABLED", "MTL_HUD_ENCODER_TIMING_ENABLED", "MTL_HUD_LOG_SHADER_ENABLED",
        "MTL_HUD_INSIGHTS_ENABLED", "MTL_HUD_SHOW_METRICS_RANGE", "MTL_HUD_SHOW_ZERO_METRICS", "MTL_HUD_HIDE_METALFX_METRICS",
        "DM_HID_MAP", "DM_HID_PADS", "DM_PAD_IDENTICAL", "DM_PAD_MERGE", "DM_KBD_PLAYER", "DM_MOTION_HID",
        "DM_JC1", "DM_JC1_SIDE", "DM_SW2_MAP", "DM_SW2_MOTION", "DM_SW2_MOTION_SIDE",
        "SDL_GAMECONTROLLERCONFIG", "SDL_JOYSTICK_HIDAPI", "SDL_JOYSTICK_HIDAPI_SWITCH", "SDL_JOYSTICK_HIDAPI_JOY_CONS",
        "DM_NET_DISCOVERY_PEER", "DM_NETWORK_INTERFACE", "DM_NET_VPN", "NO_PROXY", "no_proxy",
        "DM_SAVE", "DM_SAVE_SYNC", "DM_TRPFD_MERGE",
    ]
    private static let proxyKeys: Set<String> = ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"]

    public static func inheritedGameEnvironment(
        _ ambient: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        // Keep host defaults separate from the game's saved choices and per-session data.
        var system = ambient.filter { key, value in
            if inheritedKeys.contains(key) { return true }
            guard proxyKeys.contains(key) else { return false }
            if value.isEmpty { return true }
            let url = value.contains("://") ? value : "http://" + value
            guard let proxy = URLComponents(string: url), proxy.host?.isEmpty == false else { return false }
            return proxy.user == nil && proxy.password == nil
        }
        // nxnative reads HOME and uses osascript via posix_spawnp; use only macOS system tools.
        system["HOME"] = ambient["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? FileManager.default.homeDirectoryForCurrentUser.path
        system["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        system["TMPDIR"] = ambient["TMPDIR"].flatMap { $0.isEmpty ? nil : $0 } ?? NSTemporaryDirectory()
        return system
    }

    static func gameEnvironment(inheriting ambient: [String: String], explicit: [String: String],
                                suppressInheritedPlayerMode: Bool = false) -> [String: String] {
        let inherited = inheritedGameEnvironment(ambient)
        return (suppressInheritedPlayerMode ? inherited.filter { !PlayersLaunch.controllerKeys.contains($0.key) } : inherited)
            .merging(explicit) { _, value in value }
    }

    @MainActor private final class ExitWatch {
        var observer: NSObjectProtocol?
        var process: DispatchSourceProcess?

        func finish(_ onExit: () -> Void) {
            guard let token = observer else { return }
            observer = nil
            process?.cancel()
            process = nil
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            onExit()
        }
    }

    @MainActor private static func watchExit(of app: NSRunningApplication, onExit: @escaping @Sendable () -> Void) {
        let watch = ExitWatch()
        watch.observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            guard let ended = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  ended == app else { return }
            // `queue: .main` runs this block on the main thread.
            MainActor.assumeIsolated { watch.finish(onExit) }
        }
        // LaunchServices may not deliver the workspace event for an accessory
        // app or while the launch screen owns the main loop. Follow the exact PID.
        if !app.isTerminated {
            let source = DispatchSource.makeProcessSource(identifier: app.processIdentifier, eventMask: .exit, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { watch.finish(onExit) } }
            watch.process = source
            source.resume()
        }
        // The process can exit before the open completion or observer registration.
        if app.isTerminated { watch.finish(onExit) }
    }
}

public final class LaunchService {
    private let launcher: AppLaunching

    public init(launcher: AppLaunching = NSWorkspaceLauncher()) {
        self.launcher = launcher
    }

    public func writeEnvironment(
        settings: GameRuntimeConfig,
        titleId: String,
        baseDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/nxnative")
    ) throws {
        let dir = baseDirectory.appendingPathComponent(titleId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let envURL = dir.appendingPathComponent("env.txt")
        let existing = FileManager.default.fileExists(atPath: envURL.path)
            ? try String(contentsOf: envURL, encoding: .utf8) : nil
        try settings.mergedEnvContent(existing: existing).write(
            to: envURL, atomically: true, encoding: .utf8)
    }

    /// Set for every game Arcane starts: Game options are its settings window, so the engine's own
    /// (dm/mac/launcher.c: DM_LAUNCHER=0) does not show; the game takes Arcane's settings and starts.
    public static let launchEnvironment = ["DM_LAUNCHER": "0"]
    /// The game's own quit question, in the player's language (docs/frontends.md, DM_HOME_QUIT_TEXT): the hold, the
    /// title, the note, quit and cancel, then this fork's Resume and Return; the last line, the game's title, stays its own.
    public static let quitTextKey = "DM_HOME_QUIT_TEXT"
    public static func quitText(gameName: String) -> String {
        [L10n.text("Keep holding to quit"), L10n.format("Quit %@?", [gameName]), L10n.text("Unsaved progress will be lost."),
         L10n.text("Quit"), L10n.text("Cancel"), L10n.text("Resume"), L10n.format("Return to %@", [AppIdentity.displayName])]
            .map { $0.components(separatedBy: .newlines).joined(separator: " ") }
            .joined(separator: "\n")
    }
    static let overlayHomeSwapKey = "DM_OVERLAY_HOME_SWAP"

    package func launch(appURL: URL, environment: [String: String] = [:], beganAt: Date = .now,
                       expectedArtifact: String? = nil,
                       homeButton: InGameHomeButton = .auto,
                       overlay: GameOverlayLaunch? = nil, snapshot: GameOverlaySnapshot? = nil,
                       players: PlayersLaunch? = nil, onExit: (@Sendable () -> Void)? = nil,
                       completion: @escaping @Sendable (AppOpenResult) -> Void) {
        launch(appURL: appURL, environment: environment, beganAt: beganAt, expectedArtifact: expectedArtifact,
               homeButton: homeButton, overlay: overlay, snapshot: snapshot,
               temporaryDirectory: FileManager.default.temporaryDirectory, players: players, onExit: onExit, completion: completion)
    }

    func launch(appURL: URL, environment: [String: String] = [:], beganAt: Date = .now, expectedArtifact: String? = nil,
                homeButton: InGameHomeButton = .auto,
                overlay: GameOverlayLaunch?, snapshot: GameOverlaySnapshot?, temporaryDirectory: URL,
                players: PlayersLaunch? = nil, onExit: (@Sendable () -> Void)? = nil,
                completion: @escaping @Sendable (AppOpenResult) -> Void) {
        var values = environment.merging(players?.additions ?? [:]) { explicit, _ in explicit }
        values.merge(Self.launchEnvironment) { _, fixed in fixed }
        values[GameOverlayLaunch.dataKey] = nil
        values[Self.overlayHomeSwapKey] = switch homeButton {
        case .auto: nil
        case .fullOverlay: "0"
        case .quickAccess: "1"
        }
        let cleanup: (@Sendable () -> Void)?
        if let overlay, let snapshot, let file = try? overlay.writeSnapshot(snapshot, in: temporaryDirectory) {
            values[GameOverlayLaunch.dataKey] = file.path
            cleanup = { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        } else {
            cleanup = nil
        }
        let portraits = players?.portraitFiles
        let cleanThenReport: @Sendable () -> Void = {
            cleanup?()
            portraits?.clean()
            onExit?()
        }
        let afterExit = (cleanup == nil && portraits == nil && onExit == nil) ? nil : cleanThenReport
        launcher.open(appURL, environment: values, suppressInheritedPlayerMode: players?.status.plan == .active,
                      begin: beganAt, expectedArtifact: expectedArtifact, onExit: afterExit) { result in
            switch result {
            case .joined, .failed: cleanup?(); portraits?.clean()
            case .started, .handedOff: break
            }
            completion(result)
        }
    }

    public func saveDirectory(for titleId: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/nxnative")
            .appendingPathComponent(titleId).appendingPathComponent("save")
    }

    public func logURL(for titleId: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/nxnative")
            .appendingPathComponent("\(titleId).log")
    }
}
