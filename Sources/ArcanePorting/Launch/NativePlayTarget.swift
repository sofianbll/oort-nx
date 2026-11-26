import AppKit
import Darwin

/// The identity of a local delivery target, independent of its catalog entry and symlinks.
package struct NativePlayTarget: Sendable {
    package let url: URL
    package let scope: String
    package let bundleID: String

    package init?(_ requested: URL) {
        guard requested.isFileURL else { return nil }
        let url = requested.resolvingSymlinksInPath()
        guard let scope = Self.identity(url), let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty else { return nil }
        self.url = url
        self.scope = scope
        self.bundleID = id
    }

    private static func identity(_ url: URL) -> String? {
        var info = stat()
        guard stat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]),
              let volume = values.volumeUUIDString.flatMap(UUID.init(uuidString:))
        else { return nil }
        return "mac-\(volume.uuidString.lowercased())-\(info.st_ino)"
    }

    func matches(_ application: NSRunningApplication) -> Bool {
        guard !application.isTerminated, let bundle = application.bundleURL else { return false }
        return Self.identity(bundle) == scope
    }

    package func running() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter(matches)
    }

    package static func openConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false
        return configuration
    }

    static let originKey = "OORT_PLAY_ORIGIN"

    /// Read only an exact, bounded startup marker of the candidate process. AppKit may
    /// return a concurrent external launch at the same URL without applying our environment.
    static func receivedOrigin(_ origin: String, pid: pid_t) -> Bool {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var count = 0
        guard sysctl(&mib, 3, nil, &count, nil, 0) == 0, (5...1_048_576).contains(count) else { return false }
        var raw = [UInt8](repeating: 0, count: count)
        guard sysctl(&mib, 3, &raw, &count, nil, 0) == 0, (5...raw.count).contains(count) else { return false }
        let argc = raw.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0, argc < count else { return false }
        let strings = raw[MemoryLayout<Int32>.size..<count]
        guard let executableEnd = strings.firstIndex(of: 0) else { return false }
        var entries = strings[(executableEnd + 1)...].drop(while: { $0 == 0 })
        for _ in 0..<argc {
            guard let end = entries.firstIndex(of: 0) else { return false }
            entries = entries[(end + 1)...]
        }
        let marker = "\(originKey)=\(origin)".utf8
        while let end = entries.firstIndex(of: 0), end != entries.startIndex {
            if entries[..<end].elementsEqual(marker) { return true }
            entries = entries[(end + 1)...]
        }
        return false
    }
}
