import Foundation
import Synchronization

/// The calls that differ from one system to the next, in one place. For now, where removed files go: the app run
/// from its bundle uses the system's Trash, any test or probe a folder of its own (lot 3 adds the other calls here).
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
        /// The folder a file of this volume can be renamed into.
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
        public static let system = Trash(put: { url in
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

    /// The Trash this process uses: `OORT_TRASH`; the system's for the app run from its bundle; else a folder of its own.
    public static var currentTrash: Trash {
        chosenTrash.withLock { chosen in
            if let chosen { return chosen }
            let trash: Trash
            if let path = ProcessInfo.processInfo.environment["OORT_TRASH"], !path.isEmpty {
                trash = .folder(at: URL(fileURLWithPath: path, isDirectory: true))
            } else if isBundledApp && !isTestProcess {
                trash = .system
            } else {
                trash = .folder(at: FileManager.default.temporaryDirectory
                    .appendingPathComponent("oort-trash-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true))
            }
            chosen = trash
            return trash
        }
    }

    /// Replaces the Trash of this process (a test that checks how a failing Trash is handled).
    public static func useTrash(_ trash: Trash) { chosenTrash.withLock { $0 = trash } }

    /// The app as players run it: from an `.app` bundle (probes and tests run bare executables or test bundles).
    private static var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

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
