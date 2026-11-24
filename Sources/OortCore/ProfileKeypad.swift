/// The profile PIN's grid, focus and pending digits, independent of the input device.
public struct ProfileKeypad {
    public enum Key: Hashable {
        case digit(Int), erase, validate
    }

    public static let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.erase, .digit(0), .validate]
    ]

    private let pinLength: Int
    private var row = 0
    private var column = 0
    private var digits = ""
    public var selected: Key { Self.rows[row][column] }
    public var count: Int { digits.count }
    public var canValidate: Bool { count == pinLength }

    package init(pinLength: Int) {
        precondition(pinLength > 0)
        self.pinLength = pinLength
    }

    public mutating func focus(_ key: Key) {
        guard let row = Self.rows.firstIndex(where: { $0.contains(key) }),
              let column = Self.rows[row].firstIndex(of: key) else { return }
        self.row = row
        self.column = column
    }

    public mutating func move(_ direction: MoveDirection) {
        switch direction {
        case .left: column = max(column - 1, 0)
        case .right: column = min(column + 1, Self.rows[row].count - 1)
        case .up: row = max(row - 1, 0)
        case .down: row = min(row + 1, Self.rows.count - 1)
        }
    }

    public mutating func press(_ key: Key) -> String? {
        switch key {
        case .digit(let digit) where !canValidate && (0...9).contains(digit):
            digits.append(String(digit))
        case .erase where !digits.isEmpty:
            digits.removeLast()
        case .validate where canValidate:
            let pin = digits
            digits = ""
            return pin
        default:
            break
        }
        return nil
    }
}
