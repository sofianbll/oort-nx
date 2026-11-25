import Foundation

public enum ControllerButton: CaseIterable, Hashable {
    case up, down, left, right
    case a, b, x, y, l, r, zl, zr, menu, view, l3, r3, home, capture
}

public enum ControllerInputChange: Equatable {
    case button(ControllerButton, Bool)
    case leftStick(SIMD2<Float>)
    case rightStick(SIMD2<Float>)
}

public struct ControllerInputState: Equatable {
    public var buttons: Set<ControllerButton> = []
    public var leftStick: SIMD2<Float> = .zero
    public var rightStick: SIMD2<Float> = .zero

    public init() {}

    public func changes(from previous: Self) -> [ControllerInputChange] {
        var changes: [ControllerInputChange] = []
        if buttons != previous.buttons {
            for button in ControllerButton.allCases {
                let pressed = buttons.contains(button)
                if pressed != previous.buttons.contains(button) { changes.append(.button(button, pressed)) }
            }
        }
        if leftStick != previous.leftStick { changes.append(.leftStick(leftStick)) }
        if rightStick != previous.rightStick { changes.append(.rightStick(rightStick)) }
        return changes
    }
}

/// Nintendo's simple and full input reports (nxnative `pad_hid.h` and `pad_pro.h`).
public struct NintendoHIDInput {
    private static let simpleButtons: [ControllerButton] = [
        .b, .a, .y, .x, .l, .r, .zl, .zr, .view, .menu, .l3, .r3, .home, .capture,
    ]
    private static let fullButtons: [[ControllerButton?]] = [
        [.y, .x, .b, .a, nil, nil, .r, .zr],
        [.view, .menu, .r3, .l3, .home, .capture, nil, nil],
        [.down, .up, .right, .left, nil, nil, .l, .zl],
    ]
    private static let hatDirections: [[ControllerButton]] = [
        [.up], [.up, .right], [.right], [.right, .down],
        [.down], [.down, .left], [.left], [.left, .up],
    ]
    // The two formats have different raw centers and reaches; neither can calibrate the other.
    private var simpleAxes = Array(repeating: Axis(reach: 0.7, restLimit: 0.25), count: 4)
    private var fullAxes = Array(repeating: Axis(reach: 1200.0 / 2048, restLimit: 500.0 / 2048), count: 4)

    public init() {}

    public mutating func decode<Bytes: RandomAccessCollection>(reportID: UInt32, bytes: Bytes) -> ControllerInputState?
    where Bytes.Element == UInt8, Bytes.Index == Int {
        if reportID == 0x30 { return decodeFull(bytes) }
        guard reportID == 0x3f else { return nil }
        // Exactly 11 bytes is a bare payload: 0x3f can also be its first button byte.
        let offset = bytes.count > 11 && bytes.first == 0x3f ? 1 : 0
        guard bytes.count - offset >= 11 else { return nil }
        let base = bytes.startIndex + offset
        let buttonWord = UInt16(bytes[base]) | UInt16(bytes[base + 1]) << 8
        var input = ControllerInputState()
        for (bit, button) in Self.simpleButtons.enumerated() where buttonWord & (1 << bit) != 0 {
            input.buttons.insert(button)
        }
        let hat = Int(bytes[base + 2])
        if Self.hatDirections.indices.contains(hat) { input.buttons.formUnion(Self.hatDirections[hat]) }

        func axis(_ index: Int) -> Float {
            let start = base + 3 + 2 * index
            let raw = UInt16(bytes[start]) | UInt16(bytes[start + 1]) << 8
            return Float(raw) / 32_767.5 - 1
        }
        input.leftStick = Self.stick(simpleAxes[0].normalize(axis(0)), -simpleAxes[1].normalize(axis(1)))
        input.rightStick = Self.stick(simpleAxes[2].normalize(axis(2)), -simpleAxes[3].normalize(axis(3)))
        return input
    }

    private mutating func decodeFull<Bytes: RandomAccessCollection>(_ bytes: Bytes) -> ControllerInputState?
    where Bytes.Element == UInt8, Bytes.Index == Int {
        let base: Int
        // Use the standard lengths (USB may add padding): the timer can itself be 0x30.
        switch bytes.count {
        case 48, 63: base = bytes.startIndex
        case 49, 64:
            guard bytes.first == 0x30 else { return nil }
            base = bytes.startIndex + 1
        default: return nil
        }
        var input = ControllerInputState()
        for (index, buttons) in Self.fullButtons.enumerated() {
            let byte = bytes[base + 2 + index]
            for (bit, button) in buttons.enumerated() where byte & (1 << bit) != 0 {
                if let button { input.buttons.insert(button) }
            }
        }

        func axes(at start: Int) -> (Float, Float) {
            let middle = UInt16(bytes[start + 1])
            let x = UInt16(bytes[start]) | (middle & 0xf) << 8
            let y = middle >> 4 | UInt16(bytes[start + 2]) << 4
            return ((Float(x) - 2048) / 2048, (Float(y) - 2048) / 2048)
        }
        let (lx, ly) = axes(at: base + 5)
        let (rx, ry) = axes(at: base + 8)
        // Full reports already use the launcher's upward-positive Y axis.
        input.leftStick = Self.stick(fullAxes[0].normalize(lx), fullAxes[1].normalize(ly))
        input.rightStick = Self.stick(fullAxes[2].normalize(rx), fullAxes[3].normalize(ry))
        return input
    }

    private struct Axis {
        var rest: Float?
        var negativeReach: Float
        var positiveReach: Float
        let restLimit: Float

        init(reach: Float, restLimit: Float) {
            negativeReach = reach
            positiveReach = reach
            self.restLimit = restLimit
        }

        mutating func normalize(_ value: Float) -> Float {
            let center = rest ?? (abs(value) <= restLimit ? value : 0)
            rest = center
            let delta = value - center
            if delta > 0 {
                positiveReach = max(positiveReach, delta)
                return delta / positiveReach
            }
            negativeReach = max(negativeReach, -delta)
            return delta / negativeReach
        }
    }

    private static func stick(_ x: Float, _ y: Float) -> SIMD2<Float> {
        let radius = (x * x + y * y).squareRoot()
        let dead: Float = 0.12
        let outer: Float = 0.9
        guard radius > dead else { return .zero }
        let scale = (radius - dead) / (outer - dead) / radius
        return SIMD2(min(1, max(-1, x * scale)), min(1, max(-1, y * scale)))
    }
}

public enum ControllerArbitration: Equatable {
    case gameController, wait(until: TimeInterval), hid

    public struct HID {
        private let name: String?
        private let claimedByGC: Bool
        private var fallbackAt: TimeInterval

        public init(name: String?, claimedByGC: Bool, connectedAt: TimeInterval) {
            self.name = name
            self.claimedByGC = claimedByGC
            fallbackAt = connectedAt + 2
        }

        public mutating func admission(gcNames: [String], at time: TimeInterval) -> ControllerArbitration {
            // shortcut: identical product names cannot distinguish physical twins; use a shared ID if the OS exposes one.
            if let name, gcNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                fallbackAt = min(fallbackAt, time)
                return .gameController
            }
            return claimedByGC && time < fallbackAt ? .wait(until: fallbackAt) : .hid
        }
    }

    public static func preferred(hasGameController: Bool, hasHID: Bool) -> Self? {
        if hasGameController { return .gameController }
        return hasHID ? .hid : nil
    }
}
