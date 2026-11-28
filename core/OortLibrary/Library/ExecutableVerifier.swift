import Foundation

/// Checks that a downloaded program is the one its publisher signed, before the core installs it (rclone). The Mac's
/// implementation is Apple's code signing (`MacCodeSignatureVerifier` in the app); its SHA-256 is checked as well.
public protocol ExecutableVerifier: Sendable {
    func hasValidSignature(_ url: URL) -> Bool
}
