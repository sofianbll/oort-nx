import Foundation
import Synchronization

/// Where removed files go: the app run from its bundle uses the system's Trash; tests and probes use their own.
public enum OortSystem {
    /// The system has no equivalent of this operation yet.
    public struct Unsupported: Error, Equatable, Sendable {
        public let operation: String
    }

    /// Where removed files go. Only the app, run from its `.app` bundle, uses the system's Trash. Any other process (a
    /// test, a probe, a throwaway executable, however it was started) gets a folder of its own: `OORT_TRASH` when
    /// scripts/check sets it, a new temporary folder otherwise.
    public struct Trash: Sendable {
        /// Moves a file or folder there.
        public let put: @Sendable (URL) throws -> Void
        /// The Trash folder. With a fixture, the caller still checks that it is on the source volume before renaming.
        public let folder: @Sendable (URL) throws -> URL
        /// The folder of a test or probe Trash; nil for the system's.
        public let root: URL?

        public init(put: @escaping @Sendable (URL) throws -> Void, folder: @escaping @Sendable (URL) throws -> URL,
                    root: URL? = nil) {
            self.put = put
            self.folder = folder
            self.root = root
        }

        /// The user's Trash.
        static let system = Trash(put: { url in
            #if canImport(Darwin)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            #else
            throw Unsupported(operation: "trash")
            #endif
        }, folder: { url in
            #if canImport(Darwin)
            try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)
            #else
            throw Unsupported(operation: "trash")
            #endif
        })

        /// A Trash in `root`: an item keeps its name, with a number when the name is taken.
        public static func folder(at root: URL) -> Trash {
            Trash(put: { url in
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var target = root.appendingPathComponent(url.lastPathComponent)
                var number = 1
                while FileManager.default.fileExists(atPath: target.path) {
                    number += 1
                    target = root.appendingPathComponent("\(url.lastPathComponent) \(number)")
                }
                try FileManager.default.moveItem(at: url, to: target)
            }, folder: { _ in
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                return root
            }, root: root)
        }
    }

    /// Whether this system has a Trash of its own.
    public static var hasTrash: Bool {
        #if canImport(Darwin)
        true
        #else
        false
        #endif
    }

    private static let chosenTrash = Mutex<Trash?>(nil)

    /// The Trash this process uses: a valid `OORT_TRASH`; the system's for a normal app launch; else its own folder.
    static var currentTrash: Trash {
        chosenTrash.withLock { chosen in
            if let chosen { return chosen }
            let trash: Trash
            let environment = ProcessInfo.processInfo.environment
            let temporary = FileManager.default.temporaryDirectory
            if let path = environment["OORT_TRASH"], let root = fixtureTrashRoot(path, in: temporary) {
                trash = .folder(at: root)
            } else if environment["OORT_TRASH"] == nil && isBundledApp && !isTestProcess && !isFixtureProcess {
                trash = .system
            } else {
                trash = .folder(at: temporary.appendingPathComponent("oort-trash-\(UUID())", isDirectory: true))
            }
            chosen = trash
            return trash
        }
    }

    /// A runner must give us an existing directory beneath the system's temporary directory.
    /// Check the resolved path so a link outside that tree is not accepted.
    static func fixtureTrashRoot(_ path: String, in temporary: URL) -> URL? {
        guard (path as NSString).isAbsolutePath else { return nil }
        let root = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let parent = temporary.resolvingSymlinksInPath().standardizedFileURL.path
        guard root.path.hasPrefix(parent + "/"),
              !root.pathComponents.contains(where: { [".trash", ".trashes"].contains($0.lowercased()) }),
              (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        return root
    }

    private static var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private static var isFixtureProcess: Bool {
        if ProcessInfo.processInfo.environment["OORT_HEADLESS_INPUT"] == "1" { return true }
        #if DEBUG
        return AppData.integrationFixtureHome != nil
        #else
        return false
        #endif
    }

    private static var isTestProcess: Bool {
        if NSClassFromString("XCTestCase") != nil { return true }
        let name = ProcessInfo.processInfo.processName
        return name.hasSuffix(".xctest") || name.hasSuffix("PackageTests") || name.hasSuffix("-test-runner")
    }

    /// Moves a file or folder to this process's Trash.
    public static func trash(_ url: URL) throws { try currentTrash.put(url) }

    /// The Trash folder a file of `url`'s volume can be renamed into.
    public static func trashFolder(for url: URL) throws -> URL { try currentTrash.folder(url) }
}
