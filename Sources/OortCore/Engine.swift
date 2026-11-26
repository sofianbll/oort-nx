import Foundation

public protocol EngineAdapter: Sendable {
    func workshop(_ place: Place) async throws(Refusal) -> Workshop
    func game(_ binding: EngineBinding) async throws(Refusal) -> GameDesk
}

public struct Ref<Role>: Hashable, Sendable {
    package let id: UUID
    package init(_ id: UUID) { self.id = id }
}
public enum PlaceRole {}; public typealias Place = Ref<PlaceRole>
public enum GameRole {}; public typealias Entry = Ref<GameRole>
public enum InstallationRole {}; public typealias Installation = Ref<InstallationRole>
public enum ProfileRole {}; public typealias Profile = Ref<ProfileRole>
public enum EpochRole {}; public typealias Generation = Ref<EpochRole>
public enum ChoiceRole {}; public typealias Confirmed = Ref<ChoiceRole>
public enum GestureRole {}; public typealias RequestID = Ref<GestureRole>
public enum RevisionRole {}; public typealias ReviewedRevision = Ref<RevisionRole>

public struct EngineBinding: Hashable, Sendable {
    public let place: Place
    public let entry: Entry
    public let installation: Installation
    public let profile: Profile
    public let generation: Generation

    package init(_ place: Place, _ entry: Entry, installation: Installation, profile: Profile, generation: Generation) {
        self.place = place; self.entry = entry; self.installation = installation
        self.profile = profile; self.generation = generation
    }
}

public enum Identity: Equatable, Sendable {
    case unknown, reported(String), verified(String)

    public var value: String? {
        switch self {
        case .unknown: nil
        case .reported(let value), .verified(let value): value
        }
    }
}

public enum Refusal: Error, Equatable, Sendable {
    case unsupported, notFound, differentOwner, stale, cancelled, upstream(UpstreamFailure)
}

public enum UpstreamFailure: Equatable, Sendable {
    case invalidBase, invalidURL, decoding
    case http(code: Int, message: String?)
    case rateLimited(reset: Date?)
    case connection(message: String)
}

public struct Offer<Input: Sendable, Output: Sendable>: Sendable {
    private let apply: @Sendable (Input, RequestID) async throws(Refusal) -> Output

    package init(_ apply: @escaping @Sendable (Input, RequestID) async throws(Refusal) -> Output) { self.apply = apply }

    public func run(_ input: Input, request: RequestID) async throws(Refusal) -> Output {
        try await apply(input, request)
    }
}

public struct VersionFacts: Equatable, Sendable {
    public let reference: Identity
    public let selected: Identity
    public let expected: Identity

    package init(reference: Identity, selected: Identity, expected: Identity) {
        self.reference = reference; self.selected = selected; self.expected = expected
    }
}

public enum CheckoutPresence: Equatable, Sendable { case missing, notACheckout, checkout }
public enum SetupCondition: Equatable, Sendable { case modifiedSelection }
public enum LocalKeyStatus: Equatable, Sendable { case unavailable, required, available(applicationGenerations: Int) }

public struct Workshop: Sendable {
    public let engineID: String
    public let versions: VersionFacts
    public let checkout: CheckoutPresence
    public let conditions: [SetupCondition]
    public let localKeys: LocalKeyStatus
    public let checkUpstream: Offer<Confirmed, UpstreamReview>

    package init(engineID: String, versions: VersionFacts, checkout: CheckoutPresence,
                 conditions: [SetupCondition], localKeys: LocalKeyStatus, checkUpstream: Offer<Confirmed, UpstreamReview>) {
        self.engineID = engineID; self.versions = versions; self.checkout = checkout
        self.conditions = conditions; self.localKeys = localKeys; self.checkUpstream = checkUpstream
    }
}

public struct GameDesk: Sendable {
    public let embedded: InstalledVersion
    package init(embedded: InstalledVersion) { self.embedded = embedded }
}

public struct InstalledVersion: Equatable, Sendable {
    public enum Relation: Equatable, Sendable { case current, older, newer, unknown }
    public enum Status: Equatable, Sendable { case noApp, unknown, known(Date, Relation) }
    public let identity: Identity
    public let status: Status
    package init(_ identity: Identity, status: Status) { self.identity = identity; self.status = status }
}

public struct UpstreamReview: Equatable, Sendable {
    public struct Commit: Codable, Equatable, Identifiable, Sendable {
        public let sha, subject, author, date: String
        public var id: String { sha }
        public var shortSha: String { String(sha.prefix(7)) }
        package init(sha: String, subject: String, author: String, date: String) {
            self.sha = sha; self.subject = subject; self.author = author; self.date = date
        }
    }

    public let revision: ReviewedRevision
    public let targetSHA: String
    public let newCommitsCount: Int
    public let commits: [Commit]
    public let isUpToDate: Bool

    package init(_ revision: ReviewedRevision, targetSHA: String, newCommitsCount: Int, commits: [Commit], isUpToDate: Bool) {
        self.revision = revision; self.targetSHA = targetSHA; self.newCommitsCount = newCommitsCount; self.commits = commits
        self.isUpToDate = isUpToDate
    }
}
