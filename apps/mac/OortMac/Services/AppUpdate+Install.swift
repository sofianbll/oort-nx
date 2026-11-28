import Foundation
import OortLibrary

/// Installing an update of the Mac app itself: the sealed bundle and its signature, App Translocation, the atomic
/// swap over the running copy and the relaunch. A Mac-only effect; the releases it acts on are `AppUpdate` in the core.
extension AppUpdate {
    /// Validate the sealed bundle before it can replace the installed copy.
    public static func validCodeSignature(_ app: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", app.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.runWithExitWait()(); return process.terminationStatus == 0 }
        catch { return false }
    }

    /// "v1.2.3" or "v1.2.3-beta.1" → the version; nil when it is neither dotted numbers nor one of our pre-releases.
    public enum BundleProblem: Error, Equatable {
        case noInfo, wrongIdentifier, noExecutable, wrongVersion, notRelease
        case needsNewerMacOS(String)
    }

    fileprivate static func info(_ app: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// Whether `app` is Arcane `version` as a release copy that opens on `runningOS`.
    public static func bundleProblem(_ app: URL, expectedID: String, version: String,
                                     runningOS: OperatingSystemVersion) -> BundleProblem? {
        guard let info = info(app) else { return .noInfo }
        guard !expectedID.isEmpty, info["CFBundleIdentifier"] as? String == expectedID else { return .wrongIdentifier }
        guard let exe = info["CFBundleExecutable"] as? String, !exe.isEmpty, !exe.contains("/"),
              FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/" + exe).path)
        else { return .noExecutable }
        guard info["CFBundleShortVersionString"] as? String == version else { return .wrongVersion }
        guard info[releaseMarker] as? Bool == true, info["NXLibraryDevelopmentProfile"] as? Bool != true else { return .notRelease }
        if let text = info["LSMinimumSystemVersion"] as? String, let minimum = numbers(text) {
            let running = [runningOS.majorVersion, runningOS.minorVersion, runningOS.patchVersion]
            let padded = minimum + Array(repeating: 0, count: max(0, 3 - minimum.count))
            if running.lexicographicallyPrecedes(padded.prefix(3)) { return .needsNewerMacOS(text) }
        }
        return nil
    }


    public static func installability(_ bundle: URL) -> Installability {
        guard bundle.pathExtension == "app", let metadata = info(bundle), metadata[releaseMarker] as? Bool == true, metadata["NXLibraryDevelopmentProfile"] as? Bool != true else { return .developer }
        let standardized = bundle.standardizedFileURL
        if isTranslocated(standardized) { return .readOnly }
        if !FileManager.default.isWritableFile(atPath: standardized.deletingLastPathComponent().path) { return .readOnly }
        return .ok
    }

    /// True for the temporary read-only copy macOS runs when a downloaded app is opened where it was unpacked.
    public static func isTranslocated(_ bundle: URL) -> Bool {
        bundle.standardizedFileURL.path.contains("/AppTranslocation/")
    }

    /// A release copy that macOS runs as a temporary copy never updates itself, so at launch it asks to be moved.
    public static func asksToBeMoved(_ bundle: URL) -> Bool {
        isTranslocated(bundle) && installability(bundle) == .readOnly
    }

    // MARK: - The swap

    public enum InstallError: Error, Equatable { case failed(String) }

    /// Stages on the destination volume in an exclusively owned directory, then
    /// atomically exchanges the apps. A failed Trash operation retains the old app there.
    @discardableResult
    public static func install(_ staged: URL, over current: URL, trashOld: Bool = true) throws -> URL {
        try install(staged, over: current, trashOld: trashOld, fileManager: .default, io: BuildInstallIO())
    }

    static func install(_ staged: URL, over current: URL, trashOld: Bool,
                        fileManager fm: FileManager, io: BuildInstallIO,
                        trash: (URL) throws -> Void = OortSystem.trash) throws -> URL {
        guard let previous = updateIdentity(current) else { throw InstallError.failed("The installed app is missing or unsafe.") }
        var template = Array(current.deletingLastPathComponent().appendingPathComponent(".arcane-update.XXXXXX").path.utf8CString)
        let work = try template.withUnsafeMutableBufferPointer { buffer -> URL in
            guard let path = mkdtemp(buffer.baseAddress!) else { throw InstallError.failed(String(cString: strerror(errno))) }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
        // Never recursively remove this directory: after a swap it may hold the old app.
        defer { _ = rmdir(work.path) }
        let incoming = work.appendingPathComponent(current.lastPathComponent)
        do {
            try fm.copyItem(at: staged, to: incoming)
        } catch {
            // Only a partial copy inside this attempt's private directory is owned.
            try? fm.removeItem(at: incoming)
            throw InstallError.failed(error.localizedDescription)
        }
        guard let prepared = updateIdentity(incoming), updateIdentity(current) == previous else {
            try? fm.removeItem(at: incoming)
            throw InstallError.failed("The installed app changed while the update was being prepared.")
        }
        do {
            try io.publish(incoming, current, true)
            try io.afterPublish()
        } catch {
            // If publication already happened, finish the successful installation.
            // Otherwise remove only the candidate whose identity we recorded.
            guard updateIdentity(current) == prepared, updateIdentity(incoming) == previous else {
                if updateIdentity(incoming) == prepared { try? fm.removeItem(at: incoming) }
                throw InstallError.failed(error.localizedDescription)
            }
        }
        if updateIdentity(incoming) == previous {
            if trashOld { try? trash(incoming) }
            else { try? fm.removeItem(at: incoming) }
        }
        clearQuarantine(current)
        return current
    }

    private struct UpdateIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static func updateIdentity(_ url: URL) -> UpdateIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { return nil }
        return UpdateIdentity(device: info.st_dev, inode: info.st_ino)
    }

    /// Waits until `$1` (a pid) has exited, at most `$3` ticks of 0.2 s, then opens `$2` with `$4`.
    /// The paths arrive as arguments, never spliced into the script.
    static let relaunchScript = """
        n=0
        while kill -0 "$1" 2>/dev/null && [ "$n" -lt "$3" ]; do sleep 0.2; n=$((n+1)); done
        sleep 0.5
        exec "$4" "$2"
        """

    /// Starts the new copy once this one is gone (LaunchServices would only activate the running
    /// instance of the same bundle id). The caller terminates the app right after.
    @discardableResult
    public static func relaunch(_ app: URL, afterExitOf pid: Int32 = ProcessInfo.processInfo.processIdentifier,
                                timeout: TimeInterval = 30, opener: String = "/usr/bin/open") -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", relaunchScript, "sh", String(pid), app.path, String(Int(timeout / 0.2)), opener]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); return true } catch { return false }
    }

    private static func clearQuarantine(_ app: URL) {
        let x = Process()
        x.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        x.arguments = ["-dr", "com.apple.quarantine", app.path]
        x.standardOutput = FileHandle.nullDevice
        x.standardError = FileHandle.nullDevice
        (try? x.runWithExitWait())?()
    }
}
