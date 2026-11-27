import SwiftUI
import OortLibrary

/// A column of square cards behind one focus frame: the cursor's card sits in the frame, the next ones hang below it,
/// and a move slides the whole column, as the game rail does sideways. Closed, only the chosen card shows.
struct OortCardRibbon<ID: Hashable, Face: View>: View {
    let ids: [ID]
    let cursor: Int
    let open: Bool
    /// The closed card narrows the row: its outline stays, in the accent colour, until All is chosen again.
    let locked: Bool
    /// Changes once per confirmed choice: the card is pressed in and springs back.
    let press: Int
    let side: CGFloat
    let onPick: (Int) -> Void
    @ViewBuilder var face: (ID, Bool) -> Face
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    private static var resting: CGFloat { 0.82 }
    private static var below: Int { 4 }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                let step = index - cursor
                face(id, step == 0)
                    .frame(width: side, height: side)
                    .overlay { if step == 0 { lock } }
                    .contentShape(Rectangle())
                    .onTapGesture { if step > 0 { onPick(index) } }
                    .allowsHitTesting(open && step > 0)
                    .scaleEffect(step == 0 ? 1 : Self.resting)
                    .offset(y: open ? place(step) : 0)
                    .opacity(step == 0 ? 1 : (open && step > 0 && step <= Self.below ? 1 : 0))
                    .zIndex(step == 0 ? 1 : 0)
                    .animation(Motion.rail(reduceMotion, .spotlight), value: cursor)
                    .animation(reduceMotion ? nil : Motion.rail(false, .spotlight)?.delay(Double(max(0, step)) * 0.03),
                               value: open)
            }
        }
        .frame(width: side, height: side, alignment: .top)
        .keyframeAnimator(initialValue: Press(), trigger: reduceMotion ? 0 : press) { view, press in
            view
                .scaleEffect(press.scale)
                .overlay {
                    shape.strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(SeleneTokens.Space.hairline))
                        .scaleEffect(1 + press.wave * 0.16)
                        .opacity(press.wave > 0 && press.wave < 1 ? 1 - press.wave : 0)
                        .allowsHitTesting(false)
                }
        } keyframes: { _ in
            // Down hard, up past its size, then still: an arcade button.
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.86, duration: 0.07)
                SpringKeyframe(1, duration: 0.34, spring: .init(response: 0.22, dampingRatio: 0.45))
            }
            KeyframeTrack(\.wave) {
                LinearKeyframe(0, duration: 0.07)
                CubicKeyframe(1, duration: 0.34)
            }
        }
    }

    private struct Press {
        var scale: CGFloat = 1
        var wave: CGFloat = 0
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content), style: .continuous)
    }

    private var lock: some View {
        shape.strokeBorder(SeleneTheme.glyph, lineWidth: canvas.u(SeleneTokens.Space.focusStroke))
            .opacity(locked && !open ? 1 : 0)
            .animation(Motion.rowMessage(reduceMotion), value: locked && !open)
            .allowsHitTesting(false)
    }

    /// Where the card `step` places from the frame rests; a card above leaves upward and fades.
    private func place(_ step: Int) -> CGFloat {
        guard step != 0 else { return 0 }
        guard step > 0 else { return -side * 0.6 }
        let gap = canvas.u(SeleneTokens.Space.small)
        let small = side * Self.resting
        return side + gap * 1.5 + CGFloat(step - 1) * (small + gap) - (side - small) / 2
    }
}
