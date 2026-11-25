import SwiftUI
import NXLibraryCore

/// A short written fact: a genre, a version, a state. `art` sits on an image, `tone` carries a state's colour with its word.
struct OortTag: View {
    enum Preset { case quiet, panel, art }

    @Environment(\.seleneCanvas) private var canvas
    let text: String
    var icon: MaterialIcon? = nil
    var preset: Preset = .quiet
    var tone: Color? = nil
    var monospaced = false

    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.hairline)) {
            if let icon { MaterialIconView(icon, size: SeleneTokens.Space.medium) }
            Text(verbatim: text).seleneFont(.badge, .semibold, design: monospaced ? .monospaced : .default)
        }
        .lineLimit(1)
        .foregroundStyle(ink)
        .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
        .padding(.vertical, canvas.u(SeleneTokens.Space.hairline))
        .background(Capsule().fill(fill))
    }

    private var ink: Color { tone ?? (preset == .art ? SeleneTheme.artInk : SeleneTheme.ink90) }

    private var fill: Color {
        if let tone { return tone.opacity(SeleneTokens.Alpha.soft) }
        return switch preset {
        case .quiet: SeleneTheme.ink15
        case .panel: SeleneTheme.scrim45
        case .art: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.muted)
        }
    }
}
