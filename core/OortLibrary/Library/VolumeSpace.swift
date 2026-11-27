import Foundation

/// The free space of a drive. macOS answers 0 for "important usage" on drives that are not APFS (exFAT, FAT32), where
/// nothing can be purged: the plain figure is the right one there. Idea from NX2Apple (MIT, LNPANDY), `BuildSpace.swift`.
public enum VolumeSpace {
    /// On the volume of `url`, or of its nearest existing parent. Nil: unknown.
    public static func free(at url: URL) -> Int64? {
        var existing = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" { existing.deleteLastPathComponent() }
        let values = try? existing.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        return best(important: values?.volumeAvailableCapacityForImportantUsage, plain: values?.volumeAvailableCapacity.map(Int64.init))
    }

    static func best(important: Int64?, plain: Int64?) -> Int64? {
        if let important, important > 0 { return important }
        return plain ?? important
    }
}
