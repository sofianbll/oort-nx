import Foundation

/// The tour's optional services (OnboardingView), decided once from their owners' facts: each says whether it is set
/// up, and A takes the player where it is set up. Nothing is asked of an owner: the tour opens a place of Settings.
public enum OptionalServiceEntries {
    /// A service, what the tour says of it, and where it is set up: a section of Settings, on one of its rows or at its top.
    public struct Service: Equatable, Sendable {
        public let id: String
        public let title: IntegrationWords
        public let about: IntegrationWords
        /// Enabled or Later.
        public let value: IntegrationWords
        public let icon: MaterialIcon
        public let section: SettingsSection
        public let row: String?
    }

    /// In the tour's order.
    public static func all(driveConnected: Bool, nextendoSignedIn: Bool, steamInForce: Bool, savesOn: Bool) -> [Service] {
        [
            service("drive", "Google Drive", "Connect your cloud library.", .cloud, setUp: driveConnected, opens: .cloudLibrary),
            service("nextendo", "Nextendo", "Connect an account for online play.", .gamepad, setUp: nextendoSignedIn, opens: .profileNextendo),
            // Set up while its source is in force; Sources opens on the source's switch.
            service("steam", "Steam", "Read your installed Mac games from Steam.", .store, setUp: steamInForce, opens: .sources,
                    row: SteamSourceEntries.sourceRowID),
            service("saves", "Save copies", "Choose if and where to sync ported-game saves.", .sync, setUp: savesOn, opens: .cloudSaves),
        ]
    }

    private static func service(_ id: String, _ title: String, _ about: String, _ icon: MaterialIcon, setUp: Bool,
                                opens section: SettingsSection, row: String? = nil) -> Service {
        Service(id: id, title: .init(title), about: .init(about), value: .init(setUp ? "Enabled" : "Later"), icon: icon,
                section: section, row: row)
    }
}
