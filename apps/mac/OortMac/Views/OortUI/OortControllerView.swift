import SwiftUI
import NXLibraryCore

/// The pad in the player's hands, in the cloud's dots: what is pressed lights up, the sticks lean.
struct OortControllerView: View {
    @ObservedObject var live = ControllerLive.shared
    @ObservedObject private var controller = GameControllerService.shared
    /// Another kind than the one connected, for a guide.
    var kind: ControllerShape.Kind?
    /// Canvas units.
    var width: CGFloat = 420
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        let shape = ControllerShape.of(kind ?? .init(brand: controller.activeBrand, name: controller.activeControllerName))
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !live.awake)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            Canvas { context, size in draw(shape, context, size, now) }
        }
        .frame(width: canvas.u(width), height: canvas.u(width * Self.height))
        .accessibilityHidden(true)
    }

    /// The drawing's height and the pad's middle in it, for a width of 1.
    static let height = 0.74, middle = 0.395

    private func draw(_ shape: ControllerShape, _ context: GraphicsContext, _ size: CGSize, _ now: TimeInterval) {
        let unit = size.width * 0.5, zoom = size.width / 420
        let middle = CGPoint(x: size.width / 2, y: size.width * Self.middle)
        let mark = SeleneTheme.glyph, lit = SeleneTheme.focus
        func light(_ button: ControllerButton) -> Double {
            reduceMotion ? (live.held.contains(button) ? 1 : 0) : live.light(button, at: now)
        }
        func dot(_ x: Double, _ y: Double, _ radius: Double, _ color: Color, _ alpha: Double) {
            let r = radius * zoom
            context.fill(Path(ellipseIn: CGRect(x: middle.x + x * unit - r, y: middle.y + y * unit - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(min(1, alpha))))
        }
        func ring(_ x: Double, _ y: Double, _ radius: Double, _ size: Double, _ color: Color, _ alpha: Double) {
            let count = max(6, Int(radius * 300))
            for step in 0..<count {
                let angle = Double(step) / Double(count) * 2 * .pi
                dot(x + cos(angle) * radius, y + sin(angle) * radius, size, color, alpha)
            }
        }
        func disc(_ x: Double, _ y: Double, _ radius: Double, _ amount: Double) {
            guard amount > 0.04 else { return }
            for turn in stride(from: 0.0, through: radius * 0.9, by: 0.017) {
                let count = max(1, Int(turn * 340))
                for step in 0..<count {
                    let angle = Double(step) / Double(count) * 2 * .pi
                    dot(x + cos(angle) * turn, y + sin(angle) * turn, 1 + amount * 1.5, lit, amount)
                }
            }
        }
        func line(_ from: CGPoint, _ to: CGPoint, _ size: Double, _ color: Color, _ alpha: Double) {
            let count = max(1, Int(hypot(to.x - from.x, to.y - from.y) / 0.0185))
            for step in 0..<count {
                let t = Double(step) / Double(count)
                dot(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t, size, color, alpha)
            }
        }
        func outline(_ points: [CGPoint], _ color: Color, _ alpha: Double) {
            for index in points.indices { line(points[index], points[(index + 1) % points.count], 1.05, color, alpha) }
        }
        func write(_ text: String, _ x: Double, _ y: Double, _ size: Double, _ color: Color) {
            guard !text.isEmpty else { return }
            context.draw(Text(verbatim: text).font(.system(size: size * unit, weight: .semibold)).foregroundColor(color),
                         at: CGPoint(x: middle.x + x * unit, y: middle.y + y * unit))
        }
        for cell in shape.body {
            let shade = 0.4 + 0.5 * max(0, 0.5 + cell.x * 0.5 - cell.y * 0.4)
            dot(cell.x, cell.y, 0.55 + shade, mark, 0.14 + shade * 0.46)
        }
        for point in shape.rim { dot(point.x, point.y, 1.15, mark, SeleneTokens.Alpha.strong) }
        for part in shape.parts {
            let amount = light(part.button)
            let color = amount > 0.04 ? lit : mark, x = part.x, y = part.y, r = part.radius
            switch part.figure {
            case .face(let name), .small(let name):
                disc(x, y, r, amount * SeleneTokens.Alpha.muted)
                ring(x, y, r, 1.1 + amount * 0.6, color, SeleneTokens.Alpha.near)
                write(name, x, y, name.count == 1 && "▴▾◂▸".contains(name) ? r * 1.5 : r * 1.05, SeleneTheme.ink)
            case .stick:
                let stick = part.button == .l3 ? live.left : live.right
                let dx = x + Double(stick.x) * 0.045, dy = y - Double(stick.y) * 0.045
                ring(x, y, r, 1.1, mark, SeleneTokens.Alpha.near)
                disc(dx, dy, r * 0.66, amount)
                ring(dx, dy, r * 0.66, 1.2, color, SeleneTokens.Alpha.near)
                for turn in stride(from: 0.0, to: r * 0.5, by: 0.026) { ring(dx, dy, turn, 0.75, mark, SeleneTokens.Alpha.half) }
            case .cross:
                let arm = r * 0.36
                for (button, dx, dy) in [(ControllerButton.up, 0.0, -1.0), (.down, 0, 1), (.left, -1, 0), (.right, 1, 0)] {
                    disc(x + dx * r * 0.66, y + dy * r * 0.66, arm, light(button))
                }
                outline([(-arm, -r), (arm, -r), (arm, -arm), (r, -arm), (r, arm), (arm, arm), (arm, r), (-arm, r),
                         (-arm, arm), (-r, arm), (-r, -arm), (-arm, -arm)].map { CGPoint(x: x + $0.0, y: y + $0.1) },
                        mark, SeleneTokens.Alpha.near)
            case .pill:
                disc(x, y, r, amount)
                outline([(-r, -r * 1.4), (0, -r * 2), (r, -r * 1.4), (r, r * 1.4), (0, r * 2), (-r, r * 1.4)]
                    .map { CGPoint(x: x + $0.0, y: y + $0.1) }, color, SeleneTokens.Alpha.near)
            case .square:
                let side = r * 0.82
                outline([(-side, -side), (side, -side), (side, side), (-side, side)]
                    .map { CGPoint(x: x + $0.0, y: y + $0.1) }, color, SeleneTokens.Alpha.near)
                ring(x, y, r * 0.34, 0.9 + amount, color, SeleneTokens.Alpha.near)
            case .pad:
                for column in -11...11 {
                    for row in -6...6 {
                        dot(x + Double(column) * 0.0205, y + Double(row) * 0.0255, 0.6 + amount, color, SeleneTokens.Alpha.line + amount * 0.6)
                    }
                }
                outline([(-0.27, -r), (0.27, -r), (0.235, r), (-0.235, r)].map { CGPoint(x: x + $0.0, y: y + $0.1) },
                        color, SeleneTokens.Alpha.near)
            }
        }
        for shoulder in shape.shoulders {
            let amount = light(shoulder.button)
            for row in 0..<shoulder.rows {
                for step in 0...26 {
                    let t = Double(step) / 26
                    dot(shoulder.from.x + (shoulder.to.x - shoulder.from.x) * t,
                        shoulder.from.y + (shoulder.to.y - shoulder.from.y) * (1 - pow(1 - t, 2.2)) + Double(row) * 0.018,
                        1.05 + amount * 0.9, amount > 0.04 ? lit : mark, SeleneTokens.Alpha.veil + 0.4 * t * (1 - amount) + amount)
                }
            }
        }
    }
}

/// The pad with a line from each button to what it does: the guide of the Controls page.
struct OortControllerMap: View {
    struct Entry: Identifiable {
        let button: ControllerButton
        let name, title: String
        var hold: String?
        var id: String { "\(button)" }
    }

    let kind: ControllerShape.Kind
    let entries: [Entry]
    @ObservedObject var live = ControllerLive.shared
    @Environment(\.seleneCanvas) private var canvas

    private static let width = 1120.0, pad = 460.0, column = 276.0, row = 46.0

    private struct Item {
        let entry: Entry
        let middle: CGPoint
        let radius: Double
    }

    private struct Side {
        var entries: [Item]
        let left: Bool
    }

    /// Labels of each side, so that no two of its lines cross. A button on the middle line goes where there is room.
    private static func sides(_ entries: [Entry], _ shape: ControllerShape) -> [Side] {
        let items = entries.compactMap { entry in
            shape.anchors[entry.button].map { Item(entry: entry, middle: $0.middle, radius: $0.radius) }
        }
        var left = items.filter { $0.middle.x < -0.01 }, right = items.filter { $0.middle.x > 0.01 }
        for item in items where abs(item.middle.x) <= 0.01 {
            if left.count <= right.count { left.append(item) } else { right.append(item) }
        }
        return [Side(entries: left, left: true), Side(entries: right, left: false)].map { side in
            var side = side
            side.entries.sort { $0.middle.y < $1.middle.y }
            let count = side.entries.count, edge = side.left ? -1.15 : 1.15
            func place(_ index: Int) -> CGPoint {
                CGPoint(x: edge, y: (Double(index) - Double(count - 1) / 2) * row / (pad / 2) - 0.05)
            }
            // Swapping the two ends of a crossing shortens the lines, so this stops; the bound is for rounding.
            for _ in 0..<(count * count) {
                var swapped = false
                for first in 0..<count {
                    for second in (first + 1)..<max(count, first + 1)
                    where crosses(side.entries[first].middle, place(first), side.entries[second].middle, place(second)) {
                        side.entries.swapAt(first, second)
                        swapped = true
                    }
                }
                if !swapped { break }
            }
            return side
        }
    }

    private static func crosses(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func turn(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Double { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        return turn(a, b, c) * turn(a, b, d) < 0 && turn(c, d, a) * turn(c, d, b) < 0
    }

    var body: some View {
        let shape = ControllerShape.of(kind)
        let sides = Self.sides(entries, shape)
        let rows = max(sides.map(\.entries.count).max() ?? 0, 7)
        let height = max(Double(rows) * Self.row, Self.pad * OortControllerView.height)
        ZStack(alignment: .topLeading) {
            OortControllerView(live: live, kind: kind, width: Self.pad)
                .offset(x: canvas.u((Self.width - Self.pad) / 2), y: canvas.u((height - Self.pad * OortControllerView.height) / 2))
            Canvas { context, _ in
                for side in sides {
                    for (index, item) in side.entries.enumerated() {
                        draw(item, held: isHeld(item.entry.button), to: y(index, side, height), left: side.left,
                             height: height, in: context)
                    }
                }
            }
            .accessibilityHidden(true)
            ForEach(sides, id: \.left) { side in
                ForEach(Array(side.entries.enumerated()), id: \.element.entry.id) { index, item in
                    label(item.entry, left: side.left)
                        .offset(x: canvas.u(side.left ? 0 : Self.width - Self.column), y: canvas.u(y(index, side, height) - Self.row / 2))
                }
            }
        }
        .frame(width: canvas.u(Self.width), height: canvas.u(height), alignment: .topLeading)
    }

    private func isHeld(_ button: ControllerButton) -> Bool {
        button == .up ? !live.held.isDisjoint(with: [.up, .down, .left, .right]) : live.held.contains(button)
    }

    private func y(_ index: Int, _ side: Side, _ height: Double) -> Double {
        height / 2 + (Double(index) - Double(side.entries.count - 1) / 2) * Self.row
    }

    private func draw(_ item: Item, held: Bool, to y: Double, left: Bool, height: Double, in context: GraphicsContext) {
        let unit = Self.pad / 2, side = left ? -1.0 : 1
        let top = (height - Self.pad * OortControllerView.height) / 2
        let middle = CGPoint(x: Self.width / 2 + item.middle.x * unit,
                             y: top + Self.pad * OortControllerView.middle + item.middle.y * unit)
        let end = Self.width / 2 + side * (Self.width / 2 - Self.column - 8), bend = CGPoint(x: end - side * 28, y: y)
        let length = max(1, hypot(bend.x - middle.x, bend.y - middle.y)), reach = item.radius * unit / length
        let start = CGPoint(x: middle.x + (bend.x - middle.x) * reach, y: middle.y + (bend.y - middle.y) * reach)
        var path = Path()
        path.move(to: start)
        path.addLine(to: bend)
        path.addLine(to: CGPoint(x: end, y: y))
        let color = held ? SeleneTheme.focus : SeleneTheme.ink
        context.stroke(path.applying(.init(scaleX: canvas.u(1), y: canvas.u(1))),
                       with: .color(color.opacity(held ? 1 : SeleneTokens.Alpha.mist)),
                       style: .init(lineWidth: canvas.u(held ? 2 : 1), lineCap: .round, lineJoin: .round))
        let r = canvas.u(held ? 3.5 : 2)
        context.fill(Path(ellipseIn: CGRect(x: canvas.u(start.x) - r, y: canvas.u(start.y) - r, width: r * 2, height: r * 2)),
                     with: .color(color.opacity(held ? 1 : SeleneTokens.Alpha.strong)))
    }

    private func label(_ entry: Entry, left: Bool) -> some View {
        let held = isHeld(entry.button)
        let name = Text(verbatim: entry.name)
            .seleneFont(.badge, .semibold)
            .foregroundColor(held ? SeleneTheme.focus : SeleneTheme.ink60)
        let words = VStack(alignment: left ? .trailing : .leading, spacing: 0) {
            Text(verbatim: entry.title).seleneFont(.text, .semibold).foregroundColor(held ? SeleneTheme.focus : SeleneTheme.ink)
            if let hold = entry.hold {
                Text(verbatim: hold).seleneFont(.badge).foregroundColor(SeleneTheme.ink60)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        return HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            if left { words; name } else { name; words }
        }
        .frame(width: canvas.u(Self.column), height: canvas.u(Self.row), alignment: left ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }
}
