import Foundation

/// The two folders last used with a Drive account. Signing out keeps them, so signing in again proposes the same ones.
public struct CloudKeptFolders: Codable, Equatable, Sendable {
    public static let preferenceKey = "NXLibrary_CloudKeptFolders"
    /// nil when the account was never identified: the folders are then proposed only if their games are found again.
    public let account: String?
    public let library: String
    /// nil for the library's own GameFiles folder.
    public let sources: String?

    public init(account: String?, library: String, sources: String?) {
        self.account = account
        self.library = library
        self.sources = sources
    }

    /// Another account's folders are never proposed, even under the same path.
    public func applying(to current: String?) -> CloudKeptFolders? {
        guard let account else { return self }
        return account == current ? self : nil
    }
}
