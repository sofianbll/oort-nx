import Foundation
import OortLibrary
import Security

/// A downloaded rclone must carry a valid signature (`ExecutableVerifier`): the check the core ran before, unchanged.
struct MacCodeSignatureVerifier: ExecutableVerifier {
    func hasValidSignature(_ url: URL) -> Bool {
        var code: SecStaticCode?
        return SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess
            && code.map { SecStaticCodeCheckValidity($0, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess } == true
    }
}
