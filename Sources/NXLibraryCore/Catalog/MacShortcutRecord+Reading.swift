import Darwin
import Foundation

// Choosing, re-checking and relinking an app reads its bundle with POSIX calls, so this half stays with Darwin.
extension MacShortcutRecord {
    init(chosenURL: URL) throws {
        let app = try Self.readApplication(at: chosenURL)
        id = UUID()
        name = app.name
        bundleIdentifier = app.bundleID
        url = app.url
    }

    public func verifiedURL() -> URL? {
        guard let app = try? Self.readApplication(at: url),
              app.url.path == url.path, app.bundleID == bundleIdentifier else { return nil }
        return app.url
    }

    mutating func relink(to chosenURL: URL) throws {
        let app = try Self.readApplication(at: chosenURL)
        guard app.bundleID == bundleIdentifier else { throw MacShortcutError.differentApplication }
        url = app.url
    }

    static func canonical(_ url: URL, directory: Bool = false) -> URL? {
        guard url.isFileURL, (url.host(percentEncoded: false) ?? "").isEmpty, let path = realpath(url.path, nil) else { return nil }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path), isDirectory: directory)
    }

    static func readApplication(at chosenURL: URL) throws -> (url: URL, bundleID: String, name: String) {
        guard let app = canonical(chosenURL, directory: true), app.pathExtension.lowercased() == "app",
              let plist = canonical(app.appendingPathComponent("Contents/Info.plist")),
              NativeMacApplication.isWithin(plist, root: app),
              let metadata = try? InstallationFileSnapshot.read(at: plist, maximumBytes: 1024 * 1024),
              let info = (try? PropertyListSerialization.propertyList(from: metadata.data, format: nil)) as? [String: Any],
              info["CFBundlePackageType"].map({ ($0 as? String) == "APPL" }) != false,
              let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty, executable != ".", executable != "..", !executable.contains("/"),
              let binary = canonical(app.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)),
              binary.path != app.path, NativeMacApplication.isWithin(binary, root: app),
              (try? binary.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              FileManager.default.isExecutableFile(atPath: binary.path) else { throw MacShortcutError.invalidApplication }
        try metadata.verifyUnchanged()
        let name = ["CFBundleDisplayName", "CFBundleName"].lazy.compactMap { info[$0] as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? app.deletingPathExtension().lastPathComponent
        return (app, bundleID, name)
    }
}
