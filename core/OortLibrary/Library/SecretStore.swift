import Foundation

/// Where the app keeps a secret the core needs but must not hold: the password that encrypts rclone's configuration
/// (its OAuth tokens). The Mac's implementation is the login keychain (`MacKeychainSecretStore` in the app); the core
/// never reads the secret, only asks that it exists.
public protocol SecretStore: Sendable {
    /// Makes sure a random secret exists for `service` and `account`; an existing one is never replaced.
    func ensureSecret(service: String, account: String) throws
}
