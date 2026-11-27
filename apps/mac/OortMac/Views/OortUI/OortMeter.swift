import SwiftUI
import NXLibraryCore

/// How far something is. Without a known total it moves instead of inventing a share.
struct OortMeter: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let share: Double?
    /// Canvas units; nil takes the height it is given.
    var height: CGFloat? = 6
    var track: Color = SeleneTheme.ink15
    var fill: Color = SeleneTheme.focus
    @State private var sweep = false

    private static let part = 0.32

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if let share {
                    Capsule().fill(fill)
                        .frame(width: share <= 0 ? 0 : max(geometry.size.height, width * min(1, share)))
                        .animation(Motion.transfer(reduceMotion), value: share)
                } else {
                    Capsule().fill(fill.opacity(reduceMotion ? SeleneTokens.Alpha.muted : 1))
                        .frame(width: width * Self.part)
                        .offset(x: reduceMotion ? width * (1 - Self.part) / 2 : sweep ? width * (1 - Self.part) : 0)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(SeleneTheme.ease(SeleneTokens.Motion.pageLate).repeatForever(autoreverses: true)) { sweep = true }
                        }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height.map(canvas.u))
        .accessibilityHidden(true)
    }
}
