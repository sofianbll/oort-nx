import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// The Details top block (Selene GameDetails `SeleneDetailsTop`): the logo (or
/// the name), the developer line, the Play or Build, Options and Favorite pills,
/// the stats row, the genre chips and the description. A 1060-wide column
/// placed at (110, 96) on the stage; every length is in Selene units.
struct DetailsTopBlock: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization

    let game: PortedGame
    let logo: NSImage?
    let presentation: GameDetailPresentation
    /// The game is running: the primary pill reads Resume and the second reads Close Game.
    let isRunning: Bool
    /// The quiet "Cheats on" stat: cheats on and at least one switch on (CheatsModel.cheatsOn).
    var cheatsOn = false
    /// The focused pill, or nil when the block has no focus.
    let focusedPill: Int?
    /// Build is dim (no sources to build from) but still takes focus.
    let primaryEnabled: Bool
    /// Description expanded by "Read more" (the page passes wheel scrolling through meanwhile).
    @Binding var expanded: Bool
    /// Wikipedia's introduction, shown instead of a store text in another language (`WikipediaAbout`).
    var wikipedia: WikipediaDescription? = nil
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    let onFavorite: () -> Void
    let onHoverPill: (Int) -> Void
    /// The pills follow the porting (`PortingPills`); any pill press goes to `onPill`.
    let pillSet: PortingPills
    var etaText: String? = nil
    @ObservedObject var cloud: CloudLibraryModel
    let showsCloudPill: Bool
    var downloadEnabled = false
    var canCheckCloudSources = false
    var onPill: (Int) -> Void = { _ in }
    var onOpenLog: () -> Void = {}

    /// Longer than this, the description gets a "Read more" (five lines hold about 520 characters at this width).
    static let readMoreThreshold = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logoArea
            if let developer = presentation.developerLine {
                Text(developer)
                    .seleneFont(.body)
                    .foregroundColor(SeleneTheme.ink90)
                    .padding(.leading, canvas.u(SeleneTokens.Space.seam))
                    .padding(.top, canvas.u(SeleneTokens.Space.medium))
            }
            if case .failed(let failure) = pillSet {
                Text(failure == .cancelled ? L10n.text("Porting cancelled") : L10n.text("Porting failed"))
                    .seleneFont(.panelBody, .semibold)
                    .foregroundColor(PortingPillCopy.softRed)
                    .padding(.leading, canvas.u(SeleneTokens.Space.hairline))
                    .padding(.top, canvas.u(SeleneTokens.Space.titleGap))
            }
            if let reason = pillSet.unavailableReason, downloadItem == nil {
                Text(reason.title)
                    .seleneFont(.panelBody, .semibold)
                    .foregroundColor(SeleneTheme.ink75)
                    .padding(.leading, canvas.u(SeleneTokens.Space.hairline))
                    .padding(.top, canvas.u(SeleneTokens.Space.titleGap))
            }
            HStack(spacing: canvas.u(14)) {
                pills
                if showsCloudPill && (pillSet == .porting || pillSet.isFailed) { cloudPill }
                NextendoOnlineBadge(titleID: game.titleId)
            }
                .padding(.top, canvas.u(pillSet.isFailed ? 10 : 26))
            if let state = cloud.states[game.id], let active = state.activeItem, active != .sources, !state.queued {
                CloudLibraryProgressView(progress: state.progress,
                    showsBar: !showsDownloadPill || downloadItem.flatMap { CloudLibraryProgressView.downloadFill(state, item: $0) } == nil)
                    .frame(maxWidth: canvas.u(SeleneTokens.Space.transferMeasure), alignment: .leading)
                    .padding(.top, canvas.u(SeleneTokens.Space.small))
            } else if let issue = cloud.states[game.id]?.issue, issue.item != .sources {
                Text(issue.message).seleneFont(.compactCaption)
                    .foregroundColor((issue.failed ? CloudLibraryStatus.failed : .unknown).color)
                    .padding(.top, canvas.u(SeleneTokens.Space.small))
            }
            portingNote
                .padding(.leading, canvas.u(SeleneTokens.Space.hairline))
                .padding(.top, canvas.u(SeleneTokens.Space.small))
            stats
                .padding(.top, canvas.u(SeleneTokens.Space.feature))
            if !presentation.genres.isEmpty {
                genres
                    .padding(.top, canvas.u(SeleneTokens.Space.titleGap))
            }
            description
                .padding(.top, canvas.u(SeleneTokens.Space.control))
        }
        .frame(width: canvas.u(1060), alignment: .topLeading)
        .shadow(color: .black.opacity(0.45), radius: canvas.u(4))
    }

    // MARK: - Logo

    private var logoArea: some View {
        ZStack(alignment: .bottomLeading) {
            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: canvas.u(760), maxHeight: canvas.u(200), alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.35), radius: canvas.u(8))
            } else {
                Text(game.name)
                    .seleneFont(.heroTitle)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: canvas.u(1060), alignment: .leading)
            }
        }
        .frame(width: canvas.u(1060), height: canvas.u(200), alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Pills

    @ViewBuilder private var portingNote: some View {
        switch pillSet {
        case .queued:
            EmptyView()
        case .porting:
            if let etaText {
                Text(etaText).seleneFont(.caption).foregroundColor(SeleneTheme.ink75)
            }
        case .normalAfterFailure(let failure):
            Button(action: onOpenLog) {
                Text(PortingPillCopy.lastFailure(failure, reason: game.portingFailureReason))
                    .seleneFont(.compactCaption).foregroundColor(SeleneTheme.ink60)
            }
            .buttonStyle(.plain)
        case .failed(let failure):
            if failure == .failed, let reason = game.portingFailureReason {
                Text(reason.title).seleneFont(.compactCaption).foregroundColor(SeleneTheme.ink60)
            }
        case .unavailable(let reason) where downloadItem == nil:
            Text(reason.detail).seleneFont(.compactCaption).foregroundColor(SeleneTheme.ink60)
        case .normal, .unavailable:
            if downloadItem != nil {
                EmptyView()
            } else if !canCheckCloudSources && !game.sources.isEmpty && !GameResourceState.sourcesAvailable(for: game) {
                Text(L10n.text("Game files not found · Rebuild unavailable")).seleneFont(.compactCaption).foregroundColor(SeleneTheme.ink60)
            } else if !game.isPlayableLocally {
                Text(L10n.text("Not built yet")).seleneFont(.compactCaption).foregroundColor(SeleneTheme.ink60)
            }
        }
    }

    @ViewBuilder private var pills: some View {
        switch pillSet {
        case .porting:
            SelenePillButton(title: L10n.text("Porting"), minWidth: 200, height: 52, horizontalPadding: 36,
                             focused: focusedPill == 0, waveDots: true) { onPill(0) }
                .onHover { if $0 { onHoverPill(0) } }
                .accessibilityLabel(L10n.text("Porting, show progress"))
        case .failed:
            HStack(spacing: canvas.u(14)) {
                ForEach(Array(PortingPillCopy.failedTitles.enumerated()), id: \.offset) { index, title in
                    SelenePillButton(title: title, minWidth: 200, height: 52, horizontalPadding: 36,
                                     focused: focusedPill == index) { onPill(index) }
                        .onHover { if $0 { onHoverPill(index) } }
                }
            }
        case .normal, .queued, .normalAfterFailure, .unavailable:
            normalPills
        }
    }

    private var normalPills: some View {
        let state = cloud.states[game.id] ?? CloudLibraryState()
        return HStack(spacing: canvas.u(14)) {
            Group {
                if pillSet == .queued {
                    SelenePillButton.buildQueue(minWidth: 200, focused: focusedPill == 0, action: onPrimary)
                } else {
                    SelenePillButton(title: primaryTitle, minWidth: 200, height: 52,
                                     horizontalPadding: 36, focused: focusedPill == 0,
                                     enabled: isRunning || (downloadItem != nil ? downloadEnabled && cloud.states[game.id]?.action == nil
                                         && cloud.states[game.id]?.refreshing != true
                                         : primaryEnabled && pillSet.unavailableReason == nil),
                                     downloadFill: showsDownloadPill
                                         ? downloadItem.flatMap { CloudLibraryProgressView.downloadFill(state, item: $0) } ?? 0 : nil,
                                     action: onPrimary)
                }
            }
            .onHover { if $0 { onHoverPill(0) } }
            SelenePillButton(title: isRunning ? L10n.text("Close Game") : L10n.text("Options"), minWidth: 200, height: 52,
                             horizontalPadding: 36, focused: focusedPill == 1,
                             action: onSecondary)
                .onHover { if $0 { onHoverPill(1) } }
            if showsCloudPill { cloudPill }
            let favorite = pillSet.count - 1 + (showsCloudPill ? 1 : 0)
            SelenePillButton(title: nil, icon: game.isFavorite ? .favorite : .favoriteBorder,
                             iconSize: 20, minWidth: 52, height: 52, horizontalPadding: 0,
                             focused: focusedPill == favorite, action: onFavorite)
                .onHover { if $0 { onHoverPill(favorite) } }
                .accessibilityLabel(game.isFavorite ? L10n.text("Remove from favorites") : L10n.text("Add to favorites"))
        }
    }

    private var cloudPill: some View {
        let index = pillSet.detailsCloudIndex
        let indicator = CloudLibraryIndicator(state: cloud.states[game.id] ?? CloudLibraryState())
        return CloudLibraryPill(indicator: indicator, focused: focusedPill == index, showsTransferDot: false) { onPill(index) }
            .onHover { if $0 { onHoverPill(index) } }
    }

    private var primaryTitle: String {
        if isRunning { return L10n.text("Resume") }
        if let downloadItem { return L10n.text(downloadItem.primaryDownloadTitle) }
        if pillSet.unavailableReason != nil { return L10n.text("Unavailable") }
        return presentation.canPlay ? L10n.text("Play") : "Build"
    }

    private var downloadItem: CloudLibraryItem? {
        isRunning ? nil : cloud.downloadItem(for: game)
    }

    private var showsDownloadPill: Bool {
        downloadItem != nil && pillSet != .queued && pillSet != .porting && !pillSet.isFailed
    }

    // MARK: - Stats

    /// PLAYTIME · LAST PLAYED · RELEASED · CHEATS · PLATFORM, 28 either side of each rule.
    private var stats: some View {
        var items = [
            SeleneStat.text(L10n.text("PLAYTIME"), presentation.playtime),
            SeleneStat.text(L10n.text("LAST PLAYED"), presentation.lastPlayed)
        ]
        if let released = presentation.released {
            items.append(SeleneStat.text(L10n.text("RELEASED"), released))
        }
        if cheatsOn {
            items.append(SeleneStat.text(L10n.text("CHEATS"), L10n.text("On")))
        }
        items.append(SeleneStat.platform(presentation.console))
        return SeleneStatsRow(items: items, gap: 28)
            .padding(.leading, canvas.u(SeleneTokens.Space.hairline))
    }

    // MARK: - Genres

    private var genres: some View {
        HStack(spacing: 0) {
            ForEach(Array(presentation.genres.prefix(6)), id: \.self) { genre in
                Text(genre)
                    .seleneFont(.compactCaption)
                    .foregroundColor(SeleneTheme.ink90)
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
                    .padding(.vertical, canvas.u(SeleneTokens.Space.hairline))
                    .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge), style: .continuous)
                        .fill(SeleneTheme.ink15))
                    .padding(.trailing, canvas.u(SeleneTokens.Space.compact))
                    .padding(.bottom, canvas.u(SeleneTokens.Space.compact))
            }
        }
        .padding(.leading, canvas.u(SeleneTokens.Space.seam))
    }

    // MARK: - Description

    @ViewBuilder
    private var description: some View {
        let text = wikipedia?.text ?? presentation.description
        VStack(alignment: .leading, spacing: canvas.u(6)) {
            if text.isEmpty {
                Text(L10n.text("No description for this game yet."))
                    .seleneFont(.body)
                    .foregroundColor(SeleneTheme.ink60)
            } else {
                if let wikipedia {
                    WikipediaCredit(pageURL: wikipedia.pageURL)
                } else if let note = presentation.descriptionLanguageNote {
                    Text(note).seleneFont(.metadata).foregroundColor(SeleneTheme.ink60)
                }
                if expanded {
                    ScrollView(.vertical, showsIndicators: false) {
                        descriptionText(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: canvas.u(130))
                } else {
                    descriptionText(text)
                        .lineLimit(5)
                        .frame(maxHeight: canvas.u(130), alignment: .top)
                        .clipped()
                }
                if text.count > Self.readMoreThreshold {
                    Button(expanded ? L10n.text("Show less") : L10n.text("Read more")) { expanded.toggle() }
                        .buttonStyle(.plain)
                        .seleneFont(.compactCaption, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                }
            }
        }
        .padding(.leading, canvas.u(SeleneTokens.Space.seam))
        .frame(minWidth: canvas.u(700), maxWidth: canvas.u(1034), alignment: .leading)
    }

    private func descriptionText(_ text: String) -> some View {
        Text(text)
            .seleneFont(.body)
            .lineSpacing(canvas.u(3))
            .foregroundColor(SeleneTheme.ink90)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }
}
