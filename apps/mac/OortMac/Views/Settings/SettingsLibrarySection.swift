import SwiftUI
import AppKit
import OortLibrary
import NxnativeAdapter

struct SettingsLibrarySection: View {
    @Environment(\.seleneFocusedRowID) private var focusedRowID
    @Environment(\.seleneFocusedButton) private var focusedButton
    @ObservedObject var viewModel: AppViewModel
    /// Game files shows the folder chosen through the porting model, so the row follows its changes.
    @ObservedObject var porting: PortingModel
    @ObservedObject var settings: SettingsEditor
    let onActions: ([SettingsRowAction]) -> Void
    private var appsPath: String? { settings.settings.launcherChoices.gameAppsPath ?? viewModel.libraryFolder?.path }
    private var sourcesPath: String? {
        let path = settings.settings.launcherChoices.gameSourcesPath ?? porting.gameFilesFolder?.path
        return path == "" ? nil : path
    }
    private func stageAppsPath(_ path: String) {
        settings.settings.launcherChoices.gameAppsPath = path == viewModel.libraryFolder?.path
            ? settings.store.settings.launcherChoices.gameAppsPath : path
    }
    private func stageSourcesPath(_ path: String?) {
        settings.settings.launcherChoices.gameSourcesPath = path == porting.gameFilesFolder?.path
            ? settings.store.settings.launcherChoices.gameSourcesPath : (path ?? "")
    }
    private func chooseAppsPath() {
        viewModel.selectLibraryFolder(startingAt: appsPath.map { URL(fileURLWithPath: $0) }, stage: { stageAppsPath($0.path) })
    }
    private func chooseSourcesPath() {
        porting.selectGameFolder(startingAt: sourcesPath.map { URL(fileURLWithPath: $0) }, stage: {
            guard $0.path != "/" else { return }
            stageSourcesPath($0.path)
        })
    }

    var body: some View {
        OortSettingsGroup {
            SeleneRow(GameFoldersCopy.appsTitle,
                      subtitle: GameFoldersCopy.appsContents,
                      info: "Choose where to keep your game apps. Put any existing nxnative games (.app) here. Changing folders does not move apps; rebuilds update them where they are.",
                      verbatimSubtitle: true, formatBadges: GameFoldersCopy.appBadges) {
                HStack(spacing: SeleneTokens.Space.gap) {
                    Text(appsPath ?? L10n.text("Not selected"))
                        .seleneFont(.text, .medium)
                        .foregroundColor(SeleneTheme.ink75)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .trailing)
                    Button(L10n.text("Change"), action: chooseAppsPath)
                        .buttonStyle(OortPressStyle())
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                        .seleneKeyRing(focusedRowID == GameFoldersCopy.appsTitle && focusedButton == 0)
                    Button(L10n.text("Reset"), action: resetAppsPath)
                    .buttonStyle(OortPressStyle())
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                    .seleneKeyRing(focusedRowID == GameFoldersCopy.appsTitle && focusedButton == 1)
                }
            }

            SeleneRow(GameFoldersCopy.sourcesTitle,
                      subtitle: GameFoldersCopy.sourcesContents,
                      info: "Existing game apps play without their sources. Reset group keeps this folder. Clear removes the selection, keeping your files.",
                      verbatimSubtitle: true, formatBadges: GameFoldersCopy.sourceBadges) {
                HStack(spacing: SeleneTokens.Space.gap) {
                    Text(sourcesPath ?? L10n.text("Not selected · Optional"))
                        .seleneFont(.text, .medium)
                        .foregroundColor(SeleneTheme.ink75)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .trailing)
                    Button(L10n.text("Choose"), action: chooseSourcesPath)
                        .buttonStyle(OortPressStyle())
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                        .seleneKeyRing(focusedRowID == GameFoldersCopy.sourcesTitle && focusedButton == 0 && sourcesPath != nil)
                    if sourcesPath != nil {
                        Button(L10n.text("Clear"), action: clearSourcesPath)
                            .buttonStyle(OortPressStyle())
                            .seleneFont(.text, .semibold)
                            .foregroundColor(SeleneTheme.danger)
                            .seleneKeyRing(focusedRowID == GameFoldersCopy.sourcesTitle && focusedButton == 1)
                    }
                }
            }

            SeleneToggleRow("Sort incoming files",
                            subtitle: "Check the Inbox for Switch files to sort.",
                            isOn: $settings.settings.gameInboxEnabled)

            SeleneButtonRow("Library refresh",
                            subtitle: viewModel.isScanningLibrary
                                ? "Scanning game apps…" : "Find existing nxnative builds and refresh the library.",
                            info: "Checks Game apps and its subfolders. Existing library entries are kept; no apps are moved. Source files are optional for Play.",
                            buttonTitle: "Refresh") {
                viewModel.refreshIncludingExistingBuilds()
            }

            if !viewModel.libraryScanWarnings.isEmpty {
                VStack(alignment: .leading, spacing: SeleneTokens.Space.tight) {
                    ForEach(viewModel.libraryScanWarnings, id: \.self) { warning in
                        Text(warning)
                            .seleneFont(.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundColor(SeleneTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SeleneTokens.Space.large)
                .padding(.vertical, SeleneTokens.Space.compact)
            }

            SeleneToggleRow("Refresh library at launch",
                            subtitle: "Rescan the app library for new or removed builds.",
                            isOn: $settings.settings.refreshLibraryAtLaunch)

            SeleneToggleRow("Notify when a porting ends",
                            subtitle: "A notification when a porting finishes while Arcane is in the background.",
                            isOn: $settings.settings.notifyPortingEnds)

            SeleneButtonRow("Box covers",
                            subtitle: "GameTDB covers",
                            buttonTitle: "Open GameTDB") {
                NSWorkspace.shared.open(GameTDB.siteURL)
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.isScanningLibrary) { publishActions() }
        .onChange(of: sourcesPath) { publishActions() }
    }

    private func resetAppsPath() { stageAppsPath(viewModel.defaultGameAppsPath) }
    private func clearSourcesPath() { stageSourcesPath(nil) }

    private func publishActions() {
        onActions([
            .init(id: "appsChange", title: GameFoldersCopy.appsTitle, secondary: ("Reset", resetAppsPath)) {
                chooseAppsPath()
            },
            .init(id: "romChoose", title: GameFoldersCopy.sourcesTitle,
                  secondary: sourcesPath == nil ? nil : ("Clear", clearSourcesPath)) {
                chooseSourcesPath()
            },
            .init(id: "gameInboxEnabled", title: "Sort incoming files") {
                settings.settings.gameInboxEnabled.toggle()
            },
            .init(id: "refresh", title: "Library refresh") {
                viewModel.refreshIncludingExistingBuilds()
            },
            .init(id: "refreshAtLaunch", title: "Refresh library at launch") {
                settings.settings.refreshLibraryAtLaunch.toggle()
            },
            .init(id: "notify", title: "Notify when a porting ends") {
                settings.settings.notifyPortingEnds.toggle()
            },
            .init(id: "covers", title: "Box covers") {
                NSWorkspace.shared.open(GameTDB.siteURL)
            }
        ])
    }
}
