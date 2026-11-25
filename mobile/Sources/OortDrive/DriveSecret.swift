import Foundation

/// A credential. Printing, dumping, interpolating or encoding it shows nothing.
public struct DriveSecret: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let value: String

    public init(_ value: String) { self.value = value }

    public var description: String { "(hidden)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
    /// Only where it goes into a request or into the keychain.
    func reveal() -> String { value }
}

/// Where the refresh token waits between two runs.
public protocol DriveVault: Sendable {
    func read() throws -> DriveSecret?
    func write(_ secret: DriveSecret) throws
    func erase() throws
}

/// The device's keychain. The item never leaves this device (no iCloud keychain, no restore on another one) and is readable after the
/// first unlock, so a background download can renew its access.
public struct DriveKeychain: DriveVault {
    let account: String
    let service = "io.github.sofianbll.oortnx.drive"

    /// `account` tells two connections apart; it is the client identifier, which is not a secret.
    public init(account: String) { self.account = account }

    var item: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
         kSecAttrSynchronizable: false, kSecUseDataProtectionKeychain: true]
    }

    func attributes(_ secret: DriveSecret) -> [CFString: Any] {
        [kSecValueData: Data(secret.reveal().utf8), kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    }

    public func read() throws -> DriveSecret? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item.merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 } as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let text = String(data: data, encoding: .utf8)
        else { throw DriveVaultError(status: status) }
        return DriveSecret(text)
    }

    public func write(_ secret: DriveSecret) throws {
        var status = SecItemUpdate(item as CFDictionary, attributes(secret) as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(item.merging(attributes(secret)) { $1 } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw DriveVaultError(status: status) }
    }

    public func erase() throws {
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DriveVaultError(status: status) }
    }
}

public struct DriveVaultError: Error, Equatable { public let status: OSStatus }
