import Foundation

package struct CloudDriveScope: Codable, Equatable, Sendable {
    package struct Folder: Codable, Equatable, Sendable {
        package let path: String
        package let id: String

        package init(path: String, id: String) {
            self.path = path
            self.id = id
        }
    }

    /// Where a new folder goes: the account and the parent's own ID, never its path alone.
    package struct CreationParent: Equatable, Sendable {
        package let account: String
        package let id: String

        package init(account: String, id: String) {
            self.account = account
            self.id = id
        }
    }

    package let remote: String
    package let account: String
    package let library: Folder
    package var sources: Folder?
    package var approvedSources: Folder?
    package var sourcesIdentityChanged: Bool?
    package var reference: String?

    package init(remote: String, account: String, library: Folder, sources: Folder? = nil, reference: String? = nil) {
        self.remote = remote
        self.account = account
        self.library = library
        self.sources = sources
        self.reference = reference
    }

    package var availabilityKey: [String] { [remote, account, library.id, sources?.id ?? "", reference ?? ""] }

    package mutating func resolveSources(_ found: Folder?, at path: String, previous: CloudDriveScope?) {
        let prior = previous.flatMap { old -> CloudDriveScope? in
            old.remote == remote && old.account == account && old.library == library ? old : nil
        }
        let previousApproval = (prior?.approvedSources ?? prior?.sources).flatMap { $0.path == path ? $0 : nil }
        approvedSources = previousApproval ?? found
        if let previousApproval, prior?.sourcesIdentityChanged == true || (found != nil && found != previousApproval) {
            sourcesIdentityChanged = true
            sources = nil
        } else {
            sources = found
        }
    }

    package mutating func clearSourcesApproval() {
        sources = nil
        approvedSources = nil
        sourcesIdentityChanged = nil
    }

    // shortcut: rclone does not expose the canonical My Drive ID as structured data.
    package static func accountID(in diagnostic: String) -> String? {
        struct LogLine: Decodable { let msg: String }
        let marker = "'root_folder_id = ", suffix = "' - save this in the config to speed up startup"
        let matches = Set(diagnostic.split(whereSeparator: \.isNewline).compactMap { raw -> String? in
            let line = (try? JSONDecoder().decode(LogLine.self, from: Data(raw.utf8)))?.msg ?? String(raw)
            guard let start = line.range(of: marker, options: .backwards), line.hasSuffix(suffix) else { return nil }
            return String(line[start.upperBound..<line.index(line.endIndex, offsetBy: -suffix.count)])
        })
        guard matches.count == 1, let id = matches.first, validID(id) else { return nil }
        return id
    }

    static func validID(_ id: String) -> Bool {
        id != "root" && id != "appDataFolder" && id.range(of: #"^[A-Za-z0-9_-]{1,256}\z"#, options: .regularExpression) != nil
    }
}
