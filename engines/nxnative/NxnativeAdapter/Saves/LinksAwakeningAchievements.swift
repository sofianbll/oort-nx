import Foundation
import OortLibrary

public enum LinksAwakeningAchievements {
    // Layout facts: LASRecomp docs/save-format.md (Peiikai, MIT).
    private static let size = 0x5EE0
    private static let polynomial: UInt32 = 0xEDB88320

    public static func readPrimary(from location: SaveLocation) -> [LocalAchievementPack.Metric: Int]? {
        // A secondary nxnative user cannot be attributed to an Arcane profile.
        guard (try? location.validate()) != nil,
              SaveSlot.allCases.filter({ !$0.isLegacy }).allSatisfy({ !SaveFiles.exists(location.directory($0)) })
        else { return nil }
        return read(from: location.directory(.account))
    }

    /// Only the specified committed nxnative account directory. Excludes other users and transaction folders.
    static func read(from directory: URL) -> [LocalAchievementPack.Metric: Int]? {
        var result: [LocalAchievementPack.Metric: Int] = [:]
        for slot in 0...9 {
            let file = directory.appendingPathComponent("savedata\(slot).bin")
            guard let data = try? SaveFiles.readRegular(file, limit: size),
                  let values = decode(data) else { continue }
            for (metric, count) in values { result[metric] = max(count, result[metric] ?? 0) }
        }
        return result.isEmpty ? nil : result
    }

    static func decode(_ data: Data) -> [LocalAchievementPack.Metric: Int]? {
        guard data.count == size else { return nil }
        let bytes = Array(data)
        func integer(_ start: Int, _ count: Int) -> UInt64 {
            (0..<count).reduce(0) { $0 | (UInt64(bytes[start + $1]) << ($1 * 8)) }
        }
        func validChecksum(_ range: Range<Int>, at offset: Int) -> Bool {
            var crc = polynomial
            for i in range {
                crc ^= (offset..<(offset + 4)).contains(i) ? 0 : UInt32(bytes[i])
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : polynomial) }
            }
            return UInt64(crc) == integer(offset, 4)
        }
        guard integer(0, 4) == 0xE,
              validChecksum(0..<0xE0, at: 4), validChecksum(0xE0..<size, at: 0x5EC4) else { return nil }
        let shells = integer(0x5548, 8)
        let pieces = integer(0x5550, 8)
        guard shells >> 50 == 0, pieces >> 32 == 0 else { return nil }
        return [.seashells: shells.nonzeroBitCount, .heartPieces: pieces.nonzeroBitCount]
    }
}
