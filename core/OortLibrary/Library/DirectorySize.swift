import Foundation

/// The bytes of a folder's regular files, hidden files and folders skipped. One lstat per entry, as `du` does
/// (`OortSystem.regularFileBytes`, fts on a Mac): a large game app on a USB drive has hundreds of thousands of files,
/// and asking each URL for its resource values took minutes there (issue #2).
public enum DirectorySize {
    public static func bytes(at url: URL) -> Int64 {
        bytes(at: url, includingHidden: false)
    }

    package static func bytes(at url: URL, includingHidden: Bool) -> Int64 {
        url.withUnsafeFileSystemRepresentation { path in
            path.map { OortSystem.regularFileBytes(at: String(cString: $0), includingHidden: includingHidden) } ?? 0
        }
    }
}
