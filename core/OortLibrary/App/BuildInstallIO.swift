import Foundation

public enum BuildInstallError: Error, LocalizedError {
    case invalidApp(String)
    case replaceFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidApp(let p): return L10n.format("The built app is invalid: %@", [String(describing: p)])
        case .replaceFailed(let m): return L10n.format("Could not replace the app: %@", [String(describing: m)])
        }
    }
}

/// Filesystem boundary for failure and cross-volume tests. Public: the engine adapter and the Mac app's update both
/// install through it.
public struct BuildInstallIO {
    public init() {}
    public var sameVolume: (URL, URL) throws -> Bool = { source, parent in
        var sourceInfo = stat(), parentInfo = stat()
        guard stat(source.path, &sourceInfo) == 0, stat(parent.path, &parentInfo) == 0 else {
            throw BuildInstallError.replaceFailed("Could not inspect the destination volume.")
        }
        return sourceInfo.st_dev == parentInfo.st_dev
    }
    public var publish: (URL, URL, Bool) throws -> Void = { source, destination, replacing in
        guard OortSystem.rename(source.path, destination.path, replacing ? .swap : .noReplace) == 0 else {
            throw BuildInstallError.replaceFailed(String(cString: strerror(errno)))
        }
    }
    public var afterPublish: () throws -> Void = {}
}
