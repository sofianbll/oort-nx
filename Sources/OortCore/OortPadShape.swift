import Foundation

/// The controller drawn in dots, as places only: the middle of the pad is the origin, half its width is 1, y goes down.
/// The Mac and the phone draw from this; what is pressed and its colours are theirs.
public enum OortPadShape {
    public struct Point: Equatable, Sendable {
        public let x, y: Double
        public init(_ x: Double, _ y: Double) { (self.x, self.y) = (x, y) }
    }

    public enum Place: String, CaseIterable, Sendable {
        case leftStick, rightStick, up, down, left, right, top, west, east, bottom, view, menu, home
    }

    public struct Part: Equatable, Sendable {
        public let place: Place
        public let x, y, radius: Double
    }

    public static let parts: [Part] = [
        .init(place: .leftStick, x: -0.43, y: -0.23, radius: 0.135), .init(place: .rightStick, x: 0.24, y: 0.05, radius: 0.125),
        .init(place: .up, x: -0.145, y: 0.025, radius: 0.045), .init(place: .down, x: -0.145, y: 0.175, radius: 0.045),
        .init(place: .left, x: -0.22, y: 0.1, radius: 0.045), .init(place: .right, x: -0.07, y: 0.1, radius: 0.045),
        .init(place: .top, x: 0.467, y: -0.36, radius: 0.062), .init(place: .west, x: 0.343, y: -0.24, radius: 0.062),
        .init(place: .east, x: 0.59, y: -0.24, radius: 0.062), .init(place: .bottom, x: 0.467, y: -0.115, radius: 0.062),
        .init(place: .view, x: -0.16, y: -0.3, radius: 0.038), .init(place: .menu, x: 0.16, y: -0.3, radius: 0.038),
        .init(place: .home, x: 0, y: -0.2, radius: 0.045),
    ]

    /// The dots that make the pad, and the part each one belongs to with how far from its middle it is (0 to 1).
    public static let cells: [(point: Point, part: Place?, edge: Double)] = {
        let outline = Self.outline, step = 8.2
        var cells: [(Point, Place?, Double)] = []
        for (row, y) in stride(from: 0.0, to: 300, by: step * 0.866).enumerated() {
            for x in stride(from: Double(row % 2) * step / 2, to: 420, by: step) where contains(Point(x, y), outline) {
                let point = Point((x - 210) / 210, (y - 150) / 210)
                let near = parts.map { ($0, hypot(point.x - $0.x, point.y - $0.y)) }.filter { $0.1 < $0.0.radius }.min { $0.1 < $1.1 }
                cells.append((point, near?.0.place, near.map { $0.1 / $0.0.radius } ?? 0))
            }
        }
        return cells
    }()

    /// The dots of a shoulder (tier 0) or trigger (tier 1), side -1 left and 1 right.
    public static func shoulder(side: Double, tier: Double) -> [Point] {
        (0..<9).map { step in
            let t = Double(step) / 8
            return Point(side * (0.3 + t * 0.34), -0.54 - tier * 0.07 + t * t * 0.1)
        }
    }

    private static let outline: [Point] = {
        let start = Point(112, 52)
        let curves: [(Point, Point, Point)] = [
            (Point(150, 44), Point(270, 44), Point(308, 52)), (Point(352, 58), Point(372, 110), Point(392, 190)),
            (Point(408, 254), Point(384, 284), Point(352, 272)), (Point(318, 258), Point(304, 214), Point(272, 206)),
            (Point(240, 200), Point(180, 200), Point(148, 206)), (Point(116, 214), Point(102, 258), Point(68, 272)),
            (Point(36, 284), Point(12, 254), Point(28, 190)), (Point(48, 110), Point(68, 58), Point(112, 52)),
        ]
        var points = [start], from = start
        for (a, b, to) in curves {
            for i in 1...24 {
                let t = Double(i) / 24, u = 1 - t
                points.append(Point(u * u * u * from.x + 3 * u * u * t * a.x + 3 * u * t * t * b.x + t * t * t * to.x,
                                    u * u * u * from.y + 3 * u * u * t * a.y + 3 * u * t * t * b.y + t * t * t * to.y))
            }
            from = to
        }
        return points
    }()

    private static func contains(_ p: Point, _ polygon: [Point]) -> Bool {
        var inside = false, j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
