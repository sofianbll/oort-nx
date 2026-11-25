import Foundation

/// A settings toggle is not new consent to use another Drive connection.
public struct CloudLibraryActivation: Codable, Equatable, Sendable {
    public let storage: String
    public let connection: String?
    public let wasEnabled: Bool
    public let enabled: Bool

    public init?(_ base: CloudLibraryPreference, connection: String?, enabled: Bool) {
        guard base.remote != nil, let storage = base.storage else { return nil }
        self.storage = storage
        self.connection = connection
        self.wasEnabled = base.enabled
        self.enabled = enabled
    }

    public func applying(to base: CloudLibraryPreference, connection: String?) -> CloudLibraryPreference {
        guard base.remote != nil, base.storage == storage, self.connection == connection, base.enabled == wasEnabled else { return base }
        return CloudLibraryPreference(storage: base.storage, enabled: enabled, sourcesRoot: base.sourcesRootOverride,
                                      referenceFolder: base.referenceFolder)
    }
}
