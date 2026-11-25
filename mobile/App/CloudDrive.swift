// The optional cloud library of this app: Google Drive, off until the player turns it on. Leaving this file and one line of OortApp.swift
// out leaves an app with no network code.
import Metal
import OortCore
import OortMobile
#if OORT_FAKE_DRIVE
@_spi(Checks) import OortDrive
#else
import OortDrive
#endif
import ShellHost
import UIKit

@MainActor enum CloudDrive {
    private static var kept: CloudModel?
    /// The same model for the screens and for the system's background relaunch, which comes with no screen.
    static var model: CloudModel {
        if let kept { return kept }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let model = CloudModel(module: module, settings: CloudSettings(.standard), frameworks: ShellHostConfig.defaultHotFrameworksRoot(),
                               games: documents.appendingPathComponent("games", isDirectory: true), check: { OortSigning.refusal($0) })
        kept = model
        return model
    }

    static let session = "io.github.sofianbll.oortnx.mobile.downloads"

    private static var module: CloudModule {
        #if OORT_FAKE_DRIVE
        CloudChecks.begin()
        #endif
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cloud", isDirectory: true)
        let scratch = root.appendingPathComponent("scratch", isDirectory: true), inbox = root.appendingPathComponent("inbox", isDirectory: true)
        return CloudModule(outline: DriveConnection.outline, device: device, hashing: .apple(signer: Data()), root: root, read: { text in
            guard let invite = DriveInvite.parse(text) else { return .wrong }
            return invite.client.kind == .ios ? .good : .otherDevice
        }, link: { code, settings, received in
            guard let invite = DriveInvite.parse(code), invite.client.kind == .ios else { return nil }
            let session = DriveSession.background(identifier: Self.session, inbox: inbox, allowsMeteredNetwork: { !settings.wifiOnly }, received: received)
            let metered: @Sendable () -> Bool = { !settings.wifiOnly }
            #if OORT_FAKE_DRIVE
            let connection = DriveConnection(invite: invite, scratch: scratch, background: session, allowsMeteredNetwork: metered, endpoints: CloudChecks.endpoints)
            #else
            let connection = DriveConnection(invite: invite, scratch: scratch, background: session, allowsMeteredNetwork: metered)
            #endif
            let access = connection.access
            return CloudLink(connector: connection.connector, crypto: .apple(signer: invite.signer), isSignedIn: { connection.isSignedIn }, signIn: {
                let attempt = connection.signIn()
                return CloudSignIn(page: attempt.page, scheme: invite.client.callbackScheme) { try await access.finish(attempt, callback: $0) }
            }, reconnect: { session.reconnect($0) }, abandon: { await session.abandon() })
        }, freeSpace: space, network: network, chunk: chunk)
    }

    private static var device: ShelfDevice {
        var features: Set<String> = []
        if let gpu = MTLCreateSystemDefaultDevice() {
            let families: [(MTLGPUFamily, String)] = [(.apple7, "apple7"), (.apple8, "apple8"), (.apple9, "apple9"), (.apple10, "apple10")]
            for (family, word) in families where gpu.supportsFamily(family) { features.insert(word) }
            if gpu.supportsBCTextureCompression { features.insert("bc") }
        }
        return ShelfDevice(platform: .ios, system: UIDevice.current.systemVersion, features: features, host: Int(DM_GLUE_VERSION))
    }

    #if OORT_FAKE_DRIVE
    private static let chunk: Int64 = 1 << 20
    private static let space: @Sendable (URL) -> Int64? = { CloudChecks.free ?? CloudModule.space($0) }
    private static let network: @Sendable () -> CloudNetwork = { CloudChecks.metered ? CloudNetwork(.metered) : CloudNetwork() }
    #else
    private static let chunk: Int64 = 64 << 20
    private static let space: @Sendable (URL) -> Int64? = { CloudModule.space($0) }
    private static let network: @Sendable () -> CloudNetwork = { CloudNetwork() }
    #endif

    /// The system relaunched the app, or woke it, for what it downloaded meanwhile.
    static func reconnect(_ done: @escaping @Sendable () -> Void) {
        // Time to check what came and to ask for the next part before being suspended again.
        let hold = UIApplication.shared.beginBackgroundTask(withName: "oort.cloud")
        model.reconnect {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                done()
                try? await Task.sleep(for: .seconds(15))
                UIApplication.shared.endBackgroundTask(hold)
            }
        }
    }
}

#if OORT_FAKE_DRIVE
/// The simulator's checks only: a local stand-in for Google. Not compiled in the app that ships (`check_ipa.py` proves it).
enum CloudChecks {
    private static var defaults: UserDefaults { .standard }
    /// A relaunch by the system comes without arguments: the port is remembered.
    static func begin() {
        let port = defaults.integer(forKey: "OortFakeDrivePort")
        if port > 0 { defaults.set(port, forKey: "OortFakeDriveKept") }
        if defaults.bool(forKey: "OortFakeReset") {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("oort.cloud.") { defaults.removeObject(forKey: key) }
            try? DriveKeychain(account: "1-oort.apps.googleusercontent.com").erase()
        }
        if defaults.bool(forKey: "OortFakeExit") {
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
            }
        }
    }

    static var endpoints: DriveEndpoints {
        let base = URL(string: "http://127.0.0.1:\(defaults.integer(forKey: "OortFakeDriveKept"))")!
        return DriveEndpoints(authorize: base.appendingPathComponent("auth"), token: base.appendingPathComponent("token"),
                              revoke: base.appendingPathComponent("revoke"), files: base.appendingPathComponent("drive/v3/files"))
    }
    static var free: Int64? { (defaults.object(forKey: "OortFakeFree") as? String).flatMap(Int64.init) }
    static var metered: Bool { defaults.bool(forKey: "OortFakeMetered") }
}
#endif
