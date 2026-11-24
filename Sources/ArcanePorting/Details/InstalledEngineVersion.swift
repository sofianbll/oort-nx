import Foundation
import NXLibraryCore

/// The version of the installed bundle, not the engine expected by its build record.
public enum InstalledEngineVersion: Equatable, Sendable {
    case noApp
    case unknown
    case known(Date, Relation)

    public enum Relation: Equatable, Sendable { case current, older, newer, unknown }

    public var isOlder: Bool {
        if case .known(_, .older) = self { return true }
        return false
    }

    public func detail(filesAvailable: Bool, context: AppLocale = L10n.context) -> String {
        switch self {
        case .noApp: return L10n.text("No installed app", context: context)
        case .unknown: return L10n.text("Engine version unknown", context: context)
        case .known(let date, let relation):
            let key: String
            switch relation {
            case .current: key = "%@ · up to date"
            case .older: key = filesAvailable ? "%@ · update available" : "%@ · game files needed first"
            case .newer: key = "%@ · newer than Oort’s engine"
            case .unknown: key = "%@ · update status unknown"
            }
            return L10n.format(key, [date.formatted(.dateTime.day().month(.abbreviated).locale(context.formatLocale))],
                               context: context)
        }
    }
}

/// A read-only scan of the apps and the selected checkout. Create one reader per background refresh,
/// so equal commits share Git work, and replaced apps and newly fetched history are read on the next refresh.
package struct InstalledEngineVersionReader {
    private let checkout: String
    private let runner: any CommandRunning
    private let selected: String?
    private var versions: [String: InstalledEngineVersion] = [:]

    package init(checkout: String, selected: String, runner: any CommandRunning = SystemCommandRunner()) {
        self.checkout = checkout
        self.runner = runner
        self.selected = Self.commitID(selected, checkout: checkout, runner: runner)?.hash
    }

    package mutating func version(of app: URL?) -> InstalledEngineVersion {
        guard let app, FileManager.default.fileExists(atPath: app.path) else { return .noApp }
        guard let stamp = CheatLocator.engineCommit(appURL: app, recorded: nil) else { return .unknown }
        if let known = versions[stamp] { return known }
        let version = Self.commitID(stamp, checkout: checkout, runner: runner).map { built in
            InstalledEngineVersion.known(built.date, relation(of: built.hash))
        } ?? .unknown
        versions[stamp] = version
        return version
    }

    private func relation(of built: String) -> InstalledEngineVersion.Relation {
        guard let selected else { return .unknown }
        if built == selected { return .current }
        let ahead = run(["merge-base", "--is-ancestor", built, selected])
        if ahead?.status == 0 { return .older }
        if ahead?.status == 1, run(["merge-base", "--is-ancestor", selected, built])?.status == 0 { return .newer }
        return .unknown
    }

    private func run(_ args: [String]) -> CommandResult? {
        Self.run(args, checkout: checkout, runner: runner)
    }

    private static func commitID(_ stamp: String, checkout: String,
                                 runner: any CommandRunning) -> (hash: String, date: Date)? {
        guard (7...40).contains(stamp.utf8.count), stamp.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { return nil }
        let result = run(["show", "--no-patch", "--no-notes", "--no-show-signature", "--format=%H %ct", "\(stamp)^{commit}", "--"],
                         checkout: checkout, runner: runner)
        guard let result, result.status == 0 else { return nil }
        let fields = result.stdout.split(whereSeparator: \.isWhitespace)
        guard fields.count == 2, fields[0].count == 40, fields[0].hasPrefix(stamp.lowercased()),
              let seconds = Int64(fields[1]) else { return nil }
        return (String(fields[0]), Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    private static func run(_ args: [String], checkout: String, runner: any CommandRunning) -> CommandResult? {
        // Never let Git silently fall back to an enclosing repository if the engine checkout is gone.
        guard checkout.hasPrefix("/"), FileManager.default.fileExists(atPath: checkout + "/.git") else { return nil }
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_NO_LAZY_FETCH"] = "1"
        return try? runner.run(URL(fileURLWithPath: "/usr/bin/git"), ["--no-replace-objects", "-C", checkout] + args,
                               environment: environment, currentDirectory: nil)
    }
}
