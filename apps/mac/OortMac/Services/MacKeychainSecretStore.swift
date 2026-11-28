import Foundation
import OortLibrary
import Security

/// The login keychain keeps rclone's configuration password (`SecretStore`): the code the core ran before, unchanged.
/// rclone reads it back with `/usr/bin/security` (`RcloneConfiguration.passwordCommand`).
struct MacKeychainSecretStore: SecretStore {
    struct KeychainFailure: Error {}

    public func ensureSecret(service: String, account: String) throws {
        // The CLI password command reads the file-based login keychain, not the Data Protection keychain.
        var login: SecKeychain?
        let path = NSHomeDirectory() + "/Library/Keychains/login.keychain-db"
        guard SecKeychainOpen(path, &login) == errSecSuccess, let login else { throw KeychainFailure() }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account
        ]
        var search = query
        search[kSecMatchSearchList] = [login]
        let found = SecItemCopyMatching(search as CFDictionary, nil)
        if found == errSecSuccess { return }
        guard found == errSecItemNotFound else { throw KeychainFailure() }

        var bytes = Data(count: 32)
        guard bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess
        else { throw KeychainFailure() }
        var item = query
        item[kSecUseKeychain] = login
        item[kSecValueData] = bytes.base64EncodedData()
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw KeychainFailure() }
    }
}
