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
    /// Wikipedia's introduction for a short or foreign-language store text (`WikipediaAbout`).
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
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink90)
                    .padding(.leading, canvas.u(SeleneTokens.Space.seam))
                    .padding(.top, canvas.u(SeleneTokens.Space.medium))
            }
            if case .failed(let failure) = pillSet {
                Text(failure == .cancelled ? L10n.text("Porting cancelled") : L10n.text("Porting failed"))
                    .seleneFont(.text, .semibold)
                    .foregroundColor(PortingPillCopy.softRed)
                    .padding(.leading, canvas.u(SeleneTokens.Space.hairline))
                    .padding(.top, canvas.u(SeleneTokens.Space.titleGap))
            }
            if let reason = pillSet.unavailableReason, downloadItem == nil, storeNote == nil {
                Text(reason.title)
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.ink75)
                    .padding(.leading, canvas.u(SeleneTokens.Space.hairline))
                    .padding(.top, canvas.u(SeleneTokens.Space.titleGap))
            }
            HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                pills
                if showsCloudPill && (pillSet == .porting || pillSet.isFailed) { cloudPill }
            }
                .padding(.top, canvas.u(pillSet.isFailed ? 10 : 26))
            if downloadFill != nil,
               let bytes = CloudLibraryProgressView.bytesSummary(transferState.progress, context: localization) {
                Text(bytes).seleneFont(.text).monospacedDigit().foregroundColor(SeleneTheme.ink75)
                    .padding(.top, canvas.u(SeleneTokens.Space.small))
            } else if let active = transferState.activeItem, !transferState.queued, active != .sources,
                      downloadStatus == nil || active != downloadItem {
                CloudLibraryProgressView(progress: transferState.progress, showsBar: true)
                    .frame(maxWidth: canvas.u(SeleneTokens.Space.transferMeasure), alignment: .leading)
                    .padding(.top, canvas.u(SeleneTokens.Space.small))
            } else if let issue = cloud.states[game.id]?.issue, issue.item != .sources {
                Text(issue.message).seleneFont(.text)
                    .foregroundColor((issue.failed ? CloudLibraryStatus.failed : .unknown).color)
                    .padding(.top, canvas.u(SeleneTokens.Space.small))
            }
            if let storeNote {
                Text(storeNote).seleneFont(.text).foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, canvas.u(SeleneTokens.Space.hairline))
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
        .oortShadow(.text)
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
                    .oortShadow(.text)
            } else {
                Text(game.name)
                    .seleneFont(.hero)
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
                Text(etaText).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
            }
        case .normalAfterFailure(let failure):
            Button(action: onOpenLog) {
                Text(PortingPillCopy.lastFailure(failure, reason: game.portingFailureReason))
                    .seleneFont(.text).foregroundColor(SeleneTheme.ink60)
            }
            .buttonStyle(OortPressStyle())
        case .failed(let failure):
            if failure == .failed, let reason = game.portingFailureReason {
                Text(reason.title).seleneFont(.text).foregroundColor(SeleneTheme.ink60)
            }
        case .unavailable(let reason) where downloadItem == nil && storeNote == nil:
            Text(reason.detail).seleneFont(.text).foregroundColor(SeleneTheme.ink60)
        case .normal, .unavailable:
            if downloadItem != nil || storeNote != nil {
                EmptyView()
            } else if !canCheckCloudSources && !game.sources.isEmpty && !GameResourceState.sourcesAvailable(for: game) {
                Text(L10n.text("Game files not found · Rebuild unavailable")).seleneFont(.text).foregroundColor(SeleneTheme.ink60)
            } else if !game.isPlayableLocally {
                Text(L10n.text("Not built yet")).seleneFont(.text).foregroundColor(SeleneTheme.ink82)
            }
        }
    }

    @ViewBuilder private var pills: some View {
        switch pillSet {
        case .porting:
            SelenePillButton(title: L10n.text("Porting"), minWidth: 200, height: 52, horizontalPadding: 36,
                             focused: focusedPill == 0, waveDots: true) { onPill(0) }
                .seleneHover { onHoverPill(0) }
                .accessibilityLabel(L10n.text("Porting, show progress"))
        case .failed:
            HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                ForEach(Array(PortingPillCopy.failedTitles.enumerated()), id: \.offset) { index, title in
                    SelenePillButton(title: title, minWidth: 200, height: 52, horizontalPadding: 36,
                                     focused: focusedPill == index) { onPill(index) }
                        .seleneHover { onHoverPill(index) }
                }
            }
        case .normal, .queued, .normalAfterFailure, .unavailable:
            normalPills
        }
    }

    private var normalPills: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
            Group {
                if pillSet == .queued {
                    SelenePillButton.buildQueue(minWidth: 200, focused: focusedPill == 0, action: onPrimary)
                } else if let downloadStatus {
                    if let downloadFill {
                        // Still a gauge during byte transfer; never a clickable or focused button.
                        SelenePillButton(title: downloadStatus, minWidth: 200, height: 52,
                                         horizontalPadding: 24, focused: false, downloadFill: downloadFill,
                                         passive: true, action: {})
                    } else {
                        HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                            SeleneStatusMark(color: CloudLibraryStatus.pending.color, pulses: false)
                            Text(text(downloadStatus)).seleneFont(.text).foregroundColor(SeleneTheme.ink90)
                        }
                        .frame(minWidth: canvas.u(200), minHeight: canvas.u(52), alignment: .leading)
                    }
                } else {
                    SelenePillButton(title: primaryTitle, minWidth: 200, height: 52,
                                     horizontalPadding: 36, focused: focusedPill == 0,
                                     enabled: isRunning || downloadItem != nil || (primaryEnabled && pillSet.unavailableReason == nil),
                                     action: onPrimary)
                }
            }
            .seleneHover { if downloadStatus == nil { onHoverPill(0) } }
            SelenePillButton(title: isRunning ? "Close Game" : "Options", minWidth: 200, height: 52,
                             horizontalPadding: 36, focused: focusedPill == 1,
                             action: onSecondary)
                .seleneHover { onHoverPill(1) }
            if showsCloudPill { cloudPill }
            let favorite = pillSet.count - 1 + (showsCloudPill ? 1 : 0)
            SelenePillButton(title: nil, icon: game.isFavorite ? .favorite : .favoriteBorder,
                             iconSize: 20, minWidth: 52, height: 52, horizontalPadding: 0,
                             focused: focusedPill == favorite, action: onFavorite)
                .seleneHover { onHoverPill(favorite) }
                .accessibilityLabel(game.isFavorite ? L10n.text("Remove from favorites") : L10n.text("Add to favorites"))
        }
    }

    private var cloudPill: some View {
        let index = pillSet.detailsCloudIndex
        let indicator = CloudLibraryIndicator(state: cloud.states[game.id] ?? CloudLibraryState())
        return CloudLibraryPill(indicator: indicator, focused: focusedPill == index, showsTransferDot: false) { onPill(index) }
            .seleneHover { onHoverPill(index) }
    }

    private var primaryTitle: String {
        if isRunning { return "Resume" }
        if let downloadItem { return downloadItem == .app ? "Download app" : downloadItem.primaryDownloadTitle }
        if pillSet.unavailableReason != nil ||
            (!primaryEnabled && !presentation.canRebuild && !canCheckCloudSources) { return "Unavailable" }
        return presentation.canPlay ? "Play" : "Build"
    }

    private var downloadItem: CloudLibraryItem? {
        isRunning ? nil : cloud.downloadItem(for: game)
    }

    private var showsDownloadPill: Bool {
        downloadItem != nil && pillSet != .queued && pillSet != .porting && !pillSet.isFailed
    }

    private var transferState: CloudLibraryState { cloud.states[game.id] ?? CloudLibraryState() }

    static func canDownload(_ allowed: Bool, state: CloudLibraryState?) -> Bool {
        allowed && state?.action == nil && state?.refreshing != true
    }

    private var downloadStatus: String? {
        guard showsDownloadPill, let item = downloadItem else { return nil }
        guard !Self.canDownload(downloadEnabled, state: transferState) else { return nil }
        if transferState.activeItem == item {
            if transferState.queued { return "Queued" }
            if let progress = transferState.progress {
                if progress.phase == .readyToInstall { return "Waiting for the game to close…" }
                return CloudLibraryProgressView.phaseKey(progress)
            }
            return "Preparing cloud operation…"
        }
        if transferState.refreshing { return "Checking…" }
        return "Download unavailable"
    }

    private var downloadFill: Double? {
        guard showsDownloadPill, let item = downloadItem, case .running = transferState.transfer(for: item),
              let fill = CloudLibraryProgressView.downloadFill(transferState, item: item), fill < 1 else { return nil }
        return fill
    }

    private func text(_ key: String) -> String { L10n.text(key, context: localization) }

    private var storeNote: String? {
        guard game.platform == .macApp, game.titleId != nil,
              pillSet != .queued, pillSet != .porting, !pillSet.isFailed else { return nil }
        if isRunning || presentation.canPlay { return text("App on this Mac") }
        let state = transferState
        let last = cloud.lastKnown
        let unverified = cloud.hasCloudReadFailure || state.failure != nil || state.referenceUnverified
        if let downloadItem {
            let key: String
            if downloadItem == .app {
                let personal = (state.copies[.app] ?? state.availability[.app])?.state == .cloudOnly
                    || last.personalApps.contains(game.id)
                let reference = state.referenceAvailability[.app]?.state == .cloudOnly || last.referenceApps.contains(game.id)
                key = reference ? (personal ? "App in both cloud libraries" : "App in the reference library") : "App in your cloud"
            } else {
                let reference = game.cloudSourcesReferenceFolder != nil || state.referenceSourceBytes != nil
                    || (last.referenceFiles.contains(game.id) && !last.personalFiles.contains(game.id))
                key = reference ? "Game files in the reference library" : "Game files in your cloud"
            }
            let stale = unverified || (downloadItem == .sources && (state.sourceFailure != nil || state.referenceSourcesUnverified))
            let origin = stale ? L10n.format("Last known location: %@", [text(key)], context: localization) : text(key)
            return downloadItem == .sources ? origin + " · " + text("Build after downloading") : origin
        }
        if presentation.canRebuild {
            let origin = text("Game files on this Mac")
            if !primaryEnabled { return origin + " · " + text("Check the engine before building") }
            if pillSet.unavailableReason != nil { return origin + " · " + text("Build from Options") }
            return origin
        }
        if unverified || state.sourceFailure != nil || state.referenceSourcesUnverified || cloud.startupFailure != nil {
            return text("Cloud unavailable")
        }
        if cloud.archive != nil && !cloud.catalogChecked { return text("Cloud not verified") }
        if canCheckCloudSources { return nil }
        return L10n.format("Find your game files in %@ → %@", [text("Options"), text("Edit details")], context: localization)
    }

    // MARK: - Stats

    /// PLAYTIME · LAST PLAYED · RELEASED · CHEATS · PLATFORM, 28 either side of each rule.
    private var stats: some View {
        var items = [
            SeleneStat.text(text("PLAYTIME"), presentation.playtime),
            SeleneStat.text(text("LAST PLAYED"), presentation.lastPlayed)
        ]
        if let released = presentation.released {
            items.append(SeleneStat.text(text("RELEASED"), released))
        }
        if cheatsOn {
            items.append(SeleneStat.text(text("CHEATS"), text("On")))
        }
        items.append(SeleneStat(label: text("PLATFORM"), value: .platform(presentation.console)))
        return SeleneStatsRow(items: items, gap: 28)
            .padding(.leading, canvas.u(SeleneTokens.Space.hairline))
    }

    // MARK: - Genres

    private var genres: some View {
        HStack(spacing: 0) {
            ForEach(Array(presentation.genres.prefix(6)), id: \.self) { genre in
                Text(genre)
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink90)
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
                    .padding(.vertical, canvas.u(SeleneTokens.Space.hairline))
                    .oortPanel(radius: canvas.u(SeleneTokens.Radius.badge))
                    .padding(.trailing, canvas.u(SeleneTokens.Space.compact))
                    .padding(.bottom, canvas.u(SeleneTokens.Space.compact))
            }
        }
        .padding(.leading, canvas.u(SeleneTokens.Space.seam))
    }

    // MARK: - Description

    @ViewBuilder
    private var description: some View {
        let about = presentation.aboutDescription(wikipedia: wikipedia, language: localization.language)
        let showingPreview = !expanded && about.preview != nil
        let note = about.note(showingPreview: showingPreview)
        let text = showingPreview ? about.preview ?? about.text : about.text
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            if text.isEmpty {
                Text(self.text("No description for this game yet."))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink60)
            } else {
                // Keep the action clear of the fixed screenshot band, even with a source and language note.
                HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                    if let note {
                        Text(note).seleneFont(.text).foregroundColor(SeleneTheme.ink60)
                    }
                    if !showingPreview, let page = about.wikipediaPage {
                        WikipediaCredit(pageURL: page)
                    }
                    if about.text.count > Self.readMoreThreshold || about.preview != nil {
                        Button(expanded ? L10n.text("Show less") : L10n.text("Read more")) { expanded.toggle() }
                            .buttonStyle(OortPressStyle())
                            .seleneFont(.text, .semibold)
                            .foregroundColor(SeleneTheme.glyph)
                    }
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
            }
        }
        .padding(.leading, canvas.u(SeleneTokens.Space.seam))
        .frame(minWidth: canvas.u(700), maxWidth: canvas.u(1034), alignment: .leading)
    }

    private func descriptionText(_ text: String) -> some View {
        Text(text)
            .seleneFont(.text)
            .lineSpacing(canvas.u(3))
            .foregroundColor(SeleneTheme.ink90)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }
}
