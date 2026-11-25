import Foundation

enum InstallationFileReadError: Error { case tooLarge, unsafeFile, sourceChanged, invalidText }

/// Retain only this small identity after parsing, not all source-file contents.
/// Taking and re-checking an observation needs POSIX file status: see `InstallationFileSnapshot.swift`.
struct InstallationFileObservation: Equatable, Sendable {
    let url: URL
    let identity: Identity?
    /// The file-type bits of the status word (`S_IFMT`), 0 for a file that was absent.
    let fileType: UInt32

    struct Identity: Equatable, Sendable {
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
    }

    init(url: URL, identity: Identity?, fileType: UInt32) {
        self.url = url
        self.identity = identity
        self.fileType = fileType
    }

    init(absentURL: URL) { url = absentURL; identity = nil; fileType = 0 }
    var byteCount: Int64 { identity?.size ?? 0 }
}
