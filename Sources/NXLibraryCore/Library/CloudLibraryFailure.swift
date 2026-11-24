import Foundation

/// Safe cloud recovery information. Never retain rclone output: OAuth errors can contain secrets.
public enum CloudLibraryFailure: LocalizedError, Hashable, Sendable {
    case offline, authentication, folderMissing, quotaFull, macFull, queueNotSaved, unavailable, requiresDrive, incomplete, scopeChanged
    case volumeFull(String)

    public enum Action: Equatable, Sendable {
        case retry, reconnect, chooseFolder, manageDriveStorage, freeMacStorage, dismiss

        public var titleKey: String {
            switch self {
            case .retry: return "Retry"
            case .reconnect: return "Reconnect"
            case .chooseFolder: return "Choose a folder"
            case .manageDriveStorage: return "Manage Google storage"
            case .freeMacStorage: return "Open Storage"
            case .dismiss: return "Close"
            }
        }
    }

    public var action: Action {
        switch self {
        case .offline, .unavailable, .incomplete: return .retry
        case .authentication: return .reconnect
        case .folderMissing, .scopeChanged: return .chooseFolder
        case .quotaFull: return .manageDriveStorage
        case .macFull, .volumeFull: return .freeMacStorage
        case .queueNotSaved, .requiresDrive: return .dismiss
        }
    }

    public var messageKey: String {
        switch self {
        case .offline: return "Offline — Google Drive is unreachable."
        case .authentication: return "Google Drive sign-in expired or was revoked."
        case .folderMissing: return "Cloud folder not found."
        case .quotaFull: return "Google Drive is full."
        case .macFull, .volumeFull: return "Not enough space on this Mac."
        case .queueNotSaved: return "The cloud queue could not be saved. Transfers continue, but may not resume after quitting."
        case .unavailable: return "Cloud storage is unavailable. Check rclone and try again."
        case .requiresDrive: return "Choose a Google Drive connection configured directly in rclone."
        case .incomplete: return "The cloud check is incomplete. Previous results were kept."
        case .scopeChanged: return "The Google Drive account or folder changed. Check the cloud settings."
        }
    }

    public func message(context: AppLocale = L10n.context) -> String {
        if case .volumeFull(let name) = self {
            return L10n.format("Not enough space on %@.", [name], context: context)
        }
        return L10n.text(messageKey, context: context)
    }

    public var errorDescription: String? { message() }

    package static func diskFull(at destination: URL?) -> Self {
        guard var url = destination, url.isFileURL else { return .macFull }
        while true {
            if let name = (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName,
               !name.isEmpty { return .volumeFull(name) }
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path, !parent.path.isEmpty else { return .macFull }
            url = parent
        }
    }

    package static func localWriteFailure(_ error: Error, at destination: URL?) -> Self? {
        let ns = error as NSError
        let location = (ns.userInfo[NSFilePathErrorKey] as? String).flatMap {
            $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil
        } ?? destination
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(POSIXErrorCode.ENOSPC.rawValue)
            || ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return diskFull(at: location)
        }
        return (ns.userInfo[NSUnderlyingErrorKey] as? Error).flatMap { localWriteFailure($0, at: location) }
    }

    package static func rclone(_ stderr: String, status: Int32, listingFolder: Bool = false) -> Self? {
        let text = stderr.lowercased()
        func contains(_ markers: String...) -> Bool { markers.contains { text.contains($0) } }
        if contains("invalid_grant", "token expired", "token has expired", "token is expired", "token has been revoked",
                    "token revoked", "error 401", "401 unauthorized", "status code: 401", #"\"code\": 401"#) {
            return .authentication
        }
        if contains("storagequotaexceeded", "storage quota", "drive is full")
            || (text.contains("403") && text.contains("quota")
                && !contains("rate limit", "ratelimit", "downloadquota", "daily limit", "dailyquota")) {
            return .quotaFull
        }
        if contains("no space left on device", "no space left", "enospc") { return .macFull }
        if contains("no such host", "network is unreachable", "network is down", "no route to host", "host is down",
                    "not connected to the internet", "connection refused", "connection reset",
                    "i/o timeout", "context deadline exceeded", "tls handshake timeout",
                    "temporary failure in name resolution", "error 502", "error 503", "error 504") {
            return .offline
        }
        if contains("error 403", "403 forbidden", "ratelimitexceeded") { return .unavailable }
        if listingFolder && (status == 3 || status == 4 || text.contains("directory not found")) { return .folderMissing }
        return nil
    }
}
