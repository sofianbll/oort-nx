import SwiftUI
import NXLibraryCore

/// One controller's outline and the place of each of its buttons. Half the pad's width is 1 and its middle the
/// origin, so one drawing and one map serve every kind.
struct ControllerShape {
    enum Kind: String, CaseIterable, Identifiable {
        case xbox, playstation, switchPro, joyConPair, joyConLeft, joyConRight

        var id: String { rawValue }

        /// Product names, the same in every language.
        var title: String {
            switch self {
            case .xbox: "Xbox"
            case .playstation: "PlayStation"
            case .switchPro: "Switch Pro"
            case .joyConPair: "Joy-Con"
            case .joyConLeft: "Joy-Con (L)"
            case .joyConRight: "Joy-Con (R)"
            }
        }

        var names: ButtonNameStyle {
            switch self {
            case .xbox: .xbox
            case .playstation: .playstation
            case .switchPro, .joyConPair, .joyConLeft, .joyConRight: .nintendo
            }
        }

        /// The kind in the player's hands. A controller of no known family is drawn as an Xbox one, whose places
        /// most of them follow.
        init(brand: GamepadBrand, name: String) {
            switch brand {
            case .playstation: self = .playstation
            case .xbox, .generic: self = .xbox
            case .nintendoSwitch:
                let name = name.lowercased()
                if !name.contains("joy-con") { self = .switchPro }
                else if name.contains("(l)") { self = .joyConLeft }
                else if name.contains("(r)") { self = .joyConRight }
                else { self = .joyConPair }
            }
        }
    }

    /// What a player chooses to see: five, so a single Joy-Con is one choice, on the side that is connected.
    enum Family: String, CaseIterable {
        case xbox, playstation, switchPro, joyCon, singleJoyCon

        init(_ kind: Kind) {
            switch kind {
            case .xbox: self = .xbox
            case .playstation: self = .playstation
            case .switchPro: self = .switchPro
            case .joyConPair: self = .joyCon
            case .joyConLeft, .joyConRight: self = .singleJoyCon
            }
        }

        func kind(connected: Kind) -> Kind {
            if Self(connected) == self { return connected }
            switch self {
            case .xbox: return .xbox
            case .playstation: return .playstation
            case .switchPro: return .switchPro
            case .joyCon: return .joyConPair
            case .singleJoyCon: return .joyConRight
            }
        }
    }

    /// What a button is drawn as.
    enum Figure: Equatable { case face(String), stick, cross, small(String), pill, square, pad }

    struct Part {
        let button: ControllerButton
        let x, y, radius: Double
        let figure: Figure
    }

    struct Shoulder {
        let button: ControllerButton
        let from, to: CGPoint
        let rows: Int
    }

    let kind: Kind
    let parts: [Part]
    let shoulders: [Shoulder]
    /// Dots of the body, clear of every button, then of its edge.
    let body, rim: [CGPoint]
    /// Where a line from the button's label ends: its middle and its radius.
    let anchors: [ControllerButton: (middle: CGPoint, radius: Double)]

    /// The button that is A in a game: the engine reads a Nintendo pad by its names and any other by its places.
    func switchName(_ button: ControllerButton) -> ControllerButton {
        guard kind.names != .nintendo else { return button }
        return [.a: .b, .b: .a, .x: .y, .y: .x][button] ?? button
    }

    static func of(_ kind: Kind) -> ControllerShape { all[kind]! }
    private static let all = Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0, ControllerShape($0)) })

    private init(_ kind: Kind) {
        self.kind = kind
        let data = Self.data(kind)
        parts = data.parts
        shoulders = data.shoulders
        var anchors: [ControllerButton: (middle: CGPoint, radius: Double)] = [:]
        for part in data.parts { anchors[part.button] = (CGPoint(x: part.x, y: part.y), part.radius * 1.12) }
        for shoulder in data.shoulders {
            anchors[shoulder.button] = (CGPoint(x: (shoulder.from.x + shoulder.to.x) / 2,
                                                y: shoulder.to.y + (shoulder.from.y - shoulder.to.y) * 0.22), 0)
        }
        self.anchors = anchors
        let paths = data.outline.map(Self.path)
        let step = 6.8
        var body: [CGPoint] = []
        for (row, y) in stride(from: 0.0, to: 310, by: step * 0.866).enumerated() {
            for x in stride(from: Double(row % 2) * step / 2, to: 420, by: step)
            where paths.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) {
                let cell = CGPoint(x: (x - 210) / 210, y: (y - 150) / 210)
                if !data.parts.contains(where: { $0.covers(cell) }) { body.append(cell) }
            }
        }
        self.body = body
        rim = paths.flatMap { path in
            let steps = data.outline.count > 1 ? 110 : 190
            return (0..<steps).compactMap { index -> CGPoint? in
                path.trimmedPath(from: 0, to: (Double(index) + 0.5) / Double(steps)).currentPoint
                    .map { CGPoint(x: ($0.x - 210) / 210, y: ($0.y - 150) / 210) }
            }
        }
    }

    /// Absolute M, C, L and Z only.
    private static func path(_ text: String) -> Path {
        var path = Path()
        let words = text.split(separator: " ")
        var index = 0
        var command: Character = "M"
        func number() -> Double {
            defer { index += 1 }
            return Double(words[index]) ?? 0
        }
        while index < words.count {
            var word = words[index]
            if let first = word.first, first.isLetter {
                command = first
                word = word.dropFirst()
                index += 1
                if command == "Z" { path.closeSubpath() }
                continue
            }
            switch command {
            case "M": path.move(to: CGPoint(x: number(), y: number()))
            case "L": path.addLine(to: CGPoint(x: number(), y: number()))
            default:
                let one = CGPoint(x: number(), y: number()), two = CGPoint(x: number(), y: number())
                path.addCurve(to: CGPoint(x: number(), y: number()), control1: one, control2: two)
            }
        }
        return path
    }
}

extension ControllerShape.Part {
    func covers(_ cell: CGPoint) -> Bool {
        let dx = abs(cell.x - x), dy = abs(cell.y - y)
        switch figure {
        case .cross:
            let arm = radius * 0.46
            return (dx < radius * 1.1 && dy < arm) || (dy < radius * 1.1 && dx < arm)
        case .pill: return dx < radius * 1.1 && dy < radius * 2.2
        case .square: return dx < radius * 1.25 && dy < radius * 1.25
        case .pad: return dx < 0.285 && dy < radius * 1.1
        default: return hypot(dx, dy) < radius * 1.18
        }
    }
}

private extension ControllerShape {
    struct Data {
        let outline: [String]
        let parts: [Part]
        let shoulders: [Shoulder]
    }

    static func faces(_ x: Double, _ y: Double, _ reach: Double, _ radius: Double,
                      _ top: (ControllerButton, String), _ left: (ControllerButton, String),
                      _ right: (ControllerButton, String), _ bottom: (ControllerButton, String)) -> [Part] {
        let places: [((ControllerButton, String), Double, Double)] = [(top, 0, -1), (left, -1, 0), (right, 1, 0), (bottom, 0, 1)]
        return places.map { item, dx, dy in
            Part(button: item.0, x: x + dx * reach, y: y + dy * reach, radius: radius, figure: .face(item.1))
        }
    }

    static func cross(_ x: Double, _ y: Double, _ radius: Double) -> [Part] {
        [.init(button: .up, x: x, y: y, radius: radius, figure: .cross)]
    }

    static func shoulders(_ outer: Double, _ inner: Double, _ low: Double, _ high: Double) -> [Shoulder] {
        let sides: [(ControllerButton, ControllerButton, Double)] = [(.l, .zl, -1), (.r, .zr, 1)]
        return sides.flatMap { bumper, trigger, side -> [Shoulder] in
            let end = side * inner
            return [Shoulder(button: bumper, from: CGPoint(x: side * outer, y: low), to: CGPoint(x: end, y: high), rows: 2),
                    Shoulder(button: trigger, from: CGPoint(x: side * (outer + 0.01), y: low - 0.085),
                             to: CGPoint(x: end, y: high - 0.085), rows: 4)]
        }
    }

    static func data(_ kind: Kind) -> Data {
        func part(_ button: ControllerButton, _ x: Double, _ y: Double, _ radius: Double, _ figure: Figure) -> Part {
            Part(button: button, x: x, y: y, radius: radius, figure: figure)
        }
        func nintendo(_ x: Double, _ y: Double, _ reach: Double, _ radius: Double) -> [Part] {
            faces(x, y, reach, radius, (.x, "X"), (.y, "Y"), (.a, "A"), (.b, "B"))
        }
        func figures(_ groups: [Part]...) -> [Part] { groups.flatMap { $0 } }
        var parts: [Part]
        switch kind {
        case .xbox:
            parts = figures(cross(-0.215, 0.06, 0.115),
                            faces(0.455, -0.225, 0.12, 0.058, (.y, "Y"), (.x, "X"), (.b, "B"), (.a, "A")))
            parts.append(part(.l3, -0.45, -0.22, 0.135, .stick))
            parts.append(part(.r3, 0.22, 0.06, 0.125, .stick))
            parts.append(part(.view, -0.105, -0.235, 0.042, .small("❐")))
            parts.append(part(.menu, 0.105, -0.235, 0.042, .small("☰")))
            parts.append(part(.capture, 0, -0.15, 0.032, .small("")))
            parts.append(part(.home, 0, -0.365, 0.06, .small("")))
            return Data(outline: ["M 104 48 C 134 38 150 46 168 46 L 252 46 C 270 46 286 38 316 48 C 352 58 372 108 390 178 C 406 244 390 286 356 280 C 326 274 308 226 278 214 C 262 208 158 208 142 214 C 112 226 94 274 64 280 C 30 286 14 244 30 178 C 48 108 68 58 104 48 Z"],
                        parts: parts, shoulders: shoulders(0.66, 0.3, -0.36, -0.545))
        case .playstation:
            parts = figures(cross(-0.505, -0.215, 0.125),
                            faces(0.505, -0.215, 0.128, 0.056, (.y, "△"), (.x, "□"), (.b, "○"), (.a, "✕")))
            parts.append(part(.l3, -0.245, 0.06, 0.12, .stick))
            parts.append(part(.r3, 0.245, 0.06, 0.12, .stick))
            parts.append(part(.view, 0, -0.29, 0.18, .pad))
            parts.append(part(.capture, -0.345, -0.42, 0.028, .pill))
            parts.append(part(.menu, 0.345, -0.42, 0.028, .pill))
            parts.append(part(.home, 0, 0.06, 0.044, .small("")))
            return Data(outline: ["M 92 46 C 118 36 132 42 146 42 L 274 42 C 288 42 302 36 328 46 C 358 56 378 108 394 182 C 406 246 402 290 366 288 C 336 286 322 238 302 212 C 296 204 290 204 280 204 L 140 204 C 130 204 124 204 118 212 C 98 238 84 286 54 288 C 18 290 14 246 26 182 C 42 108 62 56 92 46 Z"],
                        parts: parts, shoulders: shoulders(0.66, 0.37, -0.39, -0.545))
        case .switchPro:
            parts = figures(cross(-0.215, 0.07, 0.115), nintendo(0.46, -0.205, 0.12, 0.058))
            parts.append(part(.l3, -0.46, -0.2, 0.13, .stick))
            parts.append(part(.r3, 0.22, 0.07, 0.125, .stick))
            parts.append(part(.view, -0.2, -0.36, 0.038, .small("−")))
            parts.append(part(.menu, 0.2, -0.36, 0.038, .small("+")))
            parts.append(part(.capture, -0.09, -0.235, 0.034, .square))
            parts.append(part(.home, 0.09, -0.235, 0.04, .small("")))
            return Data(outline: ["M 112 50 C 150 42 270 42 308 50 C 350 58 372 108 390 188 C 406 252 384 284 352 272 C 318 258 304 216 272 208 C 240 202 180 202 148 208 C 116 216 102 258 68 272 C 36 284 14 252 30 188 C 48 108 70 58 112 50 Z"],
                        parts: parts, shoulders: shoulders(0.66, 0.28, -0.36, -0.53))
        case .joyConPair:
            parts = figures(faces(-0.41, 0.09, 0.115, 0.052, (.up, "▴"), (.left, "◂"), (.right, "▸"), (.down, "▾")),
                            nintendo(0.41, -0.25, 0.115, 0.052))
            parts.append(part(.view, -0.23, -0.46, 0.036, .small("−")))
            parts.append(part(.l3, -0.41, -0.27, 0.125, .stick))
            parts.append(part(.capture, -0.27, 0.41, 0.034, .square))
            parts.append(part(.menu, 0.23, -0.46, 0.036, .small("+")))
            parts.append(part(.r3, 0.41, 0.11, 0.125, .stick))
            parts.append(part(.home, 0.27, 0.41, 0.042, .small("")))
            return Data(outline: ["M 176 30 L 134 30 C 90 30 74 56 74 96 L 74 214 C 74 254 90 280 134 280 L 176 280 Z",
                                  "M 244 30 L 286 30 C 330 30 346 56 346 96 L 346 214 C 346 254 330 280 286 280 L 244 280 Z"],
                        parts: parts, shoulders: shoulders(0.62, 0.24, -0.47, -0.63))
        case .joyConLeft, .joyConRight:
            // Held sideways, the rail on top: the printed marks turn with it, the places do not.
            if kind == .joyConLeft {
                parts = faces(0.2, 0.03, 0.115, 0.052, (.x, "▸"), (.y, "▴"), (.a, "▾"), (.b, "◂"))
                parts.append(part(.menu, -0.63, -0.17, 0.036, .small("−")))
                parts.append(part(.capture, 0.62, -0.16, 0.034, .square))
            } else {
                parts = faces(0.2, 0.03, 0.115, 0.052, (.x, "Y"), (.y, "B"), (.a, "X"), (.b, "A"))
                parts.append(part(.menu, 0.62, -0.16, 0.036, .small("+")))
                parts.append(part(.home, -0.63, -0.17, 0.042, .small("")))
            }
            parts.append(part(.l3, -0.43, 0.04, 0.125, .stick))
            return Data(outline: ["M 56 96 L 364 96 L 364 148 C 364 194 338 212 296 212 L 124 212 C 82 212 56 194 56 148 Z"],
                        parts: parts,
                        shoulders: [Shoulder(button: .l, from: CGPoint(x: -0.44, y: -0.3), to: CGPoint(x: -0.14, y: -0.3), rows: 2),
                                    Shoulder(button: .r, from: CGPoint(x: 0.44, y: -0.3), to: CGPoint(x: 0.14, y: -0.3), rows: 2)])
        }
    }
}
