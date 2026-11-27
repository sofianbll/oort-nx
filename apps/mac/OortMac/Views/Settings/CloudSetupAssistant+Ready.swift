import OortLibrary
import NxnativeAdapter
import SwiftUI

/// Step 3: both folders answered, what is in them, and the way to the games.
extension CloudSetupAssistant {
    var ready: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
                summary(.sources, icon: .storage, path: sourcesOverride ?? sources?.path ?? defaultSourcesPath, line: sourcesLine)
                summary(.library, icon: .cloudDone, path: draft.path, line: libraryLine)
                state
            }
            .padding(canvas.u(SeleneTokens.Space.hairline))
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func summary(_ folder: Folder, icon: MaterialIcon, path: String, line: String) -> some View {
        OortFolderCard(icon: icon, title: text(folder == .library ? "Game library" : "ROM library"), about: line,
                       account: text("Google Drive"), path: shownPath(path), placeholder: "", status: { EmptyView() }, actions: { EmptyView() })
            .accessibilityElement(children: .combine)
    }

    private var libraryLine: String {
        guard let games = library?.games else { return text("Oort puts its apps there. An empty folder is fine.") }
        return games == 0 ? text("Empty for now: your games will go there.") : L10n.count("%lld compiled games", games, context: localization)
    }

    private var sourcesLine: String {
        guard let sources else { return text("No folder chosen yet") }
        guard let left = index?.gamesToCompile(sources: sourcesOverride ?? sources.path, library: draft.path) ?? sources.games else {
            return text("The files you bring. Oort changes nothing there unless you ask.")
        }
        return left == 0 && (sources.games ?? 0) == 0 ? text("No game in it yet. Put your ROMs there.")
            : L10n.count("%lld games to compile", left, context: localization)
    }

    @ViewBuilder private var state: some View {
        if let move {
            let status = CloudLibraryStatus.pending
            SeleneStatusDot(text: text(move.isVerifying ? "Verifying the move…" : move.isCancelling ? "Cancelling…" : "Moving games…"),
                            color: status.color, pulses: !move.isCancelling, font: .row)
            OortMeter(share: move.fraction, fill: status.color)
        } else if work != nil { progress("Checking…") }
        else if draft.verified {
            SeleneStatusDot(text: text("Connection OK"), color: SeleneTheme.statusOK, labelColor: SeleneTheme.ink90, font: .row)
        } else if !movePaused { cardKey(.retry, "Try again", action: verify) }
    }
}
