import Foundation
import OortLibrary

/// A single writer for the active library. A PIN grant is in memory and valid only for the same plan and profile.
public actor PlayerPlanLibrary {
    public struct DraftAuthorization {
        fileprivate let profile: LocalProfile
        fileprivate let plan: PlayerPlan

        public init?(profile: LocalProfile, pin: String, plan: PlayerPlan) {
            guard profile.isLocked, profile.matchesPIN(pin),
                  plan.slots.values.contains(where: { $0.profileID == profile.id }) else { return nil }
            self.profile = profile
            self.plan = plan
        }
    }
    private let store: PlayerPlanStore
    private var authorizedPlan: PlayerPlan?
    private var authorizedProfiles: [UUID: LocalProfile] = [:]

    public init(url: URL) { store = PlayerPlanStore(url: url) }

    public func load(committed: PlayerPlan? = nil) throws -> PlayerPlan? {
        let plan: PlayerPlan?
        do { plan = try committed ?? store.load() }
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

    public func authorize(_ profile: LocalProfile, pin: String, for plan: PlayerPlan,
                          committed: PlayerPlan? = nil) throws -> Bool {
        guard profile.isLocked, profile.matchesPIN(pin),
              plan.slots.values.contains(where: { $0.profileID == profile.id }), try load(committed: committed) == plan else { return false }
        authorizedPlan = plan
        authorizedProfiles[profile.id] = profile
        return true
    }

    public func accept(_ grants: [DraftAuthorization], committed: PlayerPlan, profiles: [LocalProfile]) {
        if authorizedPlan != committed { clearAuthorization() }
        for grant in grants where grant.plan == committed && profiles.contains(grant.profile) {
            authorizedPlan = committed
            authorizedProfiles[grant.profile.id] = grant.profile
        }
    }

    func launchPlan(profiles: [LocalProfile], committed: PlayerPlan? = nil) throws -> (plan: PlayerPlan?, unlocked: Set<UUID>) {
        let plan = try load(committed: committed)
        return (plan, Set(profiles.filter { authorizedProfiles[$0.id] == $0 }.map(\.id)))
    }

    private func clearAuthorization() {
        authorizedPlan = nil
        authorizedProfiles = [:]
    }
}
