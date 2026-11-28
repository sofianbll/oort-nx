// Adapted from NX2Apple's AppUpdate.swift (https://github.com/LNPANDY/NX2Apple), MIT License,
// Copyright (c) 2026 LNPANDY and NX2Apple contributors. See NOTICE.

import Foundation
import Crypto

/// The rules of Arcane's self-update: which release, what may be installed, which copy may
/// replace itself, and the swap. Everything works on paths it is given, so the tests run it on
/// bundles in a temporary folder, never on the running app or the network.
///
/// - What is installed is what GitHub says the release is: the zip's SHA-256 matches the asset's
///   `digest`, and the app inside carries this app's bundle identifier, an executable, the
///   release's version and the release marker.
/// - Only a release copy (`NXLibraryRelease` in its Info.plist, written by scripts/release.sh)
///   replaces itself; a developer's `build_app.sh` build never does.
/// - A failure anywhere leaves a working app where it was.
public enum AppUpdate {
    /// Public release source. Development copies still never replace themselves.
    public static let defaultRepository: String? = "sofianbll/oort-nx"
    /// A UserDefaults override of `defaultRepository`, for testing before publishing.
    public static let repositoryOverrideKey = "NXLibrary_UpdateRepository"
    /// The name this repository would have after a rename on GitHub, whose asset URLs then use it.
    public static let successorRepository: String? = nil
    /// The update's archive, and the app inside it.
    public static func archiveName(_ version: String) -> String { "Oort-NX-\(version).zip" }
    public static let bundleName = "Oort NX.app"
    /// The Info.plist key that marks a release copy.
    public static let releaseMarker = "NXLibraryRelease"
    static let interval: TimeInterval = 24 * 3600
    public static let maximumDownloadBytes: Int64 = 512 * 1024 * 1024

    /// The version as Settings shows it: a copy without the release marker is a development build
    /// of the version in progress, so it never reads like a published release.
    public static func versionLabel(_ info: [String: Any]?, context: AppLocale? = nil) -> String {
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        if info?[releaseMarker] as? Bool == true { return short }
        if info?["NXLibraryDevelopmentProfile"] as? Bool == true { return "\(short) (Dev · Launcher)" }
        return L10n.format("%@ (development build)", [short], context: context)
    }

    public static func repository(defaults: UserDefaults = AppData.preferences) -> String? {
        if let value = defaults.string(forKey: repositoryOverrideKey)?.trimmingCharacters(in: .whitespaces),
           value.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return defaultRepository
    }

    // MARK: - The release

    public struct Release: Equatable, Sendable {
        public var tag: String
        public var version: String
        /// The notes as shown, without the requirements line.
        public var notes: String
        public var zipURL: URL
        /// "sha256:<hex>"; nil when GitHub gave none.
        public var digest: String?
        public var archiveBytes: Int64
        public var requirements = Requirements()
    }

    /// What a release needs on this Mac, from a hidden line scripts/release.sh adds to its notes.
    public struct Requirements: Equatable, Sendable {
        public var minimumXcode: String?
        public var engineCommit: String?

        public init(minimumXcode: String? = nil, engineCommit: String? = nil) {
            self.minimumXcode = minimumXcode
            self.engineCommit = engineCommit
        }
    }

    static let requirementsMarker = "nxlibrary-requires"

    /// "<!-- nxlibrary-requires xcode=27.1 engine=<commit> -->", the line scripts/release.sh writes.
    public static func requirementsLine(minimumXcode: String, engineCommit: String) -> String {
        "<!-- \(requirementsMarker) xcode=\(minimumXcode) engine=\(engineCommit) -->"
    }

    /// The requirements line's values, and the notes without it.
    public static func requirements(in notes: String) -> (Requirements, String) {
        guard let range = notes.range(of: #"<!--\s*nxlibrary-requires\s+([^>]*?)\s*-->"#, options: .regularExpression)
        else { return (Requirements(), notes.trimmingCharacters(in: .whitespacesAndNewlines)) }
        var requirements = Requirements()
        let body = notes[range].dropFirst(4).dropLast(3)
        for pair in body.split(whereSeparator: \.isWhitespace) {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "xcode": requirements.minimumXcode = parts[1]
            case "engine": requirements.engineCommit = parts[1]
            default: break
            }
        }
        var shown = notes
        shown.removeSubrange(range)
        return (requirements, shown.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The Xcode version this Mac must update to for new portings with the release; nil when it has it (or has
    /// none, the Setup check's job).
    public static func neededXcode(_ requirements: Requirements, installedXcode: String?) -> String? {
        guard let minimum = requirements.minimumXcode, let installed = installedXcode,
              VersionNumber.isOlder(installed, than: minimum) else { return nil }
        return minimum
    }

    /// What the update dialog says before installing: an Xcode this Mac must update first (new portings wait for
    /// it), and a new engine that Setup brings after the restart.
    public static func requirementNotes(_ requirements: Requirements, installedXcode: String?,
                                        currentEngine: String) -> [String] {
        var notes: [String] = []
        if let minimum = neededXcode(requirements, installedXcode: installedXcode), let installed = installedXcode {
            notes.append("New portings need Xcode \(minimum); this Mac has \(installed). Update Xcode from the App Store first. Your games keep playing.")
        }
        if let engine = requirements.engineCommit, !engine.isEmpty, engine != currentEngine {
            notes.append("It comes with nxnative \(engine.prefix(7)): after the restart, Setup downloads it in one step.")
        }
        return notes
    }

    /// GitHub's `releases/latest` answer, with the asset named `Oort-NX-<version>.zip` in `repository`
    /// or, when there is one, in its `successor`.
    public static func parseRelease(_ json: Data, repository: String = "Bium23/NxLibrary",
                                    successor: String? = AppUpdate.successorRepository) -> Release? {
        guard json.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tag = object["tag_name"] as? String, let version = version(fromTag: tag),
              let assets = object["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == archiveName(version) }),
              let link = asset["browser_download_url"] as? String, let url = URL(string: link),
              trustedDownloadURL(url), url.host?.lowercased() == "github.com",
              ([repository] + [successor].compactMap { $0 }).contains(where: { owner in
                  url.path == "/\(owner)/releases/download/\(tag)/\(archiveName(version))"
              }),
              url.query == nil, url.fragment == nil,
              let bytes = asset["size"] as? Int64, bytes > 0, bytes <= maximumDownloadBytes,
              let digest = asset["digest"] as? String,
              digest.range(of: #"^sha256:[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil
        else { return nil }
        let (requirements, notes) = requirements(in: object["body"] as? String ?? "")
        return Release(tag: tag, version: version, notes: notes, zipURL: url, digest: digest, archiveBytes: bytes,
                       requirements: requirements)
    }

    /// GitHub's `releases/latest` leaves pre-releases out; take a wider page because other systems share the list.
    public static func releasesURL(repository: String, runningVersion: String) -> URL? {
        let preRelease = parsed(runningVersion).map { $0.stage < 3 } ?? false
        return URL(string: "https://api.github.com/repos/\(repository)/releases" + (preRelease ? "?per_page=100" : "/latest"))
    }

    /// The answer to `releasesURL`: one release, or a list whose newest usable one counts.
    public static func parseReleases(_ json: Data, repository: String) -> Release? {
        guard json.count <= 1024 * 1024 else { return nil }
        guard let list = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else {
            return parseRelease(json, repository: repository)
        }
        return list.filter { $0["draft"] as? Bool != true }
            .compactMap { try? JSONSerialization.data(withJSONObject: $0) }
            .compactMap { parseRelease($0, repository: repository) }
            .reduce(nil) { best, next in best.map { isNewer(next.version, than: $0.version) } == false ? best : next }
    }

    /// GitHub's release redirect stays within its HTTPS download infrastructure.
    public static func trustedDownloadURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
            && ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"]
                .contains(url.host?.lowercased() ?? "")
    }

    public static func downloadWithinLimit(received: Int64, expected: Int64) -> Bool {
        expected > 0 && expected <= maximumDownloadBytes && received >= 0 && received <= expected
    }

    public static func version(fromTag tag: String) -> String? {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return parsed(version) == nil ? nil : version
    }

    /// "1.2.3" → [1, 2, 3]; nil unless one to four non-negative numbers.
    public static func numbers(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        let values = parts.map { part in part.allSatisfy(\.isASCII) ? Int(part) : nil }
        return values.contains(where: { $0 == nil || $0! < 0 }) ? nil : values.map { $0! }
    }

    /// The numbers, then where the version stands: alpha, beta and rc come before the release itself.
    private static func parsed(_ version: String) -> (numbers: [Int], stage: Int, count: Int)? {
        guard let dash = version.firstIndex(of: "-") else { return numbers(version).map { ($0, 3, 0) } }
        let suffix = version[version.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false)
        guard let core = numbers(String(version[..<dash])), core.count == 3, suffix.count == 2,
              let stage = ["alpha", "beta", "rc"].firstIndex(of: String(suffix[0])),
              suffix[1].allSatisfy({ $0.isASCII && $0.isNumber }), suffix[1].first != "0", let count = Int(suffix[1])
        else { return nil }
        return (core, stage, count)
    }

    /// Semantic order, a missing field counting as 0: "0.10.0" is newer than "0.9.3", "0.2" equals "0.2.0",
    /// and 0.5.0-alpha.2 < 0.5.0-beta.1 < 0.5.0-beta.10 < 0.5.0.
    public static func isNewer(_ candidate: String, than running: String) -> Bool {
        guard let a = parsed(candidate), let b = parsed(running) else { return false }
        for i in 0..<max(a.numbers.count, b.numbers.count) {
            let x = i < a.numbers.count ? a.numbers[i] : 0, y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x > y }
        }
        return (a.stage, a.count) > (b.stage, b.count)
    }

    // MARK: - When

    public static func shouldCheck(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// Later hides one version for 24 hours; a newer version is offered at once.
    public static func shouldOffer(_ version: String, laterVersion: String?, laterAt: Date?, now: Date) -> Bool {
        guard laterVersion == version, let laterAt else { return true }
        return now.timeIntervalSince(laterAt) >= interval
    }

    // MARK: - What was downloaded

    public enum DigestCheck: Equatable { case match, mismatch, missing }

    /// The SHA-256 of a file as lowercase hex, read in pieces.
    static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A digest in another algorithm, or none, is missing: there is nothing to compare with.
    public static func checkDigest(_ file: URL, expected: String?) -> DigestCheck {
        guard let expected, expected.lowercased().hasPrefix("sha256:") else { return .missing }
        let want = expected.dropFirst("sha256:".count).trimmingCharacters(in: .whitespaces).lowercased()
        guard want.count == 64, let have = sha256(of: file) else { return want.isEmpty ? .missing : .mismatch }
        return have == want ? .match : .mismatch
    }

    // MARK: - Which copy may replace itself

    public enum Installability: Equatable {
        case ok
        /// Not a release copy: a developer's build never replaces itself.
        case developer
        /// A release copy that cannot be replaced where it is (App Translocation, a read-only folder).
        case readOnly
    }
}
