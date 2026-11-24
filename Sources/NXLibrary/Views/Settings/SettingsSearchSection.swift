import SwiftUI
import NXLibraryCore
import ArcanePorting

/// Search: a Selene pill field over `SettingsCatalog.search`; picking a result opens its group.
struct SettingsSearchSection: View {
    @ObservedObject var cloudLibrary: CloudLibraryModel
    let supportsNextendo: Bool
    let hasProfileAccount: Bool
    let onOpenGroup: (SettingDescriptor) -> Void
    let onSubmit: () -> Void
    /// Bumped when the player opens the field (A or Right from the sidebar). Selecting Search never
    /// takes the keys by itself: Up/Down keep moving through the sidebar.
    let fieldRequest: Int
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var results: [SettingDescriptor] {
        SettingsCatalog.search(query, supportsNextendo: supportsNextendo, hasProfileAccount: hasProfileAccount,
                               cloudConfigured: cloudLibrary.preference.remote != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            TextField(L10n.text("Search settings"), text: $query)
                .textFieldStyle(.plain)
                .seleneFont(.panelBody)
                .foregroundColor(SeleneTheme.ink)
                .focused($fieldFocused)
                .onSubmit {
                    fieldFocused = false
                    onSubmit()
                }
                .padding(.leading, canvas.u(26))
                .padding(.top, canvas.u(11))
                .padding(.trailing, canvas.u(26))
                .padding(.bottom, canvas.u(13))
                .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.field), style: .continuous)
                    .fill(SeleneTheme.glass))
                .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.field), style: .continuous)
                    .strokeBorder(fieldFocused ? SeleneTheme.focus : SeleneTheme.ink15,
                                  lineWidth: max(1, canvas.u(2))))
                .padding(.bottom, canvas.u(SeleneTokens.Space.compact))

            if !query.isEmpty && results.isEmpty {
                Text(L10n.text("No settings match."))
                    .seleneFont(.panelBody)
                    .foregroundColor(SeleneTheme.ink60)
            }
            SettingsDescriptorList(rows: results, onOpenGroup: onOpenGroup)
        }
        .onAppear(perform: publishActions)
        .onChange(of: fieldRequest) { fieldFocused = true }
        .onChange(of: results.map(\.id)) { publishActions() }
    }

    private func publishActions() {
        onActions(SettingsDescriptorList.actions(results, onOpenGroup: onOpenGroup))
    }
}

/// Changed: every row whose value differs from the default.
struct SettingsChangedSection: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var viewModel: AppViewModel
    /// The engine folder (`SetupModel`), so the Changed list follows it.
    @ObservedObject var setup: SetupModel
    @ObservedObject var cloudLibrary: CloudLibraryModel
    @ObservedObject var profiles: LocalProfileStore
    @ObservedObject private var controller = GameControllerService.shared
    let supportsNextendo: Bool
    let hasProfileAccount: Bool
    let onOpenGroup: (SettingDescriptor) -> Void
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var rows: [SettingDescriptor] {
        var external = SettingsCatalog.profileChanges(profiles.active)
        if viewModel.profileNextendo?.status == .signedIn { external.insert("nextendo") }
        if viewModel.iconAppearanceMode != .auto { external.insert("iconAppearance") }
        if abs(controller.deadzone - 0.35) > 0.001 { external.insert("controllerDeadzone") }
        if viewModel.porting.gameFilesFolder != nil { external.insert("gameFolder") }
        if cloudLibrary.preference.enabled { external.insert("cloudLibraryEnabled") }
        if cloudLibrary.preference.remote != nil { external.insert("cloudLibraryService") }
        if cloudLibrary.preference.root != CloudLibraryPreference.defaultRoot { external.insert("cloudLibraryFolder") }
        if cloudLibrary.preference.sourcesRootOverride != nil { external.insert("cloudSourcesRoot") }
        if cloudLibrary.preference.referenceFolder != nil { external.insert("cloudReferenceFolder") }
        if cloudLibrary.chosenExecutable != nil { external.insert("cloudLibraryTool") }
        let root = URL(fileURLWithPath: viewModel.defaultInstallPath)
        if viewModel.libraryFolder?.standardizedFileURL != root.appendingPathComponent("Applications").standardizedFileURL {
            external.insert("libraryFolder")
        }
        if URL(fileURLWithPath: setup.nxnativePath).standardizedFileURL != root.appendingPathComponent("nxnative").standardizedFileURL {
            external.insert("engineFolder")
        }
        return SettingsCatalog.changed(in: settings.settings, externalChanges: external, supportsNextendo: supportsNextendo,
                                       hasProfileAccount: hasProfileAccount,
                                       cloudConfigured: cloudLibrary.preference.remote != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            if rows.isEmpty {
                Text(L10n.text("Nothing changed yet."))
                    .seleneFont(.panelBody)
                    .foregroundColor(SeleneTheme.ink60)
            }
            SettingsDescriptorList(rows: rows, onOpenGroup: onOpenGroup)
        }
        .onAppear(perform: publishActions)
        .onChange(of: rows.map(\.id)) { publishActions() }
    }

    private func publishActions() {
        onActions(SettingsDescriptorList.actions(rows, onOpenGroup: onOpenGroup))
    }
}

/// Catalog rows with their group as a chip; A or a click opens the group.
struct SettingsDescriptorList: View {
    let rows: [SettingDescriptor]
    let onOpenGroup: (SettingDescriptor) -> Void
    @Environment(\.seleneCanvas) private var canvas

    static func title(_ row: SettingDescriptor) -> String { "\(row.group.place) · \(L10n.text(row.title))" }

    static func actions(_ rows: [SettingDescriptor],
                        onOpenGroup: @escaping (SettingDescriptor) -> Void) -> [SettingsRowAction] {
        rows.map { row in
            SettingsRowAction(id: row.id, title: title(row), rowID: row.id) { onOpenGroup(row) }
        }
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            ForEach(rows) { row in
                SeleneRow(Self.title(row), id: row.id, subtitle: row.about) {
                    MaterialIconView(.chevron, size: 24)
                        .foregroundColor(SeleneTheme.ink60)
                }
                .contentShape(Rectangle())
                .onTapGesture { onOpenGroup(row) }
            }
        }
    }
}
