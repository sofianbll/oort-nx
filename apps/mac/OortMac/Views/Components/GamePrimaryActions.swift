import SwiftUI
import NXLibraryCore

/// Play/Options/favorite visual and input targets are identical across sources.
struct GamePrimaryActions: View {
    let primaryTitle: String
    var secondaryTitle = "Options"
    let isFavorite: Bool
    let focused: Int?
    var primaryEnabled = true
    /// The wave dots after the first title, as the porting pill shows them (a Steam game still downloading).
    var primaryWaveDots = false
    var primaryQueued = false
    var primaryDownloadFill: Double? = nil
    /// The cloud badge pill between Options and favorite (index 2, favorite moves to 3), as on Details.
    var cloud: CloudLibraryIndicator? = nil
    let onAction: (Int) -> Void
    var onHover: (Int) -> Void = { _ in }
    @Environment(\.seleneCanvas) private var canvas
    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
            if primaryQueued {
                pill(0, SelenePillButton.buildQueue(focused: focused == 0) { onAction(0) })
            } else {
                pill(0, SelenePillButton(title: primaryTitle, height: 52, focused: focused == 0,
                                        enabled: primaryEnabled, waveDots: primaryWaveDots,
                                        downloadFill: primaryDownloadFill) { onAction(0) })
            }
            pill(1, SelenePillButton(title: secondaryTitle, height: 52, focused: focused == 1) { onAction(1) })
            if let cloud {
                pill(2, CloudLibraryPill(indicator: cloud, focused: focused == 2) { onAction(2) })
            }
            let favorite = cloud == nil ? 2 : 3
            pill(favorite, SelenePillButton(title: nil, icon: isFavorite ? .favorite : .favoriteBorder,
                                    iconSize: 20, minWidth: 52, height: 52, horizontalPadding: 0,
                                    focused: focused == favorite) { onAction(favorite) })
                .accessibilityLabel(isFavorite ? L10n.text("Remove from favorites") : L10n.text("Add to favorites"))
        }
    }
    private func pill<V: View>(_ index: Int, _ view: V) -> some View {
        view.frame(height: canvas.u(60)).seleneHover { onHover(index) }
    }
}
