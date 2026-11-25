import SwiftUI
import NXLibraryCore

extension EnvironmentValues {
    @Entry var onlinePlayersByTitle: [String: Int] = [:]
    /// Where those counts show (`OnlinePlayersDisplay`).
    @Entry var onlinePlayersDisplay = OnlinePlayersDisplay.dot
}

/// The dot on a cover whose game has players online. The tile says the number to VoiceOver.
struct NextendoOnlineBadge: View {
    let titleID: String?
    @Environment(\.onlinePlayersByTitle) private var counts
    @Environment(\.onlinePlayersDisplay) private var display
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        if display.count(for: titleID, in: counts, at: .tile) != nil {
            SeleneStatusMark(color: SeleneTheme.statusOK, pulses: false)
                .padding(canvas.u(SeleneTokens.Space.compact))
                .oortPanel(radius: canvas.u(SeleneTokens.Radius.content))
                .allowsHitTesting(false)
        }
    }
}
