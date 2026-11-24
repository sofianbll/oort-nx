import Foundation
import GameController
import IOKit.hid
import IOKit.hidsystem
import OSLog
import NXLibraryCore

// HID discovery follows NX2Apple's GamepadHID.swift (MIT; see NOTICE).
final class HIDControllerSource: ControllerSource {
    var onEvent: ((ControllerSourceEvent) -> Void)?
    private var manager: IOHIDManager?
    private var devices: [ObjectIdentifier: IOHIDDevice] = [:]
    private var nintendo: Set<ObjectIdentifier> = []
    private var readers: [ObjectIdentifier: Reader] = [:]
    private var selected: ObjectIdentifier?
    private var observed: Set<ObjectIdentifier> = []
    private static let options = IOOptionBits(kIOHIDOptionsTypeNone)
    private static let mode = CFRunLoopMode.commonModes.rawValue
    private static let log = Logger(subsystem: "local.nxlibrary", category: "controllers")

    func start() {
        guard manager == nil else { return }
        // Open only the navigation pad and visible HID roster rows, never seize a device.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
        let matches = [kHIDUsage_GD_GamePad, kHIDUsage_GD_Joystick].map {
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context, result == kIOReturnSuccess else { return }
            Unmanaged<HIDControllerSource>.fromOpaque(context).takeUnretainedValue().found(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDControllerSource>.fromOpaque(context).takeUnretainedValue().removed(device)
        }, context)
        self.manager = manager
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), Self.mode)
        let result = IOHIDManagerOpen(manager, Self.options)
        if result != kIOReturnSuccess {
            Self.log.error("Cannot open HID controller manager (\(result))")
            stop()
        }
    }

    func stop() {
        let ids = Array(devices.keys)
        tearDown()
        for id in ids { onEvent?(.disconnected(id)) }
    }

    deinit { tearDown() }

    private func tearDown() {
        for id in Array(readers.keys) { closeReader(id) }
        selected = nil
        observed.removeAll()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), Self.mode)
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerClose(manager, Self.options)
        }
        manager = nil
        devices.removeAll()
        nintendo.removeAll()
    }

    private func found(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        guard manager != nil, devices[id] == nil else { return }
        func property(_ key: String) -> CFTypeRef? { IOHIDDeviceGetProperty(device, key as CFString) }
        guard (property(kIOHIDGCSyntheticDeviceKey) as? NSNumber)?.boolValue != true,
              (property(kIOHIDVirtualHIDevice) as? NSNumber)?.boolValue != true,
              (property(kIOHIDTransportKey) as? String)?.caseInsensitiveCompare("Virtual") != .orderedSame else { return }
        // Matching both usages can return two references to the same registry device.
        if let entry = Self.registryID(device),
           devices.values.contains(where: { Self.registryID($0) == entry }) { return }
        devices[id] = device
        let elements = IOHIDDeviceCopyMatchingElements(device, nil, Self.options) as? [IOHIDElement] ?? []
        let canNavigate = elements.contains {
            let type = IOHIDElementGetType($0).rawValue
            guard (kIOHIDElementTypeInput_Misc.rawValue...kIOHIDElementTypeInput_NULL.rawValue).contains(type)
            else { return false }
            let reportID = IOHIDElementGetReportID($0)
            // Nintendo can expose the full report as vendor-defined data, not button elements.
            return reportID == 0x30 || (reportID == 0x3f && IOHIDElementGetUsagePage($0) == UInt32(kHIDPage_Button))
        }
        if canNavigate { nintendo.insert(id) }
        let name = property(kIOHIDProductKey) as? String
        let bluetooth = (property(kIOHIDTransportKey) as? String)?.lowercased().hasPrefix("bluetooth") == true
        let address = bluetooth ? (property("BluetoothAddress") as? String ?? property("DeviceAddress") as? String) : nil
        let stableID = ControllerHardwareID.make(serial: property(kIOHIDSerialNumberKey) as? String,
                                                 bluetoothAddress: address,
                                                 vendor: (property(kIOHIDVendorIDKey) as? NSNumber)?.intValue,
                                                 product: (property(kIOHIDProductIDKey) as? NSNumber)?.intValue,
                                                 salt: ControllerHardwareID.installationSalt)
        let brand: GamepadBrand = canNavigate ? .nintendoSwitch : GCControllerSource.brand(vendor: name ?? "", category: "")
        let identity = ControllerIdentity(id: id, name: name, brand: brand, stableID: stableID,
                                          supportsNavigation: canNavigate)
        onEvent?(.connected(identity, claimedByGC: GCController.supportsHIDDevice(device)))
    }

    private func removed(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        guard devices.removeValue(forKey: id) != nil else { return }
        closeReader(id)
        nintendo.remove(id)
        if selected == id { selected = nil }
        onEvent?(.disconnected(id))
    }

    @discardableResult
    func select(_ id: ObjectIdentifier?) -> Bool {
        if id == selected { return true }
        let previous = selected
        selected = nil
        if let previous, !observed.contains(previous) { closeReader(previous) }
        guard let id else { return true }
        guard nintendo.contains(id), openReader(id) else { return false }
        selected = id
        readers[id]?.navigationDecoder = NintendoHIDInput()
        readers[id]?.navigationState = ControllerInputState()
        return true
    }

    func observe(_ ids: Set<ObjectIdentifier>) {
        for id in observed.subtracting(ids) where id != selected { closeReader(id) }
        for id in ids.subtracting(observed) { _ = openReader(id) }
        observed = ids
    }

    func status(_ id: ObjectIdentifier) -> ControllerStatus {
        guard let device = devices[id] else { return .init() }
        let percent = (IOHIDDeviceGetProperty(device, "BatteryPercent" as CFString) as? NSNumber)?.floatValue
        let charging = (IOHIDDeviceGetProperty(device, "BatteryCharging" as CFString) as? NSNumber)?.boolValue
        let level = percent.flatMap { (0...100).contains($0) ? $0 / 100 : nil } ?? readers[id]?.batteryLevel
        return .init(batteryLevel: level, isCharging: charging)
    }

    private func openReader(_ id: ObjectIdentifier) -> Bool {
        if readers[id] != nil { return true }
        guard let device = devices[id] else { return false }
        let useReports = nintendo.contains(id)
        let size = useReports ? (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0 : 0
        guard !useReports || (11...65_536).contains(size) else {
            Self.log.error("Invalid HID controller report buffer size (\(size))")
            return false
        }
        let result = IOHIDDeviceOpen(device, Self.options) // Shared with the game engine; never seize.
        guard result == kIOReturnSuccess else {
            Self.log.error("Cannot open HID controller (\(result))")
            return false
        }
        let reader = Reader(source: self, device: device, capacity: size)
        readers[id] = reader
        let context = Unmanaged.passUnretained(reader).toOpaque()
        if let buffer = reader.buffer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { context, result, _, _, reportID, bytes, count in
                guard let context, result == kIOReturnSuccess else { return }
                let reader = Unmanaged<Reader>.fromOpaque(context).takeUnretainedValue()
                reader.source?.read(reader, reportID, bytes, count)
            }, context)
        }
        IOHIDDeviceRegisterInputValueCallback(device, { context, result, _, value in
            guard let context, result == kIOReturnSuccess else { return }
            let reader = Unmanaged<Reader>.fromOpaque(context).takeUnretainedValue()
            reader.source?.read(reader, value)
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), Self.mode)
        return true
    }

    private func closeReader(_ id: ObjectIdentifier) {
        guard let reader = readers.removeValue(forKey: id) else { return }
        if let buffer = reader.buffer {
            IOHIDDeviceRegisterInputReportCallback(reader.device, buffer, reader.capacity, nil, nil)
        }
        IOHIDDeviceRegisterInputValueCallback(reader.device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(reader.device, CFRunLoopGetMain(), Self.mode)
        IOHIDDeviceClose(reader.device, Self.options)
    }

    private func read(_ reader: Reader, _ reportID: UInt32, _ bytes: UnsafePointer<UInt8>, _ count: Int) {
        let id = ObjectIdentifier(reader.device)
        guard readers[id] === reader, (0...reader.capacity).contains(count),
              let state = reader.decoder.decode(reportID: reportID,
                                                bytes: UnsafeBufferPointer(start: bytes, count: count)) else { return }
        let pressed = state.buttons.subtracting(reader.state.buttons)
        reader.state = state
        if !pressed.isEmpty { onEvent?(.buttonPressed(id)) }
        guard selected == id,
              let navigation = reader.navigationDecoder.decode(reportID: reportID,
                                                              bytes: UnsafeBufferPointer(start: bytes, count: count)) else { return }
        let changes = navigation.changes(from: reader.navigationState)
        reader.navigationState = navigation
        for change in changes { onEvent?(.input(id, change)) }
    }

    private func read(_ reader: Reader, _ value: IOHIDValue) {
        let id = ObjectIdentifier(reader.device)
        guard readers[id] === reader else { return }
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let integer = IOHIDValueGetIntegerValue(value)
        if page == UInt32(kHIDPage_GenericDeviceControls),
           IOHIDElementGetUsage(element) == UInt32(kHIDUsage_GenDevControls_BatteryStrength) {
            let min = IOHIDElementGetLogicalMin(element), max = IOHIDElementGetLogicalMax(element)
            if min < max, (min...max).contains(integer) {
                reader.batteryLevel = Float((Double(integer) - Double(min)) / (Double(max) - Double(min)))
            }
        } else if reader.buffer == nil, page == UInt32(kHIDPage_Button) {
            let cookie = IOHIDElementGetCookie(element)
            if integer == 0 { reader.pressed.remove(cookie) }
            else if reader.pressed.insert(cookie).inserted { onEvent?(.buttonPressed(id)) }
        }
    }

    private static func registryID(_ device: IOHIDDevice) -> UInt64? {
        var id: UInt64 = 0
        let result = IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return result == kIOReturnSuccess ? id : nil
    }

    private final class Reader {
        weak var source: HIDControllerSource?
        let device: IOHIDDevice
        let capacity: Int
        let buffer: UnsafeMutablePointer<UInt8>?
        var decoder = NintendoHIDInput()
        var state = ControllerInputState()
        var navigationDecoder = NintendoHIDInput()
        var navigationState = ControllerInputState()
        var pressed: Set<IOHIDElementCookie> = []
        var batteryLevel: Float?

        init(source: HIDControllerSource, device: IOHIDDevice, capacity: Int) {
            self.source = source
            self.device = device
            self.capacity = capacity
            buffer = capacity > 0 ? .allocate(capacity: capacity) : nil
        }

        deinit { buffer?.deallocate() }
    }
}
