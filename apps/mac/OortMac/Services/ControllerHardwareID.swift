import CryptoKit
import Foundation
import OortLibrary

enum ControllerHardwareID {
    static func make(serial: String?, bluetoothAddress: String?, vendor: Int?, product: Int?,
                     salt: @autoclosure () -> Data) -> String? {
        let serial = serial?.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = bluetoothAddress?.lowercased().filter { $0 != ":" && $0 != "-" }
        let value: String
        if let serial, !serial.isEmpty, serial.utf8.count <= 256,
           !["unknown", "none", "n/a", "null", "default", "123456", "123456789", "0123456789"].contains(serial.lowercased()),
           !serial.allSatisfy({ $0 == "0" || $0 == "-" }) {
            value = "serial:\(vendor ?? -1):\(product ?? -1):\(serial)"
        } else if let address, address.utf8.count == 12, address.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  address != "000000000000", address != "ffffffffffff" {
            value = "bluetooth:\(address)"
        } else { return nil }
        let hash = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: salt()))
        return "hid-v1:" + Data(hash).base64EncodedString()
    }

    // The salt never leaves the app's preference profile; no hardware value is written there.
    static let installationSalt: Data = {
        let defaults = AppData.preferences
        let key = "ControllerHardwareSaltV1"
        if let salt = defaults.data(forKey: key), salt.count == 32 { return salt }
        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        defaults.set(salt, forKey: key)
        return salt
    }()
}
