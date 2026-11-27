import Foundation

extension FileHandle {
    /// Reads to the end in `size`-byte chunks. Each chunk is released before the next read: a plain
    /// `while let read(upToCount:)` loop keeps every autoreleased chunk until the loop ends, so hashing a
    /// 79 GB shader cache held tens of GB of memory.
    package func forEachChunk(_ size: Int = 1 << 20, _ body: (Data) throws -> Void) throws {
        while try autoreleasepool(invoking: {
            guard let chunk = try read(upToCount: size), !chunk.isEmpty else { return false }
            try body(chunk)
            return true
        }) {}
    }
}
