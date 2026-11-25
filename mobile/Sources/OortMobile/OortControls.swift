import OortCore
import SwiftUI

/// The switch of the Mac app: a track of dots that fills when it is on. The whole row is the target.
struct OortToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: SeleneTokens.Space.small) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? Oort.glyph.opacity(0.28) : Oort.panelLow)
                    OortDots(rise: on ? 1 : 0, color: Oort.focus).clipShape(.capsule)
                        .animation(Oort.dots(reduceMotion), value: on)
                    Capsule().strokeBorder(on ? Oort.focus.opacity(0.55) : Oort.lineStrong, lineWidth: 1)
                    Circle().fill(on ? Oort.focus : Oort.ink2).frame(width: 25, height: 25).padding(3)
                        .shadow(color: Oort.night.opacity(0.5), radius: 2, y: 1)
                }
                .frame(width: 55, height: 31)
                .opacity(enabled ? 1 : 0.45)
                .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: on)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// The slider of the Mac app: the part passed is dots, the rest a hairline. A finger anywhere on it moves it.
struct OortSlider: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double
    let title: String
    let text: String
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let knob: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, reach = max(width - Self.knob, 1)
            let x = reach * min(max((value - bounds.lowerBound) / max(bounds.upperBound - bounds.lowerBound, .ulpOfOne), 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Oort.panelLow).frame(height: 6)
                Canvas { context, size in
                    var dots = Path()
                    for dot in stride(from: 4.0, to: x + Self.knob / 2, by: 6) { dots.addEllipse(in: CGRect(x: dot - 1.8, y: size.height / 2 - 1.8, width: 3.6, height: 3.6)) }
                    context.fill(dots, with: .color(Oort.focus))
                }
                Circle().fill(Oort.focus).frame(width: Self.knob, height: Self.knob)
                    .scaleEffect(dragging && !reduceMotion ? 1.14 : 1)
                    .shadow(color: Oort.night.opacity(0.5), radius: 4, y: 2)
                    .offset(x: x)
            }
            .frame(height: 44)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 4).onChanged { drag in
                dragging = true
                let share = min(max((drag.location.x - Self.knob / 2) / reach, 0), 1)
                let next = bounds.lowerBound + ((share * (bounds.upperBound - bounds.lowerBound)) / step).rounded() * step
                if abs(next - value) > step / 1000 { value = min(max(next, bounds.lowerBound), bounds.upperBound) }
            }.onEnded { _ in dragging = false })
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: dragging)
        }
        .frame(height: 44)
        .sensoryFeedback(.selection, trigger: value) { _, _ in !OortSounds.trialMuted }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(text)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, bounds.upperBound)
            case .decrement: value = max(value - step, bounds.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// The pad in the player's hands, in the cloud's dots: what is pressed lights up, the sticks lean.
struct OortPadView: View {
    let press: (OortPadShape.Place) -> Double
    let left, right: CGPoint
    /// L, ZL, R, ZR, from 0 to 1.
    let shoulders: [Double]

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 2, zoom = size.width / 420, middle = CGPoint(x: size.width / 2, y: size.height * 0.54)
            func dot(_ x: Double, _ y: Double, _ radius: Double, _ color: Color, _ alpha: Double) {
                let r = radius * zoom
                context.fill(Path(ellipseIn: CGRect(x: middle.x + x * unit - r, y: middle.y + y * unit - r, width: r * 2, height: r * 2)),
                             with: .color(color.opacity(min(1, alpha))))
            }
            for cell in OortPadShape.cells {
                let (x, y) = (cell.point.x, cell.point.y)
                if let place = cell.part {
                    let lit = press(place)
                    if lit > 0.04 {
                        dot(x, y, 2.4 + lit * 3.2 * (1 - cell.edge * 0.4), Oort.focus, 0.35 + lit * 0.65)
                    } else if cell.edge > 0.66 {
                        dot(x, y, 2.2, Oort.glyph, 0.9)
                    }
                } else {
                    let shade = 0.4 + 0.5 * max(0, 0.5 + x * 0.5 - y * 0.4)
                    dot(x, y, 1.5 + shade * 2.2, Oort.glyph, 0.25 + shade * 0.6)
                }
            }
            for (part, stick) in [(OortPadShape.parts[0], left), (OortPadShape.parts[1], right)] {
                for step in 0..<16 {
                    let angle = Double(step) / 16 * 2 * .pi
                    dot(part.x + stick.x * 0.05 + cos(angle) * 0.065, part.y - stick.y * 0.05 + sin(angle) * 0.065, 2.3, Oort.glyph, 1)
                }
            }
            for (index, (side, tier)) in [(-1.0, 0.0), (-1, 1), (1, 0), (1, 1)].enumerated() {
                let lit = shoulders.indices.contains(index) ? shoulders[index] : 0
                for point in OortPadShape.shoulder(side: side, tier: tier) {
                    dot(point.x, point.y, 2 + lit * 2.6, lit > 0.04 ? Oort.focus : Oort.glyph, 0.5 - tier * 0.12 + lit * 0.5)
                }
            }
        }
        .aspectRatio(1 / 0.72, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
