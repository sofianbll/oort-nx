import Foundation

/// The tour's optional services (OnboardingView), decided once from their owners' facts: each says whether it is set
/// up, and A takes the player where it is set up. Nothing is asked of an owner there: the tour opens the place.
public enum OptionalServiceEntries {
    /// A service and where it is set up: a section of Settings, on one of its rows or at its top.
    public struct Service: Equatable, Sendable {
        public let entry: IntegrationEntry
        public let section: SettingsSection
        public let row: String?

        public init(_ entry: IntegrationEntry, section: SettingsSection, row: String? = nil) {
            (self.entry, self.section, self.row) = (entry, section, row)
        }
    }

    /// In the tour's order. Steam's is SteamSourceEntries.tour.
    public static func all(driveConnected: Bool, nextendoSignedIn: Bool, steamInForce: Bool, savesOn: Bool) -> [Service] {
        [
            .init(entry("drive", "Google Drive", "Connect your cloud library.", .cloud, setUp: driveConnected), section: .cloudLibrary),
            .init(entry("nextendo", "Nextendo", "Connect an account for online play.", .gamepad, setUp: nextendoSignedIn),
                  section: .profileNextendo),
            SteamSourceEntries.tour(inForce: steamInForce),
            .init(entry("saves", "Save copies", "Choose if and where to sync ported-game saves.", .sync, setUp: savesOn),
                  section: .cloudSaves),
        ]
    }

    /// A service as the tour says it: set up, or for later.
    static func entry(_ id: String, _ title: String, _ about: String, _ icon: MaterialIcon, setUp: Bool) -> IntegrationEntry {
        IntegrationEntry(id: id, title: .init(title), about: .init(about), value: .init(setUp ? "Enabled" : "Later"),
                         icon: icon.rawValue, control: .row, request: nil)
    }
}
