import Foundation

/// Platform adapters prepare a catalog target. Only the engine can give them a gesture to submit.
@MainActor package protocol PlayAdapter {
    var source: CatalogIntegration { get }
    func availability(of target: PlayTarget) -> PlayAvailability
    func admit(_ target: PlayTarget, profile: PlayProfile, gesture: PlayGesture) -> PlayResult
}

@MainActor package final class PlayEngine {
    private struct Live {
        weak var gesture: PlayGesture?
    }

    private let adapters: [any PlayAdapter]
    private let journal: PlayJournal
    private var gestures: [RequestID: Live] = [:]

    package init(_ adapters: [any PlayAdapter], directory: URL = AppData.supportRoot.appendingPathComponent("PlayRequests")) {
        self.adapters = adapters
        journal = PlayJournal(directory: directory)
    }

    package func supports(_ source: CatalogIntegration) -> Bool { adapter(for: source) != nil }

    package func availability(of target: PlayTarget?) -> PlayAvailability {
        guard let target else { return .unavailable(.missingTarget) }
        return adapter(for: target.game.integration)?.availability(of: target) ?? .unavailable(.unsupportedSource)
    }

    package func play(_ target: PlayTarget?, profile: PlayProfile, request: RequestID,
                      observe: PlayObserver? = nil) -> PlayReceipt {
        func refusal(_ reason: PlayRefusal) -> PlayReceipt { PlayReceipt(request, .refused(reason)) }
        let input = PlayJournal.Input(game: target?.game.id, source: target?.game.integration.rawValue,
                                      installation: target?.installation?.id, profile: profile,
                                      available: target?.installationAvailability, resumeOnly: target?.resumeOnly)
        if let gesture = gestures[request]?.gesture {
            return gesture.input == input ? gesture.replay(to: observe) : refusal(.stale)
        }
        do {
            if let saved = try journal.read(request) {
                guard saved.input == input else { return refusal(.stale) }
                if saved.scope != nil || saved.admission == nil ||
                    saved.admission == .accepted(.pending) && saved.events.isEmpty {
                    return refusal(.outcomeUnknown)
                }
                saved.events.forEach { observe?($0) }
                return PlayReceipt(request, saved.admission!)
            }
            let gesture = PlayGesture(request, input: input, journal: journal, observe: observe)
            try gesture.register()
            gestures = gestures.filter { $0.value.gesture != nil }
            gestures[request] = Live(gesture: gesture)
            let admission: PlayResult
            if let target {
                admission = adapter(for: target.game.integration)?.admit(target, profile: profile, gesture: gesture)
                    ?? .refused(.unsupportedSource)
            } else {
                admission = .refused(.missingTarget)
            }
            return gesture.admit(admission)
        } catch {
            return refusal(.outcomeUnknown)
        }
    }

    private func adapter(for source: CatalogIntegration) -> (any PlayAdapter)? {
        let matches = adapters.filter { $0.source == source }
        return matches.count == 1 ? matches.first : nil
    }
}

/// An adapter can prepare or resume the gesture, but it cannot bypass the durable claim at its handoff.
@MainActor package final class PlayGesture {
    package let request: RequestID
    package let startedAt = Date()
    fileprivate var input: PlayJournal.Input { record.input }
    private var record: PlayJournal.Record
    private let journal: PlayJournal
    private var observers: [PlayObserver]
    private var receipt: PlayReceipt?

    fileprivate init(_ request: RequestID, input: PlayJournal.Input, journal: PlayJournal, observe: PlayObserver?) {
        self.request = request
        self.record = .init(input: input)
        self.journal = journal
        self.observers = observe.map { [$0] } ?? []
    }

    fileprivate func register() throws { try journal.write(record, for: request, replacing: false) }

    fileprivate func admit(_ result: PlayResult) -> PlayReceipt {
        record.admission = result
        let accepted = (try? journal.write(record, for: request)) != nil
        let result = PlayReceipt(request, accepted ? result : .refused(.outcomeUnknown))
        receipt = result
        return result
    }

    fileprivate func replay(to observe: PlayObserver?) -> PlayReceipt {
        if let observe {
            record.events.forEach(observe)
            if record.events.last != .exited { observers.append(observe) }
        }
        return receipt ?? PlayReceipt(request, .accepted(.pending))
    }

    /// This is called at submission, not when a cover or a request for confirmation is displayed.
    package func reserve(_ scope: String) -> PlayRefusal? {
        guard record.scope == nil else { return .outcomeUnknown }
        do {
            try journal.claim(scope, for: request)
            record.scope = scope
            try journal.write(record, for: request)
            return nil
        } catch { return .outcomeUnknown }
    }

    package func hasUnsettledHandoff(_ scope: String) -> Bool { journal.held(scope) }

    package func emit(_ event: PlayEvent) {
        record.events.append(event)
        try? journal.write(record, for: request)
        for observe in observers { observe(event) }
        if event == .exited { observers.removeAll() }
    }

    /// Only a definitive response to the effect can release the native reservation.
    package func finish(_ result: PlayResult) {
        guard let scope = record.scope else { emit(.result(result)); return }
        record.events.append(.result(result))
        do {
            try journal.write(record, for: request)
            try journal.release(scope, for: request)
            record.scope = nil
            try journal.write(record, for: request)
        } catch {
            // The effect already happened (or was refused). Do not send it again to repair a receipt.
        }
        for observe in observers { observe(.result(result)) }
    }
}

fileprivate struct PlayJournal {
    struct Input: Equatable, Codable {
        let game: UUID?
        let source: String?
        let installation: String?
        let profile: PlayProfile
        let available: PlayAvailability?
        let resumeOnly: Bool?
    }

    struct Record: Codable {
        let input: Input
        var admission: PlayResult?
        var scope: String?
        var events: [PlayEvent] = []
    }

    let directory: URL

    func read(_ request: RequestID) throws -> Record? {
        do {
            let bytes = try InstallationFileSnapshot.read(at: location(request), maximumBytes: 64 * 1024).data
            return try JSONDecoder().decode(Record.self, from: bytes)
        } catch let error as POSIXError where error.code == .ENOENT {
            return nil
        }
    }

    func write(_ record: Record, for request: RequestID, replacing: Bool = true) throws {
        try publish(JSONEncoder().encode(record), to: location(request), replacing: replacing)
    }

    func claim(_ scope: String, for request: RequestID) throws {
        try publish(Data(request.id.uuidString.utf8), to: lock(scope), replacing: false)
    }

    func release(_ scope: String, for request: RequestID) throws {
        let url = try lock(scope)
        guard try InstallationFileSnapshot.read(at: url, maximumBytes: 64).data == Data(request.id.uuidString.utf8)
        else { throw POSIXError(.ESTALE) }
        try FileManager.default.removeItem(at: url)
        try CatalogPublication.synchronize(directory)
    }

    func held(_ scope: String) -> Bool {
        do {
            _ = try InstallationFileSnapshot.read(at: lock(scope), maximumBytes: 64)
            return true
        } catch let error as POSIXError where error.code == .ENOENT { return false }
        catch { return true }
    }

    private func location(_ request: RequestID) -> URL { directory.appendingPathComponent(request.id.uuidString + ".json") }

    private func lock(_ scope: String) throws -> URL {
        guard !scope.isEmpty, scope.utf8.count <= 100,
              scope.utf8.allSatisfy({ $0 == 45 || (48...57).contains($0) || (97...122).contains($0) })
        else { throw POSIXError(.EINVAL) }
        return directory.appendingPathComponent(scope + ".held")
    }

    private func publish(_ bytes: Data, to url: URL, replacing: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let stage = try CatalogPublication.stage(bytes, in: directory)
        defer { try? FileManager.default.removeItem(at: stage) }
        try CatalogPublication.atomic.publish(stage, url, replacing, {})
        try CatalogPublication.synchronize(directory)
    }
}
