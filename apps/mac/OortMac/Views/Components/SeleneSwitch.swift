import SwiftUI
import OortLibrary

struct SeleneSwitch: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.screenTrace) private var trace
    @Binding var isOn: Bool
    private var reduced: Bool { reduceMotion || systemReduceMotion }

    var body: some View {
        Button {
            isOn.toggle()
            SoundEffectService.shared.play(.key)
        } label: {
            // The track fills with the halftone; the knob carries the state.
            Capsule()
                .fill(SeleneTheme.panelRaised)
                .overlay {
                    OortDots(rise: isOn ? 1 : 0, color: SeleneTheme.glyph)
                        .animation(Motion.dots(reduced), value: isOn)
                        .clipShape(Capsule())
                }
                .overlay { PillOutline(width: max(1, canvas.u(SeleneTokens.Space.thinStroke))).fill(SeleneTheme.lineStrong, style: FillStyle(eoFill: true)) }
                .frame(width: canvas.u(56), height: canvas.u(30))
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(LinearGradient(colors: [SeleneTheme.focus, SeleneTheme.focus.mix(with: SeleneTheme.glyph, by: SeleneTokens.Effect.surfaceLineStrong)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: canvas.u(24), height: canvas.u(24))
                        .background { Circle().fill(SeleneTheme.panelRaised).padding(-canvas.u(SeleneTokens.Space.segmentInset)) }
                        .padding(canvas.u(SeleneTokens.Space.segmentInset))
                }
        }
        .buttonStyle(OortPressStyle())
        .animation(Motion.press(reduced, down: false), value: isOn)
        .accessibilityValue(isOn ? L10n.text("On") : L10n.text("Off"))
        .accessibilityAddTraits(.isButton)
        .screenTrace(trace, [.init(kind: .switch, on: isOn)])
    }
}
