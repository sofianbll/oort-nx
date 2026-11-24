import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting
import Combine
import os

enum SettingsFocusArea { case sidebar, rows }

extension EnvironmentValues {
    @Entry var passiveSettingsArrival = false
}

/// Selene's settings screen (`SettingsScreen.cs`): groups on the left, the group's rows on the right.
struct SettingsView: View {
    private let initialSection: SettingsSection
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var setup: SetupModel
    @ObservedObject var settings: AppSettingsStore
    @StateObject private var editor: SettingsEditor
    @ObservedObject var router: AppRouter
    @ObservedObject var artwork: ArtworkStore

    /// Opens the Search field when the player asks for it (`enterSection`).
    @State private var searchFieldRequest = 0
    @State private var section: SettingsSection
    @State private var openedFromIntegrations: Bool
    @State private var showingControls = false
    @State private var showingPlayers = false
    @State private var cloudAssistant: CloudSetupAssistant.Entry?
    @State private var editingCloudReference = false
    private var showingCloudAssistant: Bool { cloudAssistant != nil || editingCloudReference }
    @State private var cloudAdvanced = false
    @State private var multiplayerAdvanced = false
    @State private var localePicker: LocalePickerMode?
    private enum PINAction { case set, change, remove }
    @State private var pinProfileID: UUID?
    @State private var pinAction: PINAction = .set
    @State private var firstPIN: String?
    @State private var editingProfileName = false
    private var profileDialogOpen: Bool { editingProfileName || pinProfileID != nil }
    @State private var focusArea: SettingsFocusArea = .sidebar
    @State private var rowFocus = FocusIndex()
    /// The button in focus inside the focused row: 0 its own, 1 a second one (Back to tested beside Update).
    @State private var rowButton = 0
    @State private var rowActions: [SettingsRowAction] = []
    @State private var keyMonitor: Any?
    @State private var decisionFocus = 2
    @State private var decisionError: String?
    @State private var decisionScroll = 0
    @State private var originalToolchainOverride: Bool?
    @State private var originalDeadzone: Double?
    @State private var originalDockIcon: String?
    @Environment(\.seleneReduceMotion) private var environmentReduceMotion
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneBackdropStyle) private var appBackdropStyle

    /// The app's backdrop with the Settings wallpaper (Settings → Look), which may be the app's own.
    private var settingsBackdropStyle: SeleneBackdropStyle {
        var style = appBackdropStyle
        let values = settings.presentation
        let id = WallpaperCatalog.settingsWallpaper(settingsID: values.settingsWallpaperID, appID: values.wallpaperID)
        style.wallpaperURL = theme.wallpaper(for: id)?.url
        return style
    }
    /// A palette change redraws the whole screen; selection and focus live here and survive it.
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var igdb = IGDBSettings.shared
    @ObservedObject private var nextendo: NextendoSettings
    private let hasProfileAccount: Bool
    private let profiles: LocalProfileStore?
    @State private var profileRevision = false
    @State private var nextendoRemovalFocus: SeleneConfirmButton = .cancel
    @State private var nextendoEngine: EngineSelection?
    private struct EngineSelection: Equatable {
        let path: String
        let commit: String?
    }
    private var engine: EngineSelection? {
        guard setup.isNxnativeValid, !setup.nxnativePath.isEmpty else { return nil }
        return EngineSelection(path: setup.nxnativePath, commit: setup.currentEngineCommit)
    }
    private var supportsNextendo: Bool { nextendoEngine != nil && engine == nextendoEngine && viewModel.usesSharedNextendo }
    @Environment(\.nxAppLocale) private var localization

    init(initialSection: SettingsSection,
                viewModel: AppViewModel,
                settings: AppSettingsStore,
                router: AppRouter,
                artwork: ArtworkStore,
                profileAccount: NextendoSettings? = nil) {
        self.initialSection = initialSection
        self.viewModel = viewModel
        self.setup = viewModel.setup
        self.settings = settings
        _editor = StateObject(wrappedValue: SettingsEditor(settings))
        self.router = router
        self.artwork = artwork
        let account = profileAccount ?? viewModel.profileNextendo
        self.hasProfileAccount = account != nil
        _nextendo = ObservedObject(wrappedValue: account ?? .shared)
        profiles = viewModel.localProfiles
        _section = State(initialValue: initialSection)
        _openedFromIntegrations = State(initialValue: router.previousRoute == .integrations)
    }

    private var layout: some View {
        let _ = profileRevision
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: canvas.u(24)) {
                SettingsSidebar(selection: $section, isFocused: focusArea == .sidebar, context: localization)
                    .frame(width: canvas.u(400))
                content
            }
            .padding(.horizontal, canvas.u(SeleneTokens.Space.stageGutter))
            .padding(.top, canvas.u(SeleneTokens.Space.stageHeader))
            .frame(maxHeight: .infinity, alignment: .top)
            SeleneHintsBar(left: [HintItem(.b, L10n.text("Back")) { handleBack() }], right: commandHints)
                // Save remains visible even while previewing a change that hides the hints.
                .environment(\.seleneShowButtonHints, hasPendingChanges || settings.presentation.showButtonHints)
                .seleneOverlaidHints(showingControls || showingPlayers || localePicker != nil || showingCloudAssistant
                    || viewModel.isEditingSteamGridDBKey || igdb.isEditing
                    || profileDialogOpen || nextendo.isEditingClient || nextendo.friendToRemove != nil)
        }
        .id(theme.palette.id)
        .background(SeleneBackdrop().environment(\.seleneBackdropStyle, settingsBackdropStyle))
    }

    private var observedLayout: some View {
        layout
        .onAppear {
            if settings.draft == nil {
                let legacy = setup.legacyToolchainOverride
                originalToolchainOverride = legacy
                originalDeadzone = GameControllerService.shared.legacyDeadzone
                originalDockIcon = AppViewModel.legacyDockIcon
                settings.beginDraft(fields: SettingsDraftFields.fields(profiles: profiles,
                    languages: viewModel.availableLanguages, legacyToolchainOverride: legacy,
                    steam: viewModel.catalogSnapshot.source(.steam)))
            }
            installKeyMonitor()
        }
        .onReceive(profiles?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            profileRevision.toggle()
        }
        .onChange(of: profiles?.active?.id) {
            cancelPIN()
            editingProfileName = false
        }
        .onAppear {
            if AppData.profile.isDevelopment {
                Logger(subsystem: "local.nxlibrary.development", category: "backdrop-transition")
                    .notice("Settings appeared, window settling: \(viewModel.isWindowSettling, privacy: .public)")
            }
        }
        .onDisappear(perform: removeKeyMonitor)
        .onDisappear { igdb.isEditing = false }
        .onDisappear { cloudAssistant = nil; editingCloudReference = false }
        .onReceive(viewModel.cloudLibrary.$recovery.dropFirst(openedFromIntegrations ? 1 : 0)) { action in
            guard let action, router.route == .settings(.cloudLibrary) else { return }
            switch action {
            case .reconnect: cloudAssistant = .credentials
            case .archiveFolder: cloudAssistant = .library
            case .sourceFolder: cloudAssistant = .sources
            }
            Task { @MainActor in viewModel.cloudLibrary.recovery = nil }
        }
        .onDisappear {
            if !openedFromIntegrations { nextendo.cancelBrowser() }
            nextendo.isEditingClient = false
            nextendo.friendToRemove = nil
        }
        .task(id: engine) {
            guard let selected = engine else { nextendoEngine = nil; return }
            let supported = await Task.detached {
                NextendoLaunch.engineSupportsSignIn(at: URL(fileURLWithPath: selected.path))
            }.value
            guard !Task.isCancelled, engine == selected else { return }
            nextendoEngine = supported ? selected : nil
        }
        .onChange(of: supportsNextendo) { _, supported in
            if !supported, section == .multiplayer { nextendo.isEditingClient = false }
        }
        .onChange(of: section) { _, section in
            if section != .cloudLibrary { cloudAdvanced = false }
            if section != .multiplayer { multiplayerAdvanced = false }
            rowActions = []
            rowFocus = FocusIndex()
            rowButton = 0
        }
        .onChange(of: initialSection) { _, value in
            section = value
            focusArea = .sidebar
            showingPlayers = false
        }
        .onChange(of: router.settingsRowID) { _, _ in focusRequestedSetting() }
        .onChange(of: router.settingsDecision) {
            decisionFocus = 2
            decisionError = nil
            decisionScroll = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxSettingsGamepadAction)) { note in
            guard router.settingsDecision == nil, !showingPlayers, router.route == .settings(initialSection),
                  let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxSettingsDecisionInput)) { note in
            guard router.settingsDecision != nil, router.route == .settings(initialSection),
                  let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
    }

    var body: some View {
        observedLayout
        .overlay {
            if viewModel.isEditingSteamGridDBKey {
                SteamGridDBKeyDialog(viewModel: viewModel, gamepad: .nxSettingsGamepadAction) { _ in
                    viewModel.isEditingSteamGridDBKey = false
                }
            }
        }
        .overlay {
            if igdb.isEditing {
                IGDBCredentialsDialog(model: igdb) { igdb.isEditing = false }
            }
        }
        .disabled(nextendo.isEditingClient)
        .accessibilityHidden(nextendo.isEditingClient)
        .overlay {
            if nextendo.isEditingClient {
                NextendoClientDialog(settings: editor) { nextendo.isEditingClient = false }
            }
        }
        .disabled(showingCloudAssistant)
        .accessibilityHidden(showingCloudAssistant)
        .overlay {
            if let cloudAssistant {
                CloudSetupAssistant(viewModel: viewModel, model: viewModel.cloudLibrary, entry: cloudAssistant) {
                    self.cloudAssistant = nil
                }
            }
            if editingCloudReference {
                CloudReferenceDialog(viewModel: viewModel) { editingCloudReference = false }
            }
        }
        .disabled(nextendo.friendToRemove != nil || profileDialogOpen)
        .accessibilityHidden(nextendo.friendToRemove != nil || profileDialogOpen)
        .overlay { profilePINOverlay }
        .overlay { profileNameOverlay }
        .overlay { nextendoRemovalOverlay }
        .opacity(showingControls ? 0.001 : 1)
        .allowsHitTesting(!showingControls)
        .overlay {
            if showingControls {
                ControlsView(canHandleInput: {
                    !router.isMenuPresented && !viewModel.showSetupCheck
                        && !viewModel.shellDialogOwnsInput && !viewModel.isWelcomeOpen && !NativeMenuCommands.shared.isTracking
                        && viewModel.settingsNotice == nil && viewModel.gameWithInstallFailure == nil
                }) { showingControls = false }
            }
        }
        .overlay {
            if let mode = localePicker {
                LocalePicker(mode: mode, settings: editor, canHandleInput: {
                    !router.isMenuPresented && !NativeMenuCommands.shared.isTracking
                        && !viewModel.showSetupCheck && !viewModel.shellDialogOwnsInput && !viewModel.isWelcomeOpen
                        && viewModel.settingsNotice == nil && NSApp.modalWindow == nil && router.settingsDecision == nil
                }) { localePicker = nil }
            }
        }
        .seleneOverlayOwnership(!showingPlayers)
        .overlay {
            if showingPlayers {
                viewModel.playersScreen(input: .nxSettingsGamepadAction, canHandleInput: {
                    router.route == .settings(initialSection) && !router.isMenuPresented && !viewModel.showSetupCheck
                        && !viewModel.shellDialogOwnsInput && !viewModel.isWelcomeOpen
                        && !NativeMenuCommands.shared.isTracking && viewModel.settingsNotice == nil
                        && viewModel.gameWithInstallFailure == nil && viewModel.alertMessage == nil
                        && router.settingsDecision == nil
                }) { showingPlayers = false }
            }
        }
        .seleneOverlayOwnership(router.settingsDecision == nil)
        .overlay { decisionOverlay }
        .environment(\.seleneMinimumFont, 12)
    }

    private var hasPendingChanges: Bool { settings.draft?.hasChanges == true }

    @ViewBuilder var decisionOverlay: some View {
        if let mode = router.settingsDecision, let draft = settings.draft {
            SeleneOverlay(style: .profileRemoval, onOutside: { decide(2) }) {
                SeleneChoiceDialog(title: "Unsaved settings",
                    message: decisionError ?? L10n.text("Review what will change before you save."),
                    choices: ["Save", mode == .leave ? "Leave without saving" : "Discard changes", "Continue editing settings"],
                    focus: $decisionFocus, cancelIndex: 2, notes: SettingsDraftFields.summary(draft.changes),
                    notesScrollRequest: decisionScroll, onCancel: { decide(2) }, onChoose: decide)
                    .environment(\.seleneShowButtonHints, true)
            }
        }
    }

    private func decide(_ index: Int) {
        guard router.settingsDecision != nil else { return }
        switch index {
        case 0:
            do {
                let changes = Set(settings.draft?.changes.map(\.id) ?? [])
                if changes.contains("steamSource"), let choice = settings.editingSettings.launcherChoices.steamSource,
                   try viewModel.catalogRepository.load().source(.steam)?.generation != choice.replaces {
                    throw AppSettingsDraft.Failure.changedElsewhere
                }
                if changes.contains("controllerDeadzone"), settings.settings.launcherChoices.controllerDeadzone == nil,
                   originalDeadzone != GameControllerService.shared.legacyDeadzone { throw AppSettingsDraft.Failure.changedElsewhere }
                if changes.contains("iconAppearance"), settings.settings.launcherChoices.dockIconAppearance == nil,
                   originalDockIcon != AppViewModel.legacyDockIcon { throw AppSettingsDraft.Failure.changedElsewhere }
                if settings.draft?.changes.contains(where: { $0.id == "toolchainOverride" }) == true {
                    guard ToolchainGateCopy.canChangeOverride(certified: setup.compatibilityReport?.ok,
                        overrideOn: setup.allowUntestedToolchain,
                        locked: viewModel.isBuilding || viewModel.isUpdatingApp || setup.isSwitchingEngine,
                        newest: setup.usesNewestEngine) else {
                        decisionError = L10n.text("The toolchain setting is unavailable now. Your changes are still here.")
                        return
                    }
                    if settings.settings.toolchainOverride == nil, originalToolchainOverride != setup.legacyToolchainOverride {
                        throw AppSettingsDraft.Failure.changedElsewhere
                    }
                }
                try settings.commitDraft()
                decisionFocus = 2
                router.finishSettingsDecision(proceed: true)
            } catch {
                decisionError = L10n.text((error as? AppSettingsDraft.Failure)?.errorDescription
                    ?? "Settings could not be saved. Your changes are still here.")
                SoundEffectService.shared.play(.error)
            }
        case 1:
            settings.discardDraft()
            decisionFocus = 2
            router.finishSettingsDecision(proceed: true)
        default:
            decisionFocus = 2
            router.finishSettingsDecision(proceed: false)
        }
    }

    @ViewBuilder private var profilePINOverlay: some View {
        if let profile = profiles?.active, pinProfileID == profile.id {
            let title = switch pinAction {
            case .set: firstPIN == nil ? "Set profile code" : "Confirm profile code"
            case .change: "Enter current profile code"
            case .remove: "Remove profile code"
            }
            SeleneOverlay(style: .profileRemoval, onOutside: cancelPIN) {
                ProfilePINDialog(title: title, allowsTouchID: pinAction == .remove, input: .nxSettingsPINInput, onCancel: cancelPIN,
                                 onTouchID: { _ = savePIN(nil) }, onPIN: enterPIN)
                    .id(title)
            }
        }
    }

    @ViewBuilder private var profileNameOverlay: some View {
        if editingProfileName, let profiles, let profile = profiles.active {
            ProfileEditorView(profile: profile, games: [], isNew: false, nameOnly: true,
                              onCancel: { editingProfileName = false }) { draft in
                guard var active = profiles.active, active.id == draft.id else { return false }
                active.rename(to: draft.name)
                guard profiles.update(active) else { return false }
                editingProfileName = false
                return true
            }
            .accessibilityAddTraits(.isModal)
        }
    }

    @ViewBuilder private var nextendoRemovalOverlay: some View {
        if hasProfileAccount, let friend = nextendo.friendToRemove {
            ZStack {
                SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture { nextendo.friendToRemove = nil }
                SeleneConfirmDialog(title: L10n.text("Remove this friend?", context: localization), message: friend.name,
                                    confirmTitle: L10n.text("Remove friend", context: localization),
                                    cancelTitle: L10n.text("Cancel", context: localization), focus: $nextendoRemovalFocus,
                                    onCancel: { nextendo.friendToRemove = nil }, onConfirm: confirmNextendoRemoval)
            }
            .onAppear { nextendoRemovalFocus = .cancel }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: canvas.u(8)) {
                    Text(section.place)
                        .seleneFont(.compactCaption, .semibold)
                        .foregroundColor(SeleneTheme.ink.opacity(0.55))
                        .padding(.bottom, canvas.u(SeleneTokens.Space.tight))
                    SettingsSectionContent(
                        section: section,
                        viewModel: viewModel,
                        settings: editor,
                        artwork: artwork,
                        supportsNextendo: supportsNextendo,
                        activeProfile: profiles?.active,
                        profileNextendo: hasProfileAccount ? nextendo : nil,
                        onEditProfileName: { editingProfileName = true },
                        onProfilePIN: openPIN,
                        onRemovePIN: { openPIN(removing: true) },
                        onViewControls: { showingControls = true },
                        onOpenPlayers: { showingPlayers = true },
                        onChooseLanguage: { localePicker = .language },
                        onChooseRegion: { localePicker = .region },
                        onOpenConsole: { router.openConsole() },
                        onOpenGroup: openGroup,
                        onSearchSubmit: enterRows,
                        searchFieldRequest: searchFieldRequest,
                        cloudAdvanced: $cloudAdvanced,
                        multiplayerAdvanced: $multiplayerAdvanced,
                        onEditCloud: { cloudAssistant = viewModel.cloudLibrary.preference.remote == nil ? .account : .credentials },
                        onEditCloudLibraryFolder: { cloudAssistant = .library },
                        onEditCloudSources: { cloudAssistant = .sources },
                        onEditCloudReference: { editingCloudReference = true },
                        onActions: updateActions
                    )
                    .environment(\.passiveSettingsArrival, openedFromIntegrations && section == initialSection)
                    .environment(\.settingsRowChanges, pendingRows)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.seleneFocusedRowID, focusArea == .rows ? focusedRow?.rowID : nil)
                .environment(\.seleneFocusedButton, rowButton)
                .padding(.bottom, canvas.u(SeleneTokens.Space.settingsInfoClearance))
            }
            .scrollIndicators(.hidden)
            .onChange(of: focusArea == .rows ? focusedRow?.rowID : nil) { _, rowID in
                rowButton = 0
                guard let rowID else { return }
                let id = "selene-row-\(rowID)"
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var reduceMotion: Bool {
        settings.presentation.reduceMotion || environmentReduceMotion
    }

    private var pendingRows: [String: AppSettingsDraft.Change] {
        var rows: [String: AppSettingsDraft.Change] = [:]
        for change in settings.draft?.changes ?? [] {
            rows[SettingsDraftFields.row(change.id, in: section)] = change
            if change.id == "steamSource", section == .sources { rows["Steam folder"] = change }
        }
        return rows
    }

    private var commandHints: [HintItem] {
        var hints = [HintItem(.lb, "Previous") { moveSection(by: -1) },
                     HintItem(.rb, "Next") { moveSection(by: 1) }]
        if canResetSection {
            hints.append(HintItem(.x, L10n.text("Reset group")) { resetSection() })
        }
        if hasPendingChanges {
            hints.append(HintItem(.y, "Save", keyboard: .text("Y")) { router.requestSettingsSave() })
        }
        if focusArea == .sidebar {
            hints.append(HintItem(.a, L10n.text("Open")) { enterSection() })
        } else if focusedRow?.cycle != nil {
            hints.append(HintItem(.a, L10n.text("Change")))
        } else {
            hints.append(HintItem(.a, L10n.text("Select")))
        }
        return hints
    }

    private var focusedRow: SettingsRowAction? {
        rowActions.indices.contains(rowFocus.index) ? rowActions[rowFocus.index] : nil
    }

    private func updateActions(_ actions: [SettingsRowAction]) {
        // One focus slot per visible row; reset the button when an action appears or disappears.
        let focusedID = focusedRow?.id
        let focusedButtonCount = focusedRow?.buttonCount
        rowActions = SettingsRowAction.primaryActions(actions)
        if let focusedID, let index = rowActions.firstIndex(where: { $0.id == focusedID }) {
            rowFocus.index = index
        }
        rowFocus.move(by: 0, count: rowActions.count)
        if focusedID != focusedRow?.id || focusedButtonCount != focusedRow?.buttonCount { rowButton = 0 }
        if rowActions.isEmpty, focusArea == .rows { focusArea = .sidebar }
        focusRequestedSetting()
    }

    private func focusRequestedSetting() {
        guard router.route == .settings(section), let id = router.settingsRowID,
              let setting = SettingsCatalog.all.first(where: { $0.id == id && $0.group == section }),
              let index = rowActions.firstIndex(where: {
                  $0.id == id || $0.rowID == setting.title || (id == "cloudLibraryService" && $0.id == "cloudRecovery")
              }) else { return }
        rowFocus.index = index
        rowButton = 0
        focusArea = .rows
        router.takeSettingsRowFocus()
    }

    private func openGroup(_ row: SettingDescriptor) {
        section = row.group
        cloudAdvanced = SettingsCatalog.opensCloudAdvanced(row.id)
        multiplayerAdvanced = ["multiplayerLocalMode", "multiplayerAdapter", "nextendoClientID"].contains(row.id)
        focusArea = .sidebar
        SoundEffectService.shared.play(.click)
    }

    /// A or Right on the sidebar. Search opens its field; every other section enters its rows.
    private func enterSection() {
        guard focusArea == .sidebar else { return }
        if section == .search {
            searchFieldRequest += 1
            SoundEffectService.shared.play(.focus)
        } else {
            enterRows()
        }
    }

    private func enterRows() {
        guard focusArea == .sidebar, !rowActions.isEmpty else { return }
        focusArea = .rows
        rowButton = 0
        SoundEffectService.shared.play(.focus)
    }

    private func leaveRows() {
        focusArea = .sidebar
        SoundEffectService.shared.play(.focus)
    }

    private var canResetSection: Bool {
        if section == .profileSecurity { return profiles?.active?.isLocked == true && profiles?.guest == nil }
        if section == .profileNextendo { return hasProfileAccount }
        return SettingsReset.canReset(section)
    }

    /// `SettingsReset` puts the section's `AppSettings` back in one assignment; the preferences
    /// kept outside it are reset here.
    private func resetSection() {
        guard canResetSection else { return }
        switch section {
        case .look:
            let unset = settings.settings.launcherChoices.dockIconAppearance == nil
            editor.settings.launcherChoices.dockIconAppearance = unset && SettingsLookSection.iconMode(AppViewModel.legacyDockIcon) == .auto
                ? nil : AppIconAppearanceMode.auto.rawValue
        case .profileIdentity:
            if let profiles, var profile = profiles.active {
                profile.name = profile.defaultName
                profile.avatar = 0
                profile.portrait = nil
                saveProfileSetting(profile, in: profiles, notifying: viewModel)
            }
        case .profileSecurity:
            openPIN(removing: true)
        case .profileNextendo:
            if let profiles, var profile = profiles.active {
                profile.appearsOnline = nil
                profile.showsCurrentGame = nil
                saveProfileSetting(profile, in: profiles, notifying: viewModel)
            }
        case .profileCards:
            if let profiles, var profile = profiles.active {
                profile.pageCards = nil
                saveProfileSetting(profile, in: profiles, notifying: viewModel)
            }
        case .controllers:
            let unset = settings.settings.launcherChoices.controllerDeadzone == nil
            editor.settings.launcherChoices.controllerDeadzone = unset && GameControllerService.shared.legacyDeadzone == 0.35
                ? nil : 0.35
        default:
            break
        }
        editor.settings = SettingsReset.reset(section, in: editor.settings)
        SoundEffectService.shared.play(.focus)
    }

    private func moveFocus(by delta: Int) {
        switch focusArea {
        case .sidebar:
            moveSection(by: delta)
        case .rows:
            rowFocus.move(by: delta, count: rowActions.count)
        }
    }

    private func moveSection(by delta: Int) {
        guard !(NSApp.keyWindow?.firstResponder is NSText) else { return }
        focusArea = .sidebar
        section = SettingsSection.allCases.stepped(from: section, delta) ?? section
        SoundEffectService.shared.play(.focus)
    }

    private func moveSideways(_ delta: Int) {
        switch focusArea {
        case .sidebar:
            if delta > 0 { enterSection() }
        case .rows:
            if section == .cloudLibrary,
               focusedRow?.id == (delta > 0 ? "cloudLibraryFolder" : "cloudSourcesRoot"),
               let sibling = rowActions.firstIndex(where: { $0.id == (delta > 0 ? "cloudSourcesRoot" : "cloudLibraryFolder") }) {
                rowFocus.index = sibling
                rowButton = 0
                SoundEffectService.shared.play(.focus)
                return
            }
            if let cycle = focusedRow?.cycle, focusedRow?.isEnabled == true {
                cycle(delta)
                SoundEffectService.shared.play(.focus)
                return
            }
            let buttons = focusedRow?.isEnabled == true ? (focusedRow?.buttonCount ?? 1) : 1
            switch SettingsRowAction.sideways(from: rowButton, by: delta, buttons: buttons) {
            case .button(let index):
                rowButton = index
                SoundEffectService.shared.play(.focus)
            case .leaveRows:
                leaveRows()
            case .stay:
                break
            }
        }
    }

    /// Arrows, Return/Space, Esc and X, like the other screens' monitors. Typing in a field keeps its keys.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard router.route == .settings(initialSection),
                  !viewModel.shellDialogOwnsInput,
                  !viewModel.isWelcomeOpen,
                  !NativeMenuCommands.shared.isTracking,
                  !router.isMenuPresented,
                  !viewModel.showSetupCheck,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  viewModel.gameWithInstallFailure == nil,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil else { return event }
            if router.settingsDecision != nil {
                guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
                switch event.keyCode {
                case 123: handleGamepad(.navigateLeft)
                case 124: handleGamepad(.navigateRight)
                case 125: handleGamepad(.navigateDown)
                case 126: handleGamepad(.navigateUp)
                case 36, 49, 76: if !event.isARepeat { handleGamepad(.confirm) }
                case 53: handleGamepad(.cancel)
                default: return event
                }
                return nil
            }
            guard !showingControls, !showingPlayers, localePicker == nil, !viewModel.isEditingSteamGridDBKey,
                  !igdb.isEditing, !nextendo.isEditingClient, !showingCloudAssistant else { return event }
            if pinProfileID != nil {
                return ProfilePINDialog.handleKey(event, input: .nxSettingsPINInput)
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            let typing = window.firstResponder is NSText
            if editingProfileName {
                if typing && event.keyCode != 53 { return event }
                let key = event.charactersIgnoringModifiers?.lowercased()
                switch (event.keyCode, key) {
                case (51, _), (_, "x"): handleGamepad(.secondaryAction); return nil
                case (_, "y"): handleGamepad(.contextAction); return nil
                case (_, "+"), (_, "="): handleGamepad(.menu); return nil
                default: break
                }
            }
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125:
                if typing {
                    // Down from the Search field goes to its results.
                    window.makeFirstResponder(nil)
                    enterRows()
                    return nil
                }
                action = .navigateDown
            case 123:
                if typing { return event }
                action = .navigateLeft
            case 124:
                if typing { return event }
                action = .navigateRight
            case 12, 14:
                if typing { return event }
                action = event.keyCode == 12 ? .tabPrevious : .tabNext
            case 36, 49, 76:
                if typing { return event }
                guard !event.isARepeat else { return nil }
                action = .confirm
            case 53:
                action = .cancel
            case 7:                                     // X
                if typing { return event }
                action = .secondaryAction
            case 16:                                    // Y
                if typing || !hasPendingChanges { return event }
                action = .contextAction
            default:
                return event
            }
            handleGamepad(action)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleGamepad(_ action: GamepadAction) {
        if router.settingsDecision != nil {
            switch action {
            case .navigateLeft: decisionFocus = max(0, decisionFocus - 1)
            case .navigateRight: decisionFocus = min(2, decisionFocus + 1)
            case .navigateUp: decisionScroll = max(0, decisionScroll - 1)
            case .navigateDown:
                decisionScroll = min(max(0, (settings.draft?.changes.count ?? 1) - 1), decisionScroll + 1)
            case .confirm: decide(decisionFocus)
            case .cancel: decide(2)
            default: break
            }
            return
        }
        if pinProfileID != nil {
            NotificationCenter.default.post(name: .nxSettingsPINInput, object: action)
            return
        }
        if editingProfileName {
            NotificationCenter.default.post(name: .nxProfileInput, object: action)
            return
        }
        // The key dialog takes the controller while it is open.
        if viewModel.isEditingSteamGridDBKey || igdb.isEditing || nextendo.isEditingClient || showingCloudAssistant { return }
        if nextendo.friendToRemove != nil {
            switch action {
            case .navigateLeft: nextendoRemovalFocus = .left
            case .navigateRight: nextendoRemovalFocus = .right
            case .confirm where nextendoRemovalFocus == .confirm: confirmNextendoRemoval()
            case .confirm, .cancel: nextendo.friendToRemove = nil
            default: break
            }
            return
        }
        if localePicker != nil {
            NotificationCenter.default.post(name: .nxLocalePickerGamepadAction, object: action)
            return
        }
        if showingControls {
            NotificationCenter.default.post(name: .nxControlsGamepadAction, object: action)
            return
        }
        switch action {
        case .navigateUp: moveFocus(by: -1)
        case .navigateDown: moveFocus(by: 1)
        case .navigateLeft: moveSideways(-1)
        case .navigateRight: moveSideways(1)
        case .tabPrevious: moveSection(by: -1)
        case .tabNext: moveSection(by: 1)
        case .confirm:
            if focusArea == .sidebar {
                enterSection()
            } else if let row = focusedRow, row.isEnabled {
                if row.id != "soundPreview" { SoundEffectService.shared.play(.click) }
                row.press(button: rowButton)
            }
        case .cancel:
            handleBack()
        case .secondaryAction:
            resetSection()
        case .contextAction:
            router.requestSettingsSave()
        case .menu:
            router.isMenuPresented = true
        default:
            break
        }
    }

    private func confirmNextendoRemoval() {
        guard let friend = nextendo.friendToRemove else { return }
        nextendo.friendToRemove = nil
        nextendo.updateFriend(.remove(pid: friend.id), clientID: settings.settings.nextendoClientID ?? NextendoLaunch.buildClientID)
    }

    private func openPIN() { openPIN(removing: false) }

    private func openPIN(removing: Bool) {
        guard let profiles, profiles.guest == nil, let profile = profiles.active else { return }
        pinAction = removing ? .remove : profile.isLocked ? .change : .set
        pinProfileID = profile.id
    }

    private func cancelPIN() { pinProfileID = nil; firstPIN = nil }

    private func enterPIN(_ pin: String) -> String? {
        guard let profile = profiles?.active, profile.id == pinProfileID else { cancelPIN(); return nil }
        if pinAction != .set {
            guard profile.matchesPIN(pin) else { return "Incorrect code." }
            if pinAction == .remove { return savePIN(nil) }
            pinAction = .set
            return nil
        }
        guard let firstPIN else { self.firstPIN = pin; return nil }
        guard firstPIN == pin else { return "The codes do not match." }
        return savePIN(pin)
    }

    private func savePIN(_ pin: String?) -> String? {
        guard let profiles, var profile = profiles.active, profile.id == pinProfileID else { cancelPIN(); return nil }
        guard profile.setPIN(pin), profiles.update(profile) else { return "Your changes could not be saved. Try again." }
        cancelPIN()
        return nil
    }

    /// B or Esc: steps back one level. Typing in Search, it closes the field and stays on Search.
    private func handleBack() {
        if let window = NSApp.keyWindow, window.firstResponder is NSText {
            window.makeFirstResponder(nil)
            SoundEffectService.shared.play(.focus)
        } else if router.previousRoute == .profile || router.previousRoute == .integrations {
            router.back()
        } else if focusArea == .rows {
            leaveRows()
        } else {
            router.back()
        }
    }
}
