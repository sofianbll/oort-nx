import Foundation
import Combine
import NXLibraryCore

/// Connection IDs have app-session lifetime only. The writer never receives them.
@MainActor final class PlayersScreenSession {
    var confirmed: [Int: String] = [:]
    var unlocked: Set<UUID> = []
    var plan: PlayerPlan?
}

@MainActor final class PlayersScreenModel: ObservableObject {
    enum Page: Equatable {
        case overview, modes, player(Int), profiles(Int), swap(Int), mergeTargets
    }

    enum Row: Hashable {
        case modes, mode(PlayerControllerMode), player(Int), add, reset, retry
        case profiles, assign, identify, swap, remove, profile(UUID?), swapWith(Int), mergeTarget, target(Int)
    }

    struct PinRequest: Identifiable {
        let number: Int
        let profile: LocalProfile
        var id: UUID { profile.id }
    }

    // The app owns its one writer. Tests supply the same three operations on synthetic data.
    let read: () async throws -> PlayerPlan?
    let write: (PlayerPlan) async throws -> Void
    let unlock: (UUID, String, PlayerPlan) async throws -> Bool
    let availableProfiles: () -> [LocalProfile]
    let session: PlayersScreenSession
    let identify: (String) -> Bool
    /// Must lease the raw input upstream of menu arbitration, including held gestures.
    /// A nil result means the host has no exclusive capture connector.
    let leaseCapture: ((@escaping (GameControllerService.AssignmentEvent) -> Void) -> (() -> Void)?)?
    private var releaseCapture: (() -> Void)?
    private var joining: [String] = []

    @Published var page: Page = .overview
    @Published var focus: Row = .modes
    @Published var pin: PinRequest?
    @Published var capturePlayer: Int?
    @Published var confirmsReset = false
    @Published var resetFocus: SeleneConfirmButton = .cancel
    @Published private(set) var plan = PlayerPlan()
    @Published private(set) var pads: [ConnectedController] = []
    @Published private(set) var loading = true
    @Published private(set) var readable = false
    @Published private(set) var saving = false
    @Published private(set) var message: String?
    @Published var supportsExtendedMerge = false
    @Published var showsGameLimits = false
    @Published private var joinedController: String?

    init(session: PlayersScreenSession, read: @escaping () async throws -> PlayerPlan?,
         write: @escaping (PlayerPlan) async throws -> Void,
         unlock: @escaping (UUID, String, PlayerPlan) async throws -> Bool,
         profiles: @escaping () -> [LocalProfile],
         identify: @escaping (String) -> Bool = { _ in false },
         leaseCapture: ((@escaping (GameControllerService.AssignmentEvent) -> Void) -> (() -> Void)?)? = nil) {
        self.session = session
        self.read = read
        self.write = write
        self.unlock = unlock
        self.availableProfiles = profiles
        self.identify = identify
        self.leaseCapture = leaseCapture
    }

    var numbers: [Int] {
        Set(plan.slots.keys).union(plan.mode == .merge ? [mergeTarget] : []).sorted()
    }
    var nextNumber: Int? { (1...PlayerPlan.maximumPlayers).first { plan.slot($0) == nil } }
    var profiles: [LocalProfile] { availableProfiles() }
    var mergeTarget: Int { showsGameLimits && !supportsExtendedMerge ? 1 : plan.mergeTarget }
    var places: ClosedRange<Int> { 1...PlayerPlan.maximumPlayers }
    var joinedPlayer: Int? {
        guard let joinedController else { return nil }
        return resolution.slots.first(where: { $0.value == .connected(joinedController) })?.key
    }

    var rows: [Row] {
        if !readable { return loading ? [] : [.retry] }
        switch page {
        case .overview:
            return [.modes] + (plan.mode == .merge ? [.mergeTarget] : []) + numbers.map(Row.player)
                + (nextNumber == nil ? [] : [.add])
                + (session.plan == nil ? [] : [.reset])
        case .modes:
            return PlayerControllerMode.allCases.map(Row.mode)
        case .player(let number):
            return [.profiles] + (canAssign(number) ? [.assign] : []) + (identifiablePad(number) == nil ? [] : [.identify])
                + (numbers.count > 1 ? [.swap] : []) + [.remove]
        case .profiles:
            return [.profile(nil)] + profiles.map { .profile($0.id) }
        case .swap(let number):
            return numbers.filter { $0 != number }.map(Row.swapWith)
        case .mergeTargets:
            return (1...(supportsExtendedMerge ? PlayerPlan.maximumPlayers : 1)).map(Row.target)
        }
    }

    var focusedRow: Row? { rows.contains(focus) ? focus : rows.first }
    var resolution: PlayerControllerResolution {
        plan.resolveControllers(pads.map { .init(id: $0.id, stableID: $0.stableID, modelKey: $0.modelKey) },
                                confirmed: session.confirmed)
    }

    var hasIdenticalPads: Bool {
        let groups = Dictionary(grouping: pads.filter { $0.modelKey != nil }, by: \.modelKey)
        return groups.values.contains { $0.count > 1 }
    }

    func updatePads(_ pads: [ConnectedController]) {
        let live = Set(pads.map(\.id))
        session.confirmed = session.confirmed.filter { live.contains($0.value) }
        self.pads = pads
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let saved = try await read()
            if saved != session.plan {
                session.confirmed = [:]
                session.unlocked = []
            }
            session.plan = saved
            plan = saved ?? PlayerPlan()
            readable = true
            message = nil
        } catch {
            readable = false
            focus = .retry
            message = "The player setup could not be read. Nothing was changed."
        }
    }

    func profile(for number: Int) -> LocalProfile? {
        plan.slot(number)?.profileID.flatMap { id in profiles.first { $0.id == id } }
    }

    func access(for number: Int) -> PlayerProfileAccess {
        plan.slot(number)?.profileAccess(in: profiles, unlockedProfileIDs: session.unlocked) ?? .guest
    }

    func connectedPad(_ number: Int) -> ConnectedController? {
        guard case .connected(let id) = resolution.slots[number] else { return nil }
        return pads.first { $0.id == id }
    }

    func identifiablePad(_ number: Int) -> ConnectedController? {
        guard let pad = connectedPad(number),
              pad.status.canIdentifyWithLights || pad.status.canIdentifyWithRumble else { return nil }
        return pad
    }

    private func canAssign(_ number: Int) -> Bool {
        plan.mode != .merge && plan.slot(number) != nil && leaseCapture != nil
    }

    func move(_ delta: Int) {
        let rows = self.rows
        guard let current = focusedRow, let index = rows.firstIndex(of: current) else { return }
        var selection = FocusIndex(index: index)
        selection.move(by: delta, count: rows.count)
        focus = rows[selection.index]
    }

    func open(_ page: Page, focus: Row) {
        self.page = page
        self.focus = focus
    }

    func select(_ row: Row) {
        guard !saving, !loading, pin == nil, capturePlayer == nil, !confirmsReset, rows.contains(row) else { return }
        focus = row
        message = nil
        switch (page, row) {
        case (.overview, .modes): open(.modes, focus: .mode(plan.mode))
        case (.overview, .mergeTarget): open(.mergeTargets, focus: .target(mergeTarget))
        case (.mergeTargets, .target(let number)):
            setMergeTarget(number, focus: .mergeTarget)
        case (.overview, .player(let number)): open(.player(number), focus: .profiles)
        case (.overview, .add):
            guard let number = nextNumber else { return }
            edit({ try $0.set(PlayerSlot(), at: number) }, then: { self.focus = .player(number) })
        case (.overview, .reset): resetFocus = .cancel; confirmsReset = true
        case (.overview, .retry): Task { await load() }
        case (.modes, .mode(let mode)):
            setMode(mode, focus: .modes)
        case (.player(let number), .profiles):
            open(.profiles(number), focus: .profile(plan.slot(number)?.profileID))
        case (.player(let number), .identify):
            identifyPlayer(number)
        case (.player(let number), .assign): startCapture(number)
        case (.player(let number), .swap):
            if let other = numbers.first(where: { $0 != number }) { open(.swap(number), focus: .swapWith(other)) }
        case (.player(let number), .remove):
            let target = numbers.first { $0 > number } ?? numbers.last { $0 < number }
            clearPlayer(number, focus: target.map(Row.player) ?? .add)
        case (.profiles(let number), .profile(let id)):
            if let profile = profiles.first(where: { $0.id == id }),
               profile.isLocked, !session.unlocked.contains(profile.id) || plan.slot(number)?.profileID != id {
                pin = .init(number: number, profile: profile)
            } else {
                chooseProfile(id, at: number)
            }
        case (.swap(let number), .swapWith(let other)):
            movePlayer(number, to: other)
        default: break
        }
    }

    func selectMode(_ mode: PlayerControllerMode) {
        guard mode != plan.mode else { return }
        setMode(mode, focus: .mode(mode))
    }

    private func setMode(_ mode: PlayerControllerMode, focus: Row) {
        edit({
            $0.mode = mode
            if mode == .merge, $0.slot(self.mergeTarget) == nil { try $0.set(PlayerSlot(), at: self.mergeTarget) }
        }, then: { self.open(.overview, focus: focus) })
    }

    func chooseProfile(at number: Int) {
        guard !saving, readable, places.contains(number) else { return }
        open(.profiles(number), focus: .profile(plan.slot(number)?.profileID))
    }

    func movePlayer(_ number: Int, to other: Int) {
        guard places.contains(other), number != other, let first = plan.slot(number) else { return }
        let second = plan.slot(other)
        var confirmed = session.confirmed
        confirmed[number] = session.confirmed[other]
        confirmed[other] = session.confirmed[number]
        edit({
            if let second { try $0.set(second, at: number) } else { $0.remove(at: number) }
            try $0.set(first, at: other)
        }, confirmed: confirmed, then: { self.open(.overview, focus: .player(other)) })
    }

    func chooseMergeTarget(_ number: Int) {
        guard !saving, readable, number == 1 || supportsExtendedMerge, places.contains(number),
              plan.mode != .merge || number != mergeTarget else { return }
        setMergeTarget(number, focus: .player(number))
    }

    private func setMergeTarget(_ number: Int, focus: Row) {
        edit({
            $0.mode = .merge
            try $0.setMergePlayer(number)
            if $0.slot(number) == nil { try $0.set(.init(), at: number) }
        }, then: { self.open(.overview, focus: focus) })
    }

    func removePlayer(_ number: Int) {
        guard !saving, readable, plan.slot(number) != nil else { return }
        clearPlayer(number, focus: .player(number))
    }

    private func clearPlayer(_ number: Int, focus: Row) {
        var confirmed = session.confirmed
        confirmed[number] = nil
        edit({
            $0.remove(at: number)
            if $0.mode == .merge, $0.mergeTarget == number { try $0.setMergePlayer(nil) }
        }, confirmed: confirmed, then: { self.open(.overview, focus: focus) })
    }

    func identifyPlayer(_ number: Int) {
        guard let pad = identifiablePad(number) else { return }
        if !identify(pad.id) { message = "This controller did not respond." }
    }

    /// Positional input starts before this hook; only a new pad's press skips navigation.
    func joinController(_ id: String) -> Bool {
        guard readable, !loading, pin == nil, !confirmsReset, capturePlayer == nil,
              plan.mode != .merge, resolution.unassignedControllerIDs.contains(id) else { return false }
        if saving {
            if joining.count < PlayerPlan.maximumPlayers, !joining.contains(id) { joining.append(id) }
            return true
        }
        // An ambiguous reconnect never steals a remembered place. It can be confirmed explicitly on that card.
        guard let pad = pads.first(where: { $0.id == id }),
              pad.stableID.map({ id in !plan.slots.values.contains { $0.controller?.stableID == id } }) != false,
              let number = places.first(where: { plan.slot($0)?.controller == nil }) else { return true }
        assign(id, to: number, joining: true)
        return true
    }

    func stopJoining() { joining.removeAll() }

    private func joinWaitingController() {
        while !saving, !joining.isEmpty { _ = joinController(joining.removeFirst()) }
    }

    func startCapture(_ number: Int) {
        guard canAssign(number), capturePlayer == nil else { return }
        capturePlayer = number
        releaseCapture = leaseCapture? { [weak self] event in
            guard let self else { return }
            switch event {
            case .button(let id):
                self.assign(id, to: number)
                self.endCapture()
            case .cancelled: self.endCapture()
            case .timedOut:
                self.endCapture()
                self.message = "No button was pressed. Try assigning the controller again."
            }
        }
        if releaseCapture == nil {
            capturePlayer = nil
            message = "Controller assignment is unavailable right now."
        }
    }

    func endCapture() {
        releaseCapture?()
        releaseCapture = nil
        capturePlayer = nil
    }

    private func assign(_ id: String, to number: Int, joining: Bool = false) {
        guard (joining || capturePlayer == number), !saving,
              let pad = pads.first(where: { $0.id == id }) else { return }
        var slot = plan.slot(number) ?? .init()
        let current = resolution.slots
        let previous = joining ? [] : numbers.filter { candidate in
            current[candidate] == .connected(id) ||
                (pad.stableID != nil && plan.slot(candidate)?.controller?.stableID == pad.stableID)
        }
        let remembered = slot.controller
        let sameAssociation = previous.contains(number) && remembered?.stableID == pad.stableID && remembered?.modelKey == pad.modelKey
        if !sameAssociation { slot.controller = .init(stableID: pad.stableID, modelKey: pad.modelKey) }
        var confirmed = session.confirmed.filter { $0.value != id }
        confirmed[number] = id
        edit({ draft in
            for previous in previous where previous != number {
                guard var oldSlot = draft.slot(previous) else { continue }
                oldSlot.controller = nil
                try draft.set(oldSlot, at: previous)
            }
            try draft.set(slot, at: number)
        }, confirmed: confirmed, then: {
            if joining { self.joinedController = id }
            else { self.open(.overview, focus: .player(number)) }
        })
    }

    func submitPIN(_ code: String) -> String? {
        guard let request = pin,
              let profile = profiles.first(where: { $0.id == request.profile.id }),
              profile.isLocked, profile.matchesPIN(code) else { return "Incorrect code." }
        pin = nil
        chooseProfile(profile.id, at: request.number, pin: code)
        return nil
    }

    private func chooseProfile(_ id: UUID?, at number: Int, pin: String? = nil) {
        var slot = plan.slot(number) ?? PlayerSlot()
        slot.profileID = id
        edit({ try $0.set(slot, at: number) }, unlock: id.flatMap { id in pin.map { (id, $0) } }, then: {
            self.open(.overview, focus: .player(number))
        })
    }

    func reset() {
        guard confirmsReset else { return }
        confirmsReset = false
        edit({ $0 = PlayerPlan() }, confirmed: [:], then: { self.focus = .modes })
    }

    /// False only when Back belongs to the enclosing Settings or Game options.
    func back() -> Bool {
        if capturePlayer != nil { endCapture(); return true }
        if pin != nil { pin = nil; return true }
        if confirmsReset { confirmsReset = false; return true }
        if saving { return true }
        switch page {
        case .overview: return false
        case .modes: open(.overview, focus: .modes)
        case .player(let number): open(.overview, focus: .player(number))
        case .profiles(let number): open(.player(number), focus: .profiles)
        case .swap(let number): open(.player(number), focus: .swap)
        case .mergeTargets: open(.overview, focus: .mergeTarget)
        }
        return true
    }

    private func edit(_ change: (inout PlayerPlan) throws -> Void, confirmed: [Int: String]? = nil,
                      unlock: (UUID, String)? = nil, then: @escaping () -> Void) {
        guard readable, !saving else { return }
        var draft = plan
        do { try change(&draft) } catch { assertionFailure("Invalid player slot"); return }
        message = nil
        saving = true
        Task {
            defer {
                saving = false
                joinWaitingController()
            }
            do {
                if session.plan != draft {
                    try await write(draft)
                    session.unlocked = []
                    session.plan = draft
                }
                let live = Set(pads.map(\.id))
                session.confirmed = (confirmed ?? session.confirmed).filter { live.contains($0.value) }
                plan = draft
                if let (id, code) = unlock {
                    if try await self.unlock(id, code, draft) {
                        session.unlocked.insert(id)
                    } else {
                        message = "The profile is still locked."
                    }
                }
                then()
            } catch PlayerPlanStore.InvalidDocument.commitUncertain {
                await load()
                open(.overview, focus: .modes)
                message = readable ? "Check the player setup before trying again." : message
            } catch {
                message = "The player setup could not be saved."
            }
        }
    }
}
