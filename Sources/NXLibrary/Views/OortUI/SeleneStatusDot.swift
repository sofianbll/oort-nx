import AppKit
import SwiftUI
import NXLibraryCore

/// A short status label; its dot is decorative, not the only status cue.
struct SeleneStatusDot: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.screenTrace) private var trace
    let text: String
    let color: Color
    var labelColor: Color = SeleneTheme.ink60
    var accessibilityTitle: String? = nil
    var pulses = false
    var font: SeleneTokens.Text = .text

    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            SeleneStatusMark(color: color, pulses: pulses)
            Text(text).seleneFont(font).foregroundColor(labelColor)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle ?? text)
        .accessibilityValue(accessibilityTitle == nil ? "" : text)
        .screenTrace(trace, [.init(kind: .dot, text: text, tone: OortStatus.Tone.screen(color))])
    }
}

struct SeleneStatusMark: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appearsActive) private var windowActive
    let color: Color
    let pulses: Bool
    var showsDot = true

    var body: some View {
        let diameter = canvas.u(7)
        Circle().fill(showsDot ? color : .clear).frame(width: diameter, height: diameter)
            .background {
                if pulses && !reduceMotion && !systemReduceMotion && windowActive {
                    StatusHalo(color: color, diameter: diameter)
                        .frame(width: diameter * 3, height: diameter * 3)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct StatusHalo: NSViewRepresentable {
    let color: Color
    let diameter: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let halo = CALayer()
        view.layer?.addSublayer(halo)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1; scale.toValue = 2.8
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.5; fade.toValue = 0
        let pulse = CAAnimationGroup()
        pulse.duration = 1.6
        scale.duration = pulse.duration; fade.duration = pulse.duration
        pulse.animations = [scale, fade]
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulse.repeatCount = .infinity
        halo.opacity = 0
        halo.add(pulse, forKey: "pulse")
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let halo = view.layer?.sublayers?.first else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.frame = CGRect(x: diameter, y: diameter, width: diameter, height: diameter)
        halo.cornerRadius = diameter / 2
        halo.borderWidth = diameter / 7
        halo.borderColor = NSColor(color).cgColor
        CATransaction.commit()
    }
}
