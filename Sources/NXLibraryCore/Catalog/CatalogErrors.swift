import Foundation

public enum CatalogStoreError: Error, Equatable {
    case invalidLegacy, invalidCatalog(backupAvailable: Bool), legacyChanged, staleRevision, busy, unsafeDirectory
    /// Main may already contain the new revision. Reload before deciding whether to retry.
    case commitUncertain
}
