import Foundation

public struct CloudGoogleClient: Sendable {
    public let id: String
    public let secret: String

    public static let bundled = configured(in: Bundle.main.infoDictionary ?? [:])

    static func configured(in info: [String: Any]) -> Self? {
        guard let id = info["ArcaneGoogleClientID"] as? String,
              let secret = info["ArcaneGoogleClientSecret"] as? String,
              CloudSetupAssistantDraft.validGoogleClientID(id), RcloneConfiguration.validCredential(secret)
        else { return nil }
        return Self(id: id, secret: secret)
    }
}

public struct CloudSetupAssistantDraft {
    public enum Step: Int, CaseIterable { case account, folder, verify }

    public private(set) var step: Step = .account
    public private(set) var remote: String?
    public private(set) var path = ""
    public private(set) var ticket = UUID()
    public private(set) var verified = false
    public private(set) var wantsMove = false
    private var moveCompleted = false

    public init() {}

    public static func validGoogleClientID(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^[A-Za-z0-9][A-Za-z0-9-]*\.apps\.googleusercontent\.com\z"#,
                   options: .regularExpression) != nil
    }

    public mutating func chooseAccount(_ name: String) {
        remote = name
        step = .folder
        browse("")
    }

    @discardableResult
    public mutating func browse(_ folder: String) -> UUID {
        path = folder
        wantsMove = false
        return renewTicket()
    }

    @discardableResult
    public mutating func renewTicket() -> UUID {
        verified = false
        moveCompleted = false
        ticket = UUID()
        return ticket
    }

    public func matches(_ ticket: UUID) -> Bool { self.ticket == ticket }

    @discardableResult
    public mutating func useFolder() -> Bool {
        guard step == .folder, candidate != nil else { return false }
        step = .verify
        renewTicket()
        return true
    }

    public mutating func backToFolders() {
        step = .folder
        renewTicket()
    }

    public mutating func acceptAccessCheck(_ ticket: UUID) {
        if step == .verify, matches(ticket) { verified = true }
    }

    public mutating func toggleMove() {
        if step == .folder { wantsMove.toggle() }
    }

    public mutating func acceptMove(_ ticket: UUID) {
        if step == .verify, verified, wantsMove, matches(ticket) { moveCompleted = true }
    }

    public var candidate: CloudLibraryPreference? {
        guard let remote, CloudLibraryPreference.validRoot(path) else { return nil }
        let preference = CloudLibraryPreference(storage: "\(remote):\(path)", enabled: true)
        return preference.remote == remote && preference.root == path ? preference : nil
    }

    public var activation: CloudLibraryPreference? { verified && (!wantsMove || moveCompleted) ? candidate : nil }
}
