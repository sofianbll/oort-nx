import SwiftUI
import NXLibraryCore

extension EnvironmentValues {
    @Entry var onlinePlayersByTitle: [String: Int] = [:]
}

struct NextendoOnlineBadge: View {
    let titleID: String?
    var compact = false
    @Environment(\.onlinePlayersByTitle) private var counts
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale

    var body: some View {
        if let titleID, let count = counts[titleID.lowercased()], count > 0 {
            SeleneStatusDot(text: L10n.count("%lld online", count, context: locale), color: SeleneTheme.statusOK,
                            labelColor: SeleneTheme.ink)
                .padding(.horizontal, canvas.u(compact ? 7 : 10))
                .padding(.vertical, canvas.u(compact ? 4 : 5))
                .oortPanel(radius: canvas.u(SeleneTokens.Radius.hint))
                .allowsHitTesting(false)
        }
    }
}
