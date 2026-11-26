import Foundation

/// Platform adapters prepare a catalog target. Only the engine can give them a gesture to submit.
@MainActor package protocol PlayAdapter {
    var source: CatalogIntegration { get }
    func availability(of target: PlayTarget) -> PlayAvailability
    func artifact(of target: PlayTarget) -> String?
    func admit(_ target: PlayTarget, profile: PlayProfile, gesture: PlayGesture) -> PlayResult
}

extension PlayAdapter {
    package func artifact(of target: PlayTarget) -> String? { target.installation?.id }
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
                      observe: PlayFactObserver? = nil) -> PlayReceipt {
        func refusal(_ reason: PlayRefusal) -> PlayReceipt { PlayReceipt(request, .refused(reason)) }
        let selected = target.flatMap { adapter(for: $0.game.integration) }
        let input = PlayJournal.Input(game: target?.game.id, source: target?.game.integration.rawValue,
                                      installation: target?.installation?.id, profile: profile,
                                      available: target?.installationAvailability, resumeOnly: target?.resumeOnly,
                                      artifact: target.flatMap { selected?.artifact(of: $0) })
        if let gesture = gestures[request]?.gesture {
            return gesture.input == input ? gesture.replay(to: observe) : refusal(.stale)
        }
        do {
            if let saved = try journal.read(request) {
                guard saved.input == input else { return refusal(.stale) }
                if let scope = saved.scope, journal.held(scope) { return refusal(.outcomeUnknown) }
                if saved.admission == nil || saved.admission == .accepted(.pending) && saved.facts.isEmpty {
                    return refusal(.outcomeUnknown)
                }
                saved.facts.forEach { observe?($0) }
                return PlayReceipt(request, saved.admission!, run: saved.admissionRun.map(RunRef.init))
            }
            let gesture = PlayGesture(request, input: input, journal: journal, observe: observe)
            gesture.register()
            gestures = gestures.filter { $0.value.gesture != nil }
            gestures[request] = Live(gesture: gesture)
            let admission: PlayResult
            if let target {
                admission = selected?.admit(target, profile: profile, gesture: gesture) ?? .refused(.unsupportedSource)
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
    private var observers: [PlayFactObserver]
    private var receipt: PlayReceipt?
    private var writes: Task<Bool, Never>?
    private var deliveries: Task<Void, Never>?
    private var run: RunRef?

    fileprivate init(_ request: RequestID, input: PlayJournal.Input, journal: PlayJournal, observe: PlayFactObserver?) {
        self.request = request
        self.record = .init(input: input)
        self.journal = journal
        self.observers = observe.map { [$0] } ?? []
    }

    fileprivate func register() { save(replacing: false) }

    fileprivate func admit(_ result: PlayResult) -> PlayReceipt {
        record.admission = result
        record.admissionRun = run?.id
        save()
        let result = PlayReceipt(request, result, run: run)
        receipt = result
        return result
    }

    fileprivate func replay(to observe: PlayFactObserver?) -> PlayReceipt {
        if let observe {
            record.facts.forEach(observe)
            if record.facts.last?.event != .exited { observers.append(observe) }
        }
        return receipt ?? PlayReceipt(request, .accepted(.pending))
    }

    /// This is called at submission, not when a cover or a request for confirmation is displayed.
    package func reserve(_ scope: String) async -> PlayRefusal? {
        guard record.scope == nil else { return .outcomeUnknown }
        record.scope = scope
        let accepted = await persist { journal, record, request in
            try journal.claim(scope, for: request)
            do { try journal.write(record, for: request) }
            catch {
                // No request was sent. It is safe to undo our own claim.
                try? journal.release(scope, for: request)
                throw error
            }
        }.value
        if !accepted { record.scope = nil }
        return accepted ? nil : .outcomeUnknown
    }

    package func hasUnsettledHandoff(_ scope: String) -> Bool { journal.held(scope) }

    package var hasSubmitted: Bool { record.scope != nil }
    package func reported(_ event: PlayEvent) -> Bool { record.facts.contains { $0.event == event } }

    package func acceptResume(run: RunRef?) { self.run = run }

    package func backedByJournal() async -> Bool {
        let written = await writes?.value ?? false
        await deliveries?.value
        return written
    }

    package func emit(_ event: PlayEvent) {
        let fact = append(event)
        publish(fact, after: save())
    }

    /// Only a definitive response to the effect can release the native reservation.
    package func finish(_ result: PlayResult, run: RunRef? = nil,
                        afterSettled: @escaping @MainActor () -> Void = {}) {
        self.run = run
        let fact = append(.result(result))
        let scope = record.scope
        record.scope = nil
        let job = persist { journal, record, request in
            try journal.write(record, for: request)
            if let scope { try journal.release(scope, for: request) }
        }
        publish(fact, after: job, settled: afterSettled)
    }

    private func append(_ event: PlayEvent) -> PlayFact {
        let fact = PlayFact(sequence: record.facts.count + 1, event: event, run: run)
        record.facts.append(fact)
        return fact
    }

    private func publish(_ fact: PlayFact, after job: Task<Bool, Never>, settled: @escaping @MainActor () -> Void = {}) {
        let previous = deliveries
        deliveries = Task {
            await previous?.value
            _ = await job.value
            settled()
            for observe in observers { observe(fact) }
            if fact.event == .exited { observers.removeAll() }
        }
    }

    @discardableResult private func save(replacing: Bool = true) -> Task<Bool, Never> {
        persist { try $0.write($1, for: $2, replacing: replacing) }
    }

    @discardableResult private func persist(
        _ operation: @escaping @Sendable (PlayJournal, PlayJournal.Record, RequestID) throws -> Void
    ) -> Task<Bool, Never> {
        let previous = writes
        let job = Task.detached { [journal, record, request] in
            if let previous, !(await previous.value) { return false }
            do { try operation(journal, record, request); return true }
            catch { return false }
        }
        writes = job
        // An immediate replay must see this gesture until its receipt is on disk.
        Task { _ = await job.value; withExtendedLifetime(self) {} }
        return job
    }
}

fileprivate struct PlayJournal: Sendable {
    struct Input: Equatable, Codable, Sendable {
        let game: UUID?
        let source: String?
        let installation: String?
        let profile: PlayProfile
        let available: PlayAvailability?
        let resumeOnly: Bool?
        let artifact: String?
    }

    struct Record: Codable, Sendable {
        let input: Input
        var admission: PlayResult?
        var admissionRun: UUID?
        var scope: String?
        var facts: [PlayFact] = []
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
