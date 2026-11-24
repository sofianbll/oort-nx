import CryptoKit
import Foundation
import GameController
import IOKit.hid
import IOKit.hidsystem

public enum PlayerPadFingerprint {
    static func make(transport: String, vendor: UInt16, product: UInt16, serial: String) -> String? {
        guard transport == "hid" || transport == "sw2", !serial.isEmpty, !serial.utf8.contains(0) else { return nil }
        let ids = String(format: "%04x:%04x", Int(vendor), Int(product))
        let input = "nxnative-pad-v1:\(transport):\(ids):\(serial)"
        guard input.utf8.count <= 511 else { return nil }
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func unique(_ devices: [(fingerprint: String, identity: String?)]) -> [String: String] {
        let fingerprints = Dictionary(grouping: devices, by: \.fingerprint)
        let identities = Dictionary(grouping: devices.compactMap(\.identity), by: { $0 })
        return devices.reduce(into: [:]) { result, device in
            if let id = device.identity, identities[id]?.count == 1, fingerprints[device.fingerprint]?.count == 1 {
                result[id] = device.fingerprint
            }
        }
    }

    /// The correlation callback returns a local opaque ID, never a serial. The manager is not scheduled and
    /// opens no individual device. The engine's private Switch 2 BLE identity reply isn't an IOKit serial.
    @MainActor public static func liveHID(identity: (String, Int, Int) -> String?) -> [String: String] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
        let matches = [kHIDUsage_GD_GamePad, kHIDUsage_GD_Joystick].map {
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return [:] }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        let gameControllerNames = Set(GCController.controllers().filter { $0.extendedGamepad != nil }
            .compactMap(\.vendorName))
        let candidates: [(fingerprint: String, identity: String?)] = devices.compactMap { device in
            func property(_ key: String) -> CFTypeRef? { IOHIDDeviceGetProperty(device, key as CFString) }
            guard (property(kIOHIDGCSyntheticDeviceKey) as? NSNumber)?.boolValue != true,
                  (property(kIOHIDVirtualHIDevice) as? NSNumber)?.boolValue != true,
                  (property(kIOHIDTransportKey) as? String)?.caseInsensitiveCompare("Virtual") != .orderedSame,
                  let vendor = (property(kIOHIDVendorIDKey) as? NSNumber).flatMap({ UInt16(exactly: $0.intValue) }),
                  let product = (property(kIOHIDProductIDKey) as? NSNumber).flatMap({ UInt16(exactly: $0.intValue) }),
                  let serial = property(kIOHIDSerialNumberKey) as? String,
                  let hash = make(transport: "hid", vendor: vendor, product: product, serial: serial)
            else { return nil }
            // shortcut: don't reserve a slot for an unproven raw-HID route (including native GC
            // pads and twin fallback). Upgrade when the connector can observe the engine's route.
            let raw = ![0x045e, 0x054c, 0x057e].contains(vendor) &&
                !GCController.supportsHIDDevice(device) &&
                !gameControllerNames.contains(property(kIOHIDProductKey) as? String ?? "")
            return (hash, raw ? identity(serial, Int(vendor), Int(product)) : nil)
        }
        return unique(candidates)
    }
}
