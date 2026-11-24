import Foundation
import AppKit
import NXLibraryCore

public protocol AppLaunching {
    func open(_ url: URL, environment: [String: String], onExit: (() -> Void)?,
              completion: @escaping (Bool, String?) -> Void)
}

public final class NSWorkspaceLauncher: AppLaunching {
    public init() {}

    public func open(_ url: URL, environment: [String: String], onExit: (() -> Void)?,
                     completion: @escaping (Bool, String?) -> Void) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            completion(false, "The app bundle is missing: \(url.path)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment = Self.gameEnvironment(inheriting: ProcessInfo.processInfo.environment, explicit: environment)
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

    static func gameEnvironment(inheriting ambient: [String: String], explicit: [String: String]) -> [String: String] {
        // nxnative reads HOME and uses osascript via posix_spawnp; use only macOS system tools.
        var system = ["HOME": ambient["HOME"].flatMap { $0.isEmpty ? nil : $0 }
                        ?? FileManager.default.homeDirectoryForCurrentUser.path,
                      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        system["TMPDIR"] = ambient["TMPDIR"].flatMap { $0.isEmpty ? nil : $0 } ?? NSTemporaryDirectory()
        return system.merging(explicit) { _, value in value }
    }

    private static func watchExit(of app: NSRunningApplication, onExit: @escaping () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        var observer: NSObjectProtocol?
        func finish() {
            guard let token = observer else { return }
            observer = nil
            center.removeObserver(token)
            onExit()
        }
        observer = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                      object: nil, queue: .main) { note in
            guard let ended = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  ended == app else { return }
            finish()
        }
        // The process can exit before the open completion or observer registration.
        if app.isTerminated { finish() }
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
                       onExit: (() -> Void)? = nil,
                       completion: @escaping (Bool, String?) -> Void) {
        launch(appURL: appURL, environment: environment, homeButton: homeButton, overlay: overlay, snapshot: snapshot,
               temporaryDirectory: FileManager.default.temporaryDirectory, onExit: onExit, completion: completion)
    }

    func launch(appURL: URL, environment: [String: String] = [:],
                homeButton: InGameHomeButton = .auto,
                overlay: GameOverlayLaunch?, snapshot: GameOverlaySnapshot?, temporaryDirectory: URL,
                onExit: (() -> Void)? = nil,
                completion: @escaping (Bool, String?) -> Void) {
        var values = environment.merging(Self.launchEnvironment) { _, fixed in fixed }
        values[GameOverlayLaunch.dataKey] = nil
        values[Self.overlayHomeSwapKey] = switch homeButton {
        case .auto: nil
        case .fullOverlay: "0"
        case .quickAccess: "1"
        }
        var cleanup: (() -> Void)?
        if let overlay, let snapshot, let file = try? overlay.writeSnapshot(snapshot, in: temporaryDirectory) {
            values[GameOverlayLaunch.dataKey] = file.path
            cleanup = { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        }
        let afterExit: (() -> Void)? = (cleanup == nil && onExit == nil) ? nil : {
            cleanup?()
            onExit?()
        }
        launcher.open(appURL, environment: values, onExit: afterExit) { success, error in
            if !success { cleanup?() }
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
