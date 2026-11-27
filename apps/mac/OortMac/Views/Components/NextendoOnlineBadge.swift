import SwiftUI
import OortLibrary

extension EnvironmentValues {
    @Entry var onlinePlayersByTitle: [String: Int] = [:]
    /// Where those counts show (`OnlinePlayersDisplay`).
    @Entry var onlinePlayersDisplay = OnlinePlayersDisplay()
}

/// A cover's short count. The enclosing tile supplies the full Nextendo label to VoiceOver.
struct NextendoOnlineBadge: View {
    let count: Int
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale

    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.hairline)) {
            SeleneStatusMark(color: SeleneTheme.statusOK, pulses: false)
            Text(count.formatted(.number.notation(.compactName).locale(locale.formatLocale)))
                .seleneFont(.text, .bold)
                .monospacedDigit()
                .foregroundStyle(SeleneTheme.artInk)
        }
        .oortArtShadow(canvas.u(SeleneTokens.Space.thinStroke), strength: SeleneTokens.Alpha.near)
        .oortArtShadow(canvas.u(SeleneTokens.Space.hairline), strength: SeleneTokens.Alpha.near)
    }
}
