import SwiftUI
import NXLibraryCore

extension OortSynth.Figure {
    var title: String {
        switch self {
        case .rise: "Rise"
        case .major: "Major"
        case .pentatonic: "Pentatonic"
        case .minor: "Minor"
        case .arpeggio: "Arpeggio"
        case .dream: "Dream"
        case .moonlit: "Moonlit"
        case .wave: "Wave"
        case .descent: "Descent"
        case .custom: "Your notes"
        }
    }
}

extension OortSynth.Place {
    var title: String {
        switch self {
        case .games: "Games"
        case .ribbon: "Ribbon"
        case .players: "Players"
        case .lists: "Lists"
        }
    }
}

/// Eight columns of dots, one per note. Pull a column to change its note; it plays as it moves.
struct OortNotes: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    let notes: [Double]
    /// The note being heard, lit.
    var playing: Int?
    let change: (Int, Double) -> Void

    static func name(_ semitones: Double) -> String {
        ["G", "G♯", "A", "A♯", "B", "C", "C♯", "D", "D♯", "E", "F", "F♯"][(Int(semitones.rounded()) % 12 + 12) % 12]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(notes.indices, id: \.self) { index in
                GeometryReader { geometry in
                    column(notes[index], lit: playing == index)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                            let height = max(1, geometry.size.height - 2 * inset)
                            change(index, ((OortSynth.range.upperBound + self.floor) * (1 - (drag.location.y - inset) / height) - self.floor).rounded())
                        })
                }
                .accessibilityElement()
                .accessibilityLabel(L10n.format("Note %@", ["\(index + 1)"], context: locale))
                .accessibilityValue(Self.name(notes[index]))
                .accessibilityAdjustableAction { change(index, notes[index].rounded() + ($0 == .increment ? 1 : -1)) }
            }
        }
        .frame(height: canvas.u(SeleneTokens.Space.sliderMeasure))
        .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content), style: .continuous).fill(SeleneTheme.scrim))
        .padding(canvas.u(SeleneTokens.Space.medium))
        .oortPanel(radius: canvas.u(SeleneTokens.Radius.card))
    }

    private var floor: Double { 5 }
    private var inset: CGFloat { canvas.u(SeleneTokens.Space.panel) }

    private func column(_ note: Double, lit: Bool) -> some View {
        Canvas { context, size in
            let pitch = canvas.u(SeleneTokens.Space.compact)
            // The lowest note keeps a short column, so it can be seen and grabbed.
            let top = inset + (1 - (note + self.floor) / (OortSynth.range.upperBound + self.floor)) * (size.height - 2 * inset)
            var y = size.height - inset, row = 0
            while y > top + pitch {
                let share = 1 - (y - top) / max(1, size.height - top)
                for step in -2...2 {
                    let x = size.width / 2 + CGFloat(step) * pitch + (row % 2 == 0 ? pitch / 2 : 0) - pitch / 4
                    let radius = pitch * (0.14 + 0.16 * share + (lit ? 0.14 : 0))
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(SeleneTheme.glyph.opacity(0.22 + 0.45 * share + (lit ? 0.33 : 0))))
                }
                y -= pitch
                row += 1
            }
            let radius = canvas.u(lit ? SeleneTokens.Space.small : SeleneTokens.Space.compact)
            context.fill(Path(ellipseIn: CGRect(x: size.width / 2 - radius, y: top - radius, width: radius * 2, height: radius * 2)),
                         with: .color(SeleneTheme.ink))
        }
    }
}
