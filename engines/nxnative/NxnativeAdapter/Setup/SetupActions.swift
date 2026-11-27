import Foundation
import OortLibrary

public enum EngineAction: Equatable {
    case clone, checkout, none
}

/// The commands behind the Setup check's automatic cards, as argv lists so a
/// path with spaces stays one argument.
public enum SetupActions {
    public static let engineRemote = "https://github.com/seedds/nxnative"

    /// A release may override both values together; a partial or malformed plist uses the upstream defaults.
    public static func engineOverride(in info: [String: Any]?) -> (remote: String, commit: String)? {
        guard let remote = info?["NXLibraryEngineRepository"] as? String,
              remote.range(of: #"\Ahttps://github\.com/[A-Za-z0-9_-]+/[A-Za-z0-9_-][A-Za-z0-9_.-]*\z"#,
                           options: .regularExpression) != nil,
              let commit = info?["NXLibraryEngineCommit"] as? String,
              commit.range(of: #"\A[0-9a-f]{40}\z"#, options: .regularExpression) != nil else { return nil }
        return (remote, commit)
    }

    /// Only a missing engine or a clean checkout at another commit is changed;
    /// local changes are the player's and stay untouched, and so is the newest engine the player chose.
    public static func engineAction(for facts: EngineCheckout, pinned: String, newest: String? = nil) -> EngineAction {
        switch facts {
        case .missing: return .clone
        case .checkout(let head, _, .clean) where head == newest: return .none
        case .checkout(let head, _, .clean) where head != pinned: return .checkout
        default: return .none
        }
    }

    /// Arguments for /usr/bin/git, run in order.
    public static func gitCommands(for action: EngineAction, folder: URL, pinned: String,
                                   remote: String? = nil) -> [[String]] {
        let path = folder.path
        switch action {
        case .clone:
            return [["clone", "--progress", remote ?? engineRemote, path], ["-C", path, "checkout", "--detach", pinned]]
        case .checkout:
            return [["-C", path, "fetch", "--progress"] + fetchSource(remote: remote, commit: pinned),
                    ["-C", path, "checkout", "--detach", pinned]]
        case .none:
            return []
        }
    }

    /// An override fetches the exact object without replacing the player's origin or any local branch.
    static func fetchSource(remote: String?, commit: String) -> [String] {
        remote.map { [$0, commit] } ?? ["origin"]
    }
}
