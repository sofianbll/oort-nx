import Foundation
import NXLibraryCore

/// Presentation of the installed bundle, not the engine expected by its build record.
extension InstalledVersion.Status {
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
private struct InstalledEngineVersionReader {
    private let checkout: String
    private let runner: any CommandRunning
    private let selected: String?
    private var versions: [String: InstalledVersion] = [:]

    init(checkout: String, selected: String, runner: any CommandRunning = SystemCommandRunner()) {
        self.checkout = checkout
        self.runner = runner
        self.selected = Self.commitID(selected, checkout: checkout, runner: runner)?.hash
    }

    mutating func version(of app: URL?) -> InstalledVersion {
        guard let app, FileManager.default.fileExists(atPath: app.path) else { return .init(.unknown, status: .noApp) }
        guard let stamp = MacNXNative.embeddedStamp(in: app) else { return .init(.unknown, status: .unknown) }
        if let known = versions[stamp] { return known }
        let version = Self.commitID(stamp, checkout: checkout, runner: runner).map { built in
            InstalledVersion(.reported(stamp), status: .known(built.date, relation(of: built.hash)))
        } ?? .init(.reported(stamp), status: .unknown)
        versions[stamp] = version
        return version
    }

    private func relation(of built: String) -> InstalledVersion.Relation {
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

    static func run(_ args: [String], checkout: String, runner: any CommandRunning, developerDir: URL? = nil) -> CommandResult? {
        // Never let Git silently fall back to an enclosing repository if the engine checkout is gone.
        guard checkout.hasPrefix("/"), FileManager.default.fileExists(atPath: checkout + "/.git") else { return nil }
        var environment = ProcessInfo.processInfo.environment
        if let developerDir { environment["DEVELOPER_DIR"] = developerDir.path }
        environment["GIT_NO_LAZY_FETCH"] = "1"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        return try? runner.run(URL(fileURLWithPath: "/usr/bin/git"), ["--no-replace-objects", "-C", checkout] + args,
                               environment: environment, currentDirectory: nil)
    }
}

/// Reads a bounded local nxnative installation and provides the explicit upstream check.
package actor MacNXNative: EngineAdapter {
    package static func embeddedStamp(in app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let info = (try? Data(contentsOf: plist))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        guard let commit = embeddedStamp(in: info ?? [:]), (7...40).contains(commit.count),
              commit.allSatisfy(\.isHexDigit) else { return nil }
        return commit
    }

    /// The cloud archive transports the recorded value unchanged; only Git readers validate a hash.
    static func embeddedStamp(in info: [String: Any]) -> String? { info["DMCommit"] as? String }

    private let place: Place
    private let checkout: String
    private let prescribed: String
    private let expected: String
    private let apps: [Installation: URL]
    private let keys: URL?
    private let developerDir: URL?
    private let runner: any CommandRunning & Sendable
    private let client: any UpstreamHTTPClient & Sendable
    private let persistReview: Bool
    private lazy var installed = InstalledEngineVersionReader(checkout: checkout, selected: expected, runner: runner)

    package init(place: Place, checkout: String, prescribed: String, expected: String,
                 apps: [Installation: URL] = [:], keys: URL? = nil, developerDir: URL? = nil,
                 runner: any CommandRunning & Sendable = SystemCommandRunner(),
                 client: any UpstreamHTTPClient & Sendable = URLSessionUpstreamClient(), persistReview: Bool = false) {
        self.place = place; self.checkout = checkout; self.prescribed = prescribed; self.expected = expected
        self.apps = apps; self.keys = keys; self.developerDir = developerDir
        self.runner = runner; self.client = client; self.persistReview = persistReview
    }

    package nonisolated func workshop(_ place: Place) throws(Refusal) -> Workshop {
        guard place == self.place else { throw .differentOwner }
        return workshop()
    }

    package nonisolated func workshop() -> Workshop { capture().0 }

    package nonisolated func compatibility(toolchain: EngineToolchain) -> (Workshop, CompatibilityReport) {
        let (snapshot, changes) = capture()
        let checker = CompatibilityChecker(repoURL: URL(fileURLWithPath: checkout), toolchain: toolchain,
                                           developerDir: developerDir, runner: runner)
        return (snapshot, checker.check(snapshot.versions, changes: changes))
    }

    private nonisolated func capture() -> (Workshop, [String]?) {
        let (checkout, head, changes) = readCheckout()
        let status = keys.map { KeyStore(directory: $0).readStatus() } ?? .required
        let prescribed = self.prescribed
        let client = self.client
        let persistReview = self.persistReview
        return (.init(engineID: "nxnative", versions: .init(reference: prescribed,
                     selected: head.map(Identity.reported) ?? .unknown, expected: expected),
                     checkout: checkout, localKeys: status,
                     checkUpstream: Offer { (_: Confirmed, _: RequestID) throws(Refusal) -> UpstreamReview in
            try await UpstreamChecker(client: client).review(from: prescribed, persist: persistReview)
        }), changes)
    }

    package func game(_ binding: EngineBinding) async throws(Refusal) -> GameDesk {
        guard binding.place == place else { throw .differentOwner }
        return .init(embedded: installed.version(of: apps[binding.installation]))
    }

    package nonisolated static func cachedReview(from base: String) -> UpstreamReview? {
        UpstreamChecker.cachedReview(from: base)
    }

    package nonisolated static func compareURL(from base: String) -> URL? {
        UpstreamChecker.compareURL(from: base)
    }

    private nonisolated func readCheckout() -> (EngineCheckout, String?, [String]?) {
        let path = checkout
        var directory: ObjCBool = false
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &directory),
              directory.boolValue else { return (.missing, nil, nil) }
        func git(_ args: [String]) -> CommandResult? {
            InstalledEngineVersionReader.run(args, checkout: path, runner: runner, developerDir: developerDir)
        }
        let head = git(["rev-parse", "HEAD"])
        let status = git(["status", "--porcelain"])
        let changes = status.flatMap { $0.status == 0 ? CompatibilityChecker.relevantChanges($0.stdout) : nil }
        guard let head, head.status == 0 else { return (.notACheckout, nil, changes) }
        let revision = head.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revision.isEmpty else { return (.notACheckout, nil, changes) }
        let relation: EngineCheckout.Relation
        if revision == prescribed {
            relation = .current
        } else {
            switch git(["merge-base", "--is-ancestor", revision, prescribed])?.status {
            case 0: relation = .behind
            case 1: relation = .divergent
            default: relation = .unknown
            }
        }
        return (.checkout(head: revision, relation: relation,
                          tree: changes.map { $0.isEmpty ? .clean : .modified } ?? .unreadable), revision, changes)
    }
}
