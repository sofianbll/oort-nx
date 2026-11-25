import Foundation
import OortCore

/// The cloud library in the player's words. No address, no identifier, no code of a service.
enum CloudWords {
    static func size(_ bytes: Int64) -> String { ByteCountFormatStyle(style: .file, allowedUnits: [.mb, .gb]).format(bytes) }

    static func share(_ received: Int64, _ total: Int64) -> String {
        let percent = total > 0 ? Int(Double(received) / Double(total) * 100) : 0
        return Oort.text("\(percent)% · \(size(received)) of \(size(total))")
    }

    static func why(_ error: ShelfError, free: Int64? = nil) -> String {
        if case .noSpace(let needed) = error, needed > 0 { return room(needed, free) }
        return why(code: error.code, needed: nil, free: free)
    }

    static func why(code: String, needed: Int64?, free: Int64?) -> String {
        switch code {
        case "offline": Oort.text("You are offline. It resumes by itself.")
        case "networkNotAllowed": Oort.text("Waiting for Wi-Fi.")
        case "signInNeeded": Oort.text("Google asks you to sign in again.")
        case "accessDenied": Oort.text("Google refused access to this folder.")
        case "notFound": Oort.text("This folder is no longer on Google Drive.")
        case "quotaExceeded": Oort.text("Google has reached its download limit for now. Try again tomorrow.")
        case "busy", "server", "interrupted": Oort.text("Google does not answer well. It tries again by itself.")
        case "noSpace": needed.map { room($0, free) } ?? Oort.text("There is not enough free space on this device.")
        case "wrongDigest", "wrongSize", "unsigned": Oort.text("The file received is not the one your Mac sent. Nothing was installed.")
        case "filesMissing": Oort.text("Your Mac has not finished sending it.")
        case "localFile": Oort.text("This device could not write the file.")
        default: Oort.text("Google sent an answer Oort NX does not accept.")
        }
    }

    private static func room(_ needed: Int64, _ free: Int64?) -> String {
        guard let free else { return Oort.text("There is not enough free space on this device.") }
        return Oort.text("Not enough room: \(size(needed)) needed, \(size(free)) free.")
    }

    static func why(_ reason: ShelfHidden.Reason) -> String {
        switch reason {
        case .notPrepared: Oort.text("Not prepared for this device yet. Prepare it on your Mac.")
        case .system: Oort.text("Needs a newer system.")
        case .graphics: Oort.text("This device's graphics cannot run it.")
        case .launcher: Oort.text("Needs another version of Oort NX.")
        case .filesMissing: Oort.text("Your Mac has not finished sending it.")
        }
    }

    static func problem(_ error: ShelfError) -> String {
        error == .unsigned ? Oort.text("Not signed by your Mac: left out.") : Oort.text("Damaged on Google Drive. Send it again from your Mac.")
    }

    /// What a card says under the name, and VoiceOver after it.
    @MainActor static func state(_ game: CloudModel.Game, _ cloud: CloudModel) -> String {
        if cloud.installing == game.id { return Oort.text("Installing…") }
        if let job = game.job {
            switch job.state {
            case .running:
                if cloud.network == .none { return why(code: "offline", needed: nil, free: nil) }
                if cloud.network == .metered, cloud.wifiOnly { return why(code: "networkNotAllowed", needed: nil, free: nil) }
                return share(cloud.received(job), job.build.bytes)
            case .waiting: return job.reason.map { why(code: $0, needed: job.needed, free: cloud.freeSpace) } ?? Oort.text("Waiting")
            case .paused: return Oort.text("Paused")
            case .failed: return why(code: job.reason ?? "", needed: job.needed, free: cloud.freeSpace)
            case .ready: return Oort.text("Ready to install")
            }
        }
        if game.isInstalled { return Oort.text("Installed") }
        if game.installedVersion != nil { return Oort.text("Update") }
        return Oort.text("On Google Drive")
    }
}
