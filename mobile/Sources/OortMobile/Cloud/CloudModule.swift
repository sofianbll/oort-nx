import Foundation
import OortCore

/// What the app was built with, if anything: a connector and what this device is. The screens know no service by name.
public struct CloudModule: Sendable {
    public enum Code: Sendable { case good, otherDevice, wrong }

    let outline: ShelfConnector
    let device: ShelfDevice
    /// SHA-256 alone: it trusts no signer.
    let hashing: ShelfCrypto
    let root: URL
    let read: @Sendable (String) -> Code
    let link: @Sendable (_ code: String, _ settings: CloudSettings, _ received: @escaping @Sendable (Int64) -> Void) -> CloudLink?
    let freeSpace: @Sendable (URL) -> Int64?
    let network: @Sendable () -> CloudNetwork
    /// What one request brings: the most a pause or a broken connection can lose.
    let chunk: Int64

    /// `outline`: the connector before any code is known, for its hosts and permissions. `root`: where downloads wait on the device.
    public init(outline: ShelfConnector, device: ShelfDevice, hashing: ShelfCrypto, root: URL, read: @escaping @Sendable (String) -> Code,
                link: @escaping @Sendable (_ code: String, _ settings: CloudSettings, _ received: @escaping @Sendable (Int64) -> Void) -> CloudLink?,
                freeSpace: @escaping @Sendable (URL) -> Int64? = { CloudModule.space($0) },
                network: @escaping @Sendable () -> CloudNetwork = { CloudNetwork() }, chunk: Int64 = 64 << 20) {
        self.chunk = chunk
        (self.outline, self.device, self.hashing, self.root, self.read, self.link, self.freeSpace, self.network) = (outline, device, hashing, root, read, link, freeSpace, network)
    }
}

extension CloudModule {
    /// Room for something the player asked for, on the volume of the nearest folder that exists.
    public static func space(_ url: URL) -> Int64? {
        var folder = url
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 { folder.deleteLastPathComponent() }
        return try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }
}

/// One code's connection: opening it asks nothing of the network.
public struct CloudLink: Sendable {
    let connector: ShelfConnector
    let crypto: ShelfCrypto
    let isSignedIn: @Sendable () -> Bool
    let signIn: @Sendable () -> CloudSignIn
    let reconnect: @Sendable (@escaping @Sendable () -> Void) -> Void
    let abandon: @Sendable () async -> Void

    public init(connector: ShelfConnector, crypto: ShelfCrypto, isSignedIn: @escaping @Sendable () -> Bool, signIn: @escaping @Sendable () -> CloudSignIn,
                reconnect: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void, abandon: @escaping @Sendable () async -> Void) {
        (self.connector, self.crypto, self.isSignedIn, self.signIn, self.reconnect, self.abandon) = (connector, crypto, isSignedIn, signIn, reconnect, abandon)
    }
}

/// The page the system's browser opens, the address it comes back on, and what ends the sign-in.
public struct CloudSignIn: Sendable {
    let page: URL
    let scheme: String
    let finish: @Sendable (URL) async throws -> Void

    public init(page: URL, scheme: String, finish: @escaping @Sendable (URL) async throws -> Void) {
        (self.page, self.scheme, self.finish) = (page, scheme, finish)
    }
}

/// The player's choices, on this device only.
public final class CloudSettings: ShelfChoices, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults) { self.defaults = defaults }

    public func permissions(of connector: String) -> Set<String>? { defaults.stringArray(forKey: "oort.cloud.\(connector)").map(Set.init) }
    public func set(_ permissions: Set<String>?, of connector: String) { defaults.set(permissions.map { $0.sorted() }, forKey: "oort.cloud.\(connector)") }

    var code: String? {
        get { defaults.string(forKey: "oort.cloud.code") }
        set { defaults.set(newValue, forKey: "oort.cloud.code") }
    }
    public var wifiOnly: Bool {
        get { defaults.object(forKey: "oort.cloud.wifiOnly") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "oort.cloud.wifiOnly") }
    }
    func forget() { for key in ["code", "wifiOnly"] { defaults.removeObject(forKey: "oort.cloud.\(key)") } }
}
