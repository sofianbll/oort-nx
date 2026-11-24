import SwiftUI
import AppKit
import NXLibraryCore

struct SettingsAboutSection: View {
    @ObservedObject var viewModel: AppViewModel
    /// The Setup (`SetupModel`): an available release names the Xcode it needs.
    @ObservedObject var setup: SetupModel
    @EnvironmentObject private var updater: AppUpdater
    @Environment(\.seleneFocusedRowID) private var focusedRowTitle
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    let onActions: ([SettingsRowAction]) -> Void

    @State private var didCopyDiagnostics = false
    private static let supportTitle = "Support Arcane"

    private let credits: [(name: String, role: String, url: String)] = [
        ("seedds", L10n.text("nxnative engine, NVN/Metal host and ARM64 rewriter"), "https://github.com/seedds/nxnative"),
        ("d2r-mobile", L10n.text("Foundational native execution architecture"), "https://github.com/jhaizhou-ops/d2r-mobile"),
        ("Ryujinx Team", L10n.text("Maxwell shader translator and SPIR-V generator"), "https://github.com/Ryujinx/Ryujinx"),
        ("Atmosphère NX", L10n.text("Mesosphère kernel synchronization semantics"), "https://github.com/Atmosphere-NX/Atmosphere"),
        ("LibHac", L10n.text("NSP reading and PFS/HFS layered filesystem"), "https://github.com/Thealexbarney/LibHac"),
        ("Khronos Group", L10n.text("SPIRV-Cross Metal Shading Language compiler"), "https://github.com/KhronosGroup/SPIRV-Cross"),
        ("GameTDB", L10n.text("Switch box covers"), "https://www.gametdb.com"),
        ("Title DB", L10n.text("Game names, icons and banners"), "https://github.com/blawar/titledb"),
        ("LaunchBox Games Database", L10n.text("Community metadata and game artwork"), "https://gamesdb.launchbox-app.com"),
        ("TheGamesDB", L10n.text("Community metadata and game artwork"), "https://thegamesdb.net"),
        ("SteamGridDB", L10n.text("Community covers, backgrounds, logos and icons, with your API key"), "https://www.steamgriddb.com"),
        ("IGDB", L10n.text("Critic scores with your own credentials"), "https://www.igdb.com"),
        ("Wikipedia", L10n.text("Game introductions in your language (CC BY-SA)"), "https://www.wikipedia.org"),
        ("NX2Apple", L10n.text("Key check, failure explanations and diagnostics, adapted (MIT)"), "https://github.com/LNPANDY/NX2Apple")
    ]

    var body: some View {
        VStack(spacing: 12) {
            SelenePanel(AppIdentity.displayName) {
                Text(L10n.text("A free, open-source game library and launcher for Mac. Play installed games and port compatible Switch titles with nxnative."))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.format("Version %@ · Build %@ · Engine %@", [version, buildLabel, seleneShort(viewModel.pinnedEngineCommit)]))
                    .seleneFont(.badge, .regular, design: .monospaced)
                    .foregroundColor(SeleneTheme.ink60)
                Button(action: openProjectDocs) {
                    HStack(spacing: canvas.u(SeleneTokens.Space.hairline)) {
                        Text(L10n.format("Based on %@ %@, by %@", [AppIdentity.name, "0.2.1", "Bium23"], context: localization))
                        Image(systemName: "arrow.up.right").accessibilityHidden(true)
                    }
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                }
                .buttonStyle(.plain)
                .padding(canvas.u(SeleneTokens.Space.tight))
                .seleneRowFocus(focusedRowTitle == "Open project docs")
                .id("selene-row-Open project docs")
                Text(L10n.text("Play time is tracked only for launches from Arcane. Not affiliated with Nintendo."))
                    .seleneFont(.badge)
                    .foregroundColor(SeleneTheme.ink60)
                updateRow
                Button {
                    copyDiagnostics()
                } label: {
                    HStack(spacing: 4) {
                        Text(didCopyDiagnostics ? L10n.text("Copied") : L10n.text("Copy diagnostics"))
                        Image(systemName: didCopyDiagnostics ? "checkmark" : "doc.on.doc")
                    }
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                }
                .buttonStyle(.plain)
                .padding(6)
                .seleneRowFocus(focusedRowTitle == "Copy diagnostics")
                .id("selene-row-Copy diagnostics")
                .accessibilityHint(L10n.text("A report for an issue: versions, setup and the last porting. No keys."))
            }

            supportButton

            SelenePanel(L10n.text("Credits")) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(credits, id: \.name) { credit in
                        Button {
                            if let url = URL(string: credit.url) { NSWorkspace.shared.open(url) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(credit.name)
                                        .seleneFont(.text, .semibold)
                                        .foregroundColor(SeleneTheme.ink)
                                    Image(systemName: "arrow.up.right")
                                        .seleneFont(.badge)
                                        .foregroundColor(SeleneTheme.ink60)
                                }
                                Text(credit.role)
                                    .seleneFont(.badge)
                                    .foregroundColor(SeleneTheme.ink60)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(SeleneTheme.glass.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .seleneRowFocus(focusedRowTitle == credit.name, radius: 7)
                        .id("selene-row-\(credit.name)")
                        .accessibilityLabel("\(credit.name), \(credit.role)")
                    }
                }
            }

            SelenePanel(L10n.text("Visual direction")) {
                Text(L10n.text("Inspired by Selene (MIT) by Matthew Silva."))
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                Button {
                    if let url = URL(string: "https://github.com/mattxslv/Selene") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("https://github.com/mattxslv/Selene")
                        Image(systemName: "arrow.up.right")
                    }
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                }
                .buttonStyle(.plain)
                .padding(6)
                .seleneRowFocus(focusedRowTitle == "Selene")
                .id("selene-row-Selene")
                Text(L10n.text("Selene is a Playnite theme for Windows. No Selene name, logo, wallpaper, avatar or sound is used as Arcane branding; this is a visual adaptation in SwiftUI."))
                    .seleneFont(.badge)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SelenePanel(L10n.text("Nintendo Store data")) {
                Text(L10n.text("Descriptions, genres and artwork are fetched from the public Nintendo Store catalog for personal use, cached locally for seven days, and never committed or redistributed."))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.text("The app ships no keys, ROMs, game art or Nintendo UI assets."))
                    .seleneFont(.badge)
                    .foregroundColor(SeleneTheme.ink60)
            }

            SelenePanel(L10n.text("Licenses")) {
                Text(L10n.text("Arcane is personal software released under the MIT license. nxnative, Ryujinx, SPIR-V Cross, LibHac and the other dependencies retain their own licenses through the engine."))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.text("This app is not affiliated with Nintendo."))
                    .seleneFont(.badge, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                Text(L10n.text("This app is not affiliated with Valve."))
                    .seleneFont(.badge, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                // Valve's attribution, in Valve's own wording for each language.
                Text(L10n.text("©2026 Valve Corporation. Steam and the Steam logo are trademarks and/or registered trademarks of Valve Corporation in the U.S. and/or other countries."))
                    .seleneFont(.badge)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.text("Platform names and logos identify their respective platforms. They belong to their owners and do not imply affiliation or endorsement."))
                    .seleneFont(.badge)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "Nintendo · Valve Corporation · Epic Games · GOG · CodeWeavers · Buy Me a Coffee · Google")
                    .seleneFont(.badge)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: updater.state) { publishActions() }
        .onChange(of: viewModel.isBuilding) { publishActions() }
        .onChange(of: viewModel.isCleaningStorage) { publishActions() }
        .onChange(of: viewModel.hasActiveSaveOperations) { publishActions() }
        .onChange(of: viewModel.isUpdatingApp) { publishActions() }
        .onChange(of: viewModel.runningGameCount) { publishActions() }
    }

    private var supportButton: some View {
        Button(action: openSupportPage) {
            SelenePanel {
                HStack(spacing: canvas.u(14)) {
                    VStack(alignment: .leading, spacing: canvas.u(4)) {
                        PlatformLabel(.support,
                                      title: L10n.format("Support %@ on Buy Me a Coffee", ["Bium23"], context: localization), preset: .summary)
                            .foregroundStyle(SeleneTheme.ink)
                        Text(L10n.text("Optional contributions support development and maintenance.", context: localization))
                            .seleneFont(.text)
                            .foregroundColor(SeleneTheme.ink75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: canvas.u(8))
                    Image(systemName: "arrow.up.right")
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .seleneRowFocus(focusedRowTitle == Self.supportTitle, radius: SeleneTheme.cardRadius)
        .id("selene-row-\(Self.supportTitle)")
    }

    private func copyDiagnostics() {
        viewModel.copyDiagnostics()
        didCopyDiagnostics = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { didCopyDiagnostics = false }
    }

    private func publishActions() {
        var actions: [SettingsRowAction] = [.init(id: "docs", title: "Open project docs", activate: openProjectDocs)]
        actions += updateActions.map { action in
            SettingsRowAction(id: "update-\(action.title)", title: action.title,
                              isEnabled: action.enabled, activate: action.perform)
        }
        actions.append(.init(id: "diagnostics", title: "Copy diagnostics", activate: copyDiagnostics))
        actions.append(.init(id: "support", title: Self.supportTitle, activate: openSupportPage))
        actions += credits.map { credit in
            SettingsRowAction(id: "credit-\(credit.name)", title: credit.name) {
                if let url = URL(string: credit.url) { NSWorkspace.shared.open(url) }
            }
        }
        actions.append(.init(id: "selene", title: "Selene") {
            NSWorkspace.shared.open(URL(string: "https://github.com/mattxslv/Selene")!)
        })
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
            HStack(spacing: 14) {
                Text(updateText)
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                ForEach(updateActions, id: \.title) { action in
                    Button(action.title, action: action.perform)
                        .buttonStyle(.plain)
                        .seleneFont(.text, .semibold)
                        .foregroundColor(action.enabled ? SeleneTheme.glyph : SeleneTheme.ink60)
                        .disabled(!action.enabled)
                        .padding(6)
                        .seleneRowFocus(focusedRowTitle == action.title)
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

    private func openSupportPage() {
        if let url = URL(string: "https://buymeacoffee.com/bium") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openProjectDocs() {
        NSWorkspace.shared.open(AppIdentity.documentationPage)
    }
}
