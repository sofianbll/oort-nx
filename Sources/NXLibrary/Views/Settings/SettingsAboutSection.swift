import SwiftUI
import AppKit
import NXLibraryCore

struct SettingsAboutSection: View {
    @ObservedObject var viewModel: AppViewModel
    /// The Setup (`SetupModel`): an available release names the Xcode it needs.
    @ObservedObject var setup: SetupModel
    @EnvironmentObject private var updater: AppUpdater
    @Environment(\.seleneFocusedRowID) private var focusedRowTitle
    @Environment(\.seleneFocusedButton) private var focusedButton
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.openURL) private var openURL
    let onActions: ([SettingsRowAction]) -> Void

    @State private var didCopyDiagnostics = false
    private static let fundingRow = "oort-funding"
    private static let fundingMark: OortCreditCard.Mark = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return .glyph(.favorite) }
        return .art(image)
    }()
    private static let docsRow = "Open project docs"
    private static let diagnosticsRow = "Copy diagnostics"
    private static let noticeRow = "credits-notice"

    /// Categories whose cards are shown; the first is always open.
    @State private var opened: Set<String>

    private let credits = Credits.bundled
    private let groups = Credits.bundled?.groups(for: .mac) ?? []

    init(viewModel: AppViewModel, setup: SetupModel, opened: Set<String> = [], onActions: @escaping ([SettingsRowAction]) -> Void) {
        self.viewModel = viewModel
        self.setup = setup
        self.onActions = onActions
        _opened = State(initialValue: opened)
    }

    var body: some View {
        OortSettingsGroup {
            SelenePanel(AppIdentity.displayName) {
                Text(L10n.text("A free, open-source game library and launcher for Mac. Play installed games and port compatible Switch titles with nxnative."))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.format("Version %@ · Build %@ · Engine %@", [version, buildLabel, seleneShort(viewModel.pinnedEngineCommit)]))
                    .seleneFont(.badge, .regular, design: .monospaced)
                    .foregroundColor(SeleneTheme.ink60)
                Text(L10n.format("Based on %@ %@, by %@", [AppIdentity.name, "0.2.1", "Bium23"], context: localization))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink90)
                Text(L10n.text("Play time is tracked only for launches from Arcane. Not affiliated with Nintendo."))
                    .seleneFont(.badge)
                    .foregroundColor(SeleneTheme.ink60)
                updateRow
            }

            OortSettingsLink(id: Self.docsRow, title: L10n.text("Open project docs"), action: openProjectDocs)
            OortSettingsLink(id: Self.diagnosticsRow, title: L10n.text(didCopyDiagnostics ? "Copied" : "Copy diagnostics"),
                             subtitle: L10n.text("A report for an issue: versions, setup and the last porting. No keys."),
                             action: copyDiagnostics)

            fundingButton

            if let credits {
                ForEach(groups) { group in
                    if group.id == groups.first?.id {
                        SettingsSubheading(Credits.words(group.category.title, in: language))
                            .accessibilityAddTraits(.isHeader)
                    } else {
                        OortSettingsLink(id: "credits-\(group.id)", title: Credits.words(group.category.title, in: language),
                                         value: "\(group.credits.count)", expanded: shows(group)) { toggle(group.id) }
                    }
                    if shows(group) {
                        OortCreditGroup(group: group, credits: credits, focusedCard: focusedCard(in: group), open: open)
                    }
                }

                SelenePanel(Credits.words(credits.labels["legal"] ?? [:], in: language)) {
                    ForEach(credits.statements(for: .mac, in: language), id: \.self) { statement in
                        Text(verbatim: statement)
                            .seleneFont(.badge)
                            .foregroundColor(SeleneTheme.ink75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                OortSettingsLink(id: Self.noticeRow, title: credits.label("notice", in: language), action: openNotice)
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: localization.language) { publishActions() }
        .onChange(of: updater.state) { publishActions() }
        .onChange(of: opened) { publishActions() }
        .onChange(of: viewModel.isBuilding) { publishActions() }
        .onChange(of: viewModel.isCleaningStorage) { publishActions() }
        .onChange(of: viewModel.hasActiveSaveOperations) { publishActions() }
        .onChange(of: viewModel.isUpdatingApp) { publishActions() }
        .onChange(of: viewModel.runningGameCount) { publishActions() }
    }

    private var language: String { localization.language.rawValue }
    private var fundingTitle: String { L10n.text("Support Oort NX", context: localization) }

    private var fundingButton: some View {
        OortCreditCard(mark: Self.fundingMark, name: fundingTitle,
                       byline: L10n.text("Sofian develops and maintains Oort NX.", context: localization),
                       hint: L10n.text("Opens in your browser", context: localization),
                       focused: focusedRowTitle == Self.fundingRow, action: openFundingPage)
            .id("selene-row-\(Self.fundingRow)")
    }

    private func shows(_ group: Credits.Group) -> Bool { group.id == groups.first?.id || opened.contains(group.id) }

    private func toggle(_ id: String) {
        withAnimation(Motion.focus(reduceMotion)) { opened.formSymmetricDifference([id]) }
    }

    private func focusedCard(in group: Credits.Group) -> String? {
        guard let line = OortCreditGroup.lines(group).first(where: { $0.id == focusedRowTitle }) else { return nil }
        return line.credits[min(focusedButton, line.credits.count - 1)].id
    }

    private func open(_ credit: Credits.Credit) { NSWorkspace.shared.open(credit.url) }

    /// The notices as shipped, read in the Mac's own text editor; their public copy when the app has none (a test).
    private func openNotice() {
        let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        if let notice = Bundle.main.url(forResource: "NOTICE", withExtension: nil), let editor {
            NSWorkspace.shared.open([notice], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = URL(string: AppIdentity.projectPage + "/blob/main/NOTICE") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyDiagnostics() {
        viewModel.copyDiagnostics()
        didCopyDiagnostics = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { didCopyDiagnostics = false }
    }

    private func publishActions() {
        var actions = updateActions.map { action in
            SettingsRowAction(id: "update-\(action.title)", title: action.title,
                              isEnabled: action.enabled, activate: action.perform)
        }
        actions.append(.init(id: "docs", title: "Open project docs", rowID: Self.docsRow, activate: openProjectDocs))
        actions.append(.init(id: "diagnostics", title: "Copy diagnostics", rowID: Self.diagnosticsRow, activate: copyDiagnostics))
        actions.append(.init(id: Self.fundingRow, title: fundingTitle, rowID: Self.fundingRow, activate: openFundingPage))
        for group in groups {
            if group.id != groups.first?.id {
                actions.append(.init(id: "credits-\(group.id)", title: Credits.words(group.category.title, in: language),
                                     rowID: "credits-\(group.id)") { toggle(group.id) })
            }
            guard shows(group) else { continue }
            actions += OortCreditGroup.lines(group).map { line in
                let opens = line.credits.map { credit in { open(credit) } }
                return SettingsRowAction(id: line.id, title: line.credits[0].name, rowID: line.id,
                                         additionalButtons: Array(opens.dropFirst()), activate: opens[0])
            }
        }
        if credits != nil {
            actions.append(.init(id: "notice", title: "NOTICE", rowID: Self.noticeRow, activate: openNotice))
        }
        onActions(actions)
    }

    // MARK: - Updates

    private struct UpdateAction {
        let title: String
        var enabled = true
        let perform: () -> Void
    }

    @ViewBuilder private var updateRow: some View {
        if updater.state != .hidden {
            HStack(spacing: SeleneTokens.Space.line) {
                Text(updateText)
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                ForEach(updateActions, id: \.title) { action in
                    OortButton(title: action.title, focused: focusedRowTitle == action.title,
                               state: action.enabled ? .ready : .blocked, preset: .compact, action: action.perform)
                        .id("selene-row-\(action.title)")
                }
            }
        }
    }

    private var updateText: String {
        switch updater.state {
        case .hidden: return ""
        case .developer: return L10n.text("Development copy · manual checks only")
        case .readOnly: return L10n.text("Move Arcane to Applications to update")
        case .idle: return L10n.text("Updates not checked yet")
        case .checking: return "Checking for updates…"
        case .upToDate: return L10n.text("Arcane is up to date")
        case .available(let release):
            let xcode = AppUpdate.neededXcode(release.requirements, installedXcode: setup.environmentStatus?.xcodeVersion)
                .map { L10n.format(" · new portings need Xcode %@", [String(describing: $0)]) } ?? ""
            return (updater.blockedReason().map { L10n.format("%@ is available · %@", [String(describing: release.version), String(describing: $0)]) } ?? L10n.format("%@ is available", [String(describing: release.version)])) + xcode
        case .readyToInstall: return L10n.text("Update ready to install")
        case .downloading(let fraction): return L10n.format("Downloading %@%%", [String(describing: Int((fraction * 100).rounded()))])
        case .verifying: return L10n.text("Checking download…")
        case .installing: return L10n.text("Installing…")
        case .failed(let message): return message
        }
    }

    private var updateActions: [UpdateAction] {
        let checkNow = UpdateAction(title: L10n.text("Check now")) { updater.checkNow() }
        switch updater.state {
        case .hidden, .checking, .downloading, .verifying, .installing:
            return []
        case .readOnly:
            return [checkNow, UpdateAction(title: L10n.text("Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }]
        case .developer, .idle, .upToDate:
            return [checkNow]
        case .available:
            return [UpdateAction(title: L10n.text("View update")) { updater.showDetails() }, checkNow]
        case .readyToInstall:
            return [UpdateAction(title: L10n.text("View update")) { updater.showDetails() }]
        case .failed:
            return [checkNow]
        }
    }

    private var version: String {
        AppUpdate.versionLabel(Bundle.main.infoDictionary, context: localization)
    }

    private var buildLabel: String {
        guard let commit = Bundle.main.object(forInfoDictionaryKey: "NXLibraryBuildCommit") as? String else { return buildDate }
        return "\(buildDate) · \(seleneShort(commit))"
    }

    private var buildDate: String {
        let url = Bundle.main.executableURL ?? Bundle.main.bundleURL
        if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            return date.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.context.formatLocale))
        }
        return "local"
    }

    private func openProjectDocs() {
        NSWorkspace.shared.open(AppIdentity.documentationPage)
    }

    private func openFundingPage() {
        openURL(AppIdentity.koFiPage)
    }
}
