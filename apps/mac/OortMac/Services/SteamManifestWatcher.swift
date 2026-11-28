import Foundation
import CoreServices
import OortLibrary

/// Tells Arcane when Steam rewrites a manifest (a download starts, pauses or finishes, a game is installed,
/// removed or launched) or the library index, so the Steam source can rescan without a Refresh. One FSEvents
/// stream over the `steamapps` folders of the libraries the last scan read. FSEvents is recursive, so a download's
/// writes under `downloading/` reach the callback too: its 2 s latency batches them and only the paths are
/// compared, nothing is read. `CatalogSourcesModel.steamFilesChanged` paces the rescans.
@MainActor
public final class SteamManifestWatcher {
    /// Called on the main thread, at most once per batch of events.
    public var onChange: (@MainActor () -> Void)?

    private var stream: FSEventStreamRef?
    private var watched: [String] = []
    private var libraries: [String] = []
    private var root: String?

    public init(onChange: (@MainActor () -> Void)? = nil) { self.onChange = onChange }

    /// Watches these libraries (the scan's, the source's root among them). Rechecks available folders even for
    /// the same set, so a library returning on an external drive joins the stream. None stops watching.
    public func watch(_ libraries: [URL], root: URL?) {
        let paths = libraries.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let rootPath = root.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let folders = paths.map { $0 + "/steamapps" }.filter { FileManager.default.fileExists(atPath: $0) }
        guard paths != self.libraries || rootPath != self.root || folders != watched else { return }
        stop()
        guard !folders.isEmpty else { return }
        // The stream holds the watcher until it is released in `stop`, so a callback already queued on the main
        // queue never reaches a freed watcher.
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: Self.retain, release: Self.release, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                                             | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(nil, Self.callback, &context, folders as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
        self.libraries = paths
        self.root = rootPath
        watched = folders
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
        }
        stream = nil; watched = []; libraries = []; root = nil
    }

    private func received(_ paths: [String], flags: [FSEventStreamEventFlags]) {
        let mustScan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        let changed = zip(paths, flags).contains { path, flag in
            // FSEvents can spell /var and /tmp with /private; compare in the same form as `watch`.
            let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            return SteamManifestPaths.isRelevant(canonical, dropped: flag & mustScan != 0, libraries: libraries, root: root)
        }
        if changed { onChange?() }
    }

    // FSEvents may call these on its own threads, so they stay outside the main actor.
    private nonisolated static let retain: CFAllocatorRetainCallBack = { info in
        guard let info else { return nil }
        _ = Unmanaged<SteamManifestWatcher>.fromOpaque(info).retain()
        return info
    }
    private nonisolated static let release: CFAllocatorReleaseCallBack = { info in
        guard let info else { return }
        Unmanaged<SteamManifestWatcher>.fromOpaque(info).release()
    }

    private nonisolated static let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
        guard let info else { return }
        let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
        let flags = Array(UnsafeBufferPointer(start: eventFlags, count: count))
        let watcher = Unmanaged<SteamManifestWatcher>.fromOpaque(info).takeUnretainedValue()
        MainActor.assumeIsolated { watcher.received(paths, flags: flags) }
    }
}
