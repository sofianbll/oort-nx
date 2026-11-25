import Foundation
import AppKit
import NXLibraryCore

public protocol AppLaunching {
    func open(_ url: URL, environment: [String: String], suppressInheritedPlayerMode: Bool,
              onExit: (@Sendable () -> Void)?, completion: @escaping @Sendable (Bool, String?) -> Void)
}

public final class NSWorkspaceLauncher: AppLaunching {
    public init() {}

    public func open(_ url: URL, environment: [String: String], suppressInheritedPlayerMode: Bool,
                     onExit: (@Sendable () -> Void)?, completion: @escaping @Sendable (Bool, String?) -> Void) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            completion(false, L10n.format("The app bundle is missing: %@", [url.path]))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment = Self.gameEnvironment(inheriting: ProcessInfo.processInfo.environment, explicit: environment,
                                                          suppressInheritedPlayerMode: suppressInheritedPlayerMode)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            if let error {
                completion(false, error.localizedDescription)
            } else if let app {
                completion(true, nil)
                if let onExit {
                    DispatchQueue.main.async {
                        Self.watchExit(of: app, onExit: onExit)
                    }
                }
            } else {
                completion(false, nil)
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

        func finish(_ onExit: () -> Void) {
            guard let token = observer else { return }
            observer = nil
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
    static let overlayHomeSwapKey = "DM_OVERLAY_HOME_SWAP"

    public func launch(appURL: URL, environment: [String: String] = [:],
                       homeButton: InGameHomeButton = .auto,
                       overlay: GameOverlayLaunch? = nil, snapshot: GameOverlaySnapshot? = nil,
                       players: PlayersLaunch? = nil, onExit: (@Sendable () -> Void)? = nil,
                       completion: @escaping @Sendable (Bool, String?) -> Void) {
        launch(appURL: appURL, environment: environment, homeButton: homeButton, overlay: overlay, snapshot: snapshot,
               temporaryDirectory: FileManager.default.temporaryDirectory, players: players, onExit: onExit, completion: completion)
    }

    func launch(appURL: URL, environment: [String: String] = [:],
                homeButton: InGameHomeButton = .auto,
                overlay: GameOverlayLaunch?, snapshot: GameOverlaySnapshot?, temporaryDirectory: URL,
                players: PlayersLaunch? = nil, onExit: (@Sendable () -> Void)? = nil,
                completion: @escaping @Sendable (Bool, String?) -> Void) {
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
                      onExit: afterExit) { success, error in
            if !success { cleanup?(); portraits?.clean() }
            completion(success, error)
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
