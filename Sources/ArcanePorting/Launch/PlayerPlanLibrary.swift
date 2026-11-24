import Foundation
import NXLibraryCore

/// A single writer for the active library. A PIN grant is in memory and valid only for the same plan and profile.
public actor PlayerPlanLibrary {
    private let store: PlayerPlanStore
    private var authorizedPlan: PlayerPlan?
    private var authorizedProfiles: [UUID: LocalProfile] = [:]

    public init(url: URL) { store = PlayerPlanStore(url: url) }

    public func load() throws -> PlayerPlan? {
        let plan: PlayerPlan?
        do { plan = try store.load() }
        catch {
            clearAuthorization()
            throw error
        }
        if plan != authorizedPlan { clearAuthorization() }
        return plan
    }

    public func save(_ plan: PlayerPlan) throws {
        try store.save(plan)
        if plan != authorizedPlan { clearAuthorization() }
    }

    public func authorize(_ profile: LocalProfile, pin: String, for plan: PlayerPlan) throws -> Bool {
        guard profile.isLocked, profile.matchesPIN(pin),
              plan.slots.values.contains(where: { $0.profileID == profile.id }), try load() == plan else { return false }
        authorizedPlan = plan
        authorizedProfiles[profile.id] = profile
        return true
    }

    func launchPlan(profiles: [LocalProfile]) throws -> (plan: PlayerPlan?, unlocked: Set<UUID>) {
        let plan = try load()
        return (plan, Set(profiles.filter { authorizedProfiles[$0.id] == $0 }.map(\.id)))
    }

    private func clearAuthorization() {
        authorizedPlan = nil
        authorizedProfiles = [:]
    }
}
