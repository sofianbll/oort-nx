import SwiftUI
import NXLibraryCore

struct SettingsSectionContent: View {
    @Environment(\.seleneFocusedRowID) private var focusedRowID
    @Environment(\.seleneFocusedButton) private var focusedButton
    let section: SettingsSection
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: SettingsEditor
    @ObservedObject var artwork: ArtworkStore
    let supportsNextendo: Bool
    let activeProfile: LocalProfile?
    let profileNextendo: NextendoSettings?
    let onEditProfileName: () -> Void
    let onProfilePIN: () -> Void
    let onRemovePIN: () -> Void
    let onViewControls: () -> Void
    let onOpenPlayers: () -> Void
    let onChooseLanguage: () -> Void
    let onChooseRegion: () -> Void
    let onOpenConsole: () -> Void
    let onOpenIntegrations: () -> Void
    let onOpenGroup: (SettingDescriptor) -> Void
    let searchQuery: String
    @Binding var cloudAdvanced: Bool
    @Binding var multiplayerAdvanced: Bool
    let onEditCloud: () -> Void
    let onEditCloudLibraryFolder: () -> Void
    let onEditCloudSources: () -> Void
    let onEditCloudReference: () -> Void
    let onActions: ([SettingsRowAction]) -> Void

    var body: some View {
        switch section {
        case .search:
            SettingsSearchSection(cloudLibrary: viewModel.cloudLibrary, supportsNextendo: supportsNextendo,
                                  hasProfileAccount: profileNextendo != nil, onOpenGroup: onOpenGroup,
                                  query: searchQuery, onActions: onActions)
        case .changed:
            if let profiles = viewModel.localProfiles {
                SettingsChangedSection(settings: settings.store, viewModel: viewModel, setup: viewModel.setup,
                                       cloudLibrary: viewModel.cloudLibrary, profiles: profiles,
                                       supportsNextendo: supportsNextendo, hasProfileAccount: profileNextendo != nil,
                                       query: searchQuery, onOpenGroup: onOpenGroup, onActions: onActions)
            }
        case .startUp:
            if let profiles = viewModel.localProfiles {
                SettingsStartUpSection(settings: settings, onActions: onActions, onChooseLanguage: onChooseLanguage,
                                       onChooseRegion: onChooseRegion, onOpenOnboarding: viewModel.reopenOnboarding, profiles: profiles)
            }
        case .profileIdentity:
            if let profiles = viewModel.localProfiles {
                SettingsProfileIdentitySection(profiles: profiles, viewModel: viewModel,
                                               onEditName: onEditProfileName, onActions: onActions)
            }
        case .profileSecurity:
            if let profile = activeProfile, viewModel.localProfiles?.guest == nil {
                let focused = focusedRowID == "Profile lock"
                SeleneRow("Profile lock", subtitle: "Use four digits.") {
                    SelenePillButton(title: profile.isLocked ? "Change code" : "Set code",
                                     focused: focused && focusedButton == 0, action: onProfilePIN)
                    if profile.isLocked {
                        SelenePillButton(title: "Remove code", focused: focused && focusedButton == 1, action: onRemovePIN)
                    }
                }
                .onChange(of: profile.isLocked, initial: true) { _, locked in
                    onActions([.init(id: "profileLock", title: "Profile lock",
                                     secondary: locked ? ("Remove code", onRemovePIN) : nil, activate: onProfilePIN)])
                }
            }
        case .profileNextendo:
            if let profiles = viewModel.localProfiles, let profile = activeProfile, let profileNextendo {
                SettingsAPISection(viewModel: viewModel, settings: settings, showsMultiplayer: true,
                                   supportsNextendo: true, accountOnly: true, profile: profile,
                                   onProfilePreference: { key, value in
                    guard var active = profiles.active, active.id == profile.id else { return }
                    active[keyPath: key] = value
                    saveProfileSetting(active, in: profiles, notifying: viewModel)
                }, advanced: .constant(false), onActions: onActions, nextendo: profileNextendo)
                .id(profile.id)
            } else {
                Text(L10n.text("No account linked")).seleneFont(.text).foregroundStyle(SeleneTheme.ink60)
            }
        case .profileCards:
            if let profiles = viewModel.localProfiles {
                SettingsProfileCardsSection(profiles: profiles, onActions: onActions)
            }
        case .profileLook:
            SettingsLookSection(viewModel: viewModel, settings: settings, profileLook: true, onActions: onActions)
        case .navigation:
            SettingsNavigationSection(settings: settings, onActions: onActions)
        case .spotlight:
            SettingsSpotlightSection(settings: settings, onActions: onActions)
        case .soundMusic:
            SettingsSoundSection(settings: settings, onActions: onActions) { question, apply in
                viewModel.confirmSetting(question.title, message: question.message, action: question.action, apply: apply)
            }
        case .look:
            SettingsLookSection(viewModel: viewModel, settings: settings, onActions: onActions)
        case .apiServices:
            SettingsAPISection(viewModel: viewModel, settings: settings, showsMultiplayer: false,
                               supportsNextendo: false, advanced: .constant(false), onActions: onActions)
        case .multiplayer:
            SettingsAPISection(viewModel: viewModel, settings: settings, showsMultiplayer: true,
                               supportsNextendo: supportsNextendo, advanced: $multiplayerAdvanced, onActions: onActions)
        case .libraryGames:
            SettingsLibraryGamesSection(viewModel: viewModel, settings: settings, onActions: onActions)
        case .games:
            SettingsGamesSection(viewModel: viewModel, settings: settings, onActions: onActions)
        case .cloudSaves:
            SettingsCloudSavesSection(settings: settings, onActions: onActions)
        case .cloudLibrary:
            SettingsCloudLibrarySection(viewModel: viewModel, model: viewModel.cloudLibrary, settings: settings, advanced: $cloudAdvanced,
                                        onEdit: onEditCloud, onEditLibrary: onEditCloudLibraryFolder,
                                        onEditSources: onEditCloudSources, onEditReference: onEditCloudReference, onActions: onActions)
        case .controllers:
            SettingsControllersSection(settings: settings, onActions: onActions,
                                       onViewControls: onViewControls, onOpenPlayers: onOpenPlayers)
        case .library:
            SettingsLibrarySection(viewModel: viewModel, porting: viewModel.porting, settings: settings, onActions: onActions)
        case .sources:
            SettingsSourcesSection(viewModel: viewModel, settings: settings, onOpenIntegrations: onOpenIntegrations, onActions: onActions)
        case .storage:
            SettingsStorageSection(viewModel: viewModel, artwork: artwork, onActions: onActions)
        case .portingStorage:
            SettingsPortingStorageSection(viewModel: viewModel, onActions: onActions)
        case .engine:
            SettingsEngineSection(viewModel: viewModel, setup: viewModel.setup, settings: settings, onActions: onActions)
        case .keys:
            SettingsKeysSection(viewModel: viewModel, setup: viewModel.setup, onActions: onActions)
        case .console:
            SettingsConsoleSection(onActions: onActions, onOpenConsole: onOpenConsole)
        case .about:
            SettingsAboutSection(viewModel: viewModel, setup: viewModel.setup, onActions: onActions)
        }
    }
}

func seleneBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file).locale(L10n.context.formatLocale))
}

func seleneShort(_ commit: String?) -> String {
    guard let commit, !commit.isEmpty else { return "—" }
    return String(commit.prefix(7))
}
