import SwiftUI
import OortLibrary

struct SettingsProfileIdentitySection: View {
    var profiles: LocalProfileStore
    let viewModel: AppViewModel
    let onEditName: () -> Void
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneFocusedRowID) private var focusedRow

    var body: some View {
        if let profile = profiles.active {
            let time = viewModel.playSessionStore?.profileActivity(at: .now).values.reduce(0) { $0 + $1.duration } ?? 0
            let created = profile.createdAt.map {
                L10n.format("Created %@", [$0.formatted(.dateTime.day().month(.abbreviated).year()
                    .locale(L10n.context.formatLocale))])
            }
            let details = [created, L10n.format("%@ played", [LibraryPresentation.duration(time)])]
                .compactMap { $0 }.joined(separator: " · ")
            OortSettingsGroup {
                SeleneOptionRow(icon: nil, title: profile.name, about: details, focused: false,
                                leading: AnyView(ProfilePortrait(profile: profile, size: 60, ring: true)),
                                titleAccessory: AnyView(SeleneStatusDot(text: L10n.text("Active profile"), color: SeleneTheme.statusOK))) {
                    EmptyView()
                }
                SettingsSubheading("Name")
                SeleneRow("Name", subtitle: "Shown on your profile and to your friends.") {
                    SeleneValueChip(text: profile.name)
                    button("Edit", action: onEditName)
                }
                SettingsSubheading("Avatar")
                let avatar = preset(profile)
                SeleneOptionRow(icon: nil, title: L10n.text("Avatar"), about: L10n.text("One of Arcane’s 28 illustrations."),
                                focused: focusedRow == "Avatar", leading: AnyView(ProfilePortrait(profile: avatar, size: 40))) {
                    SeleneCycleValue(title: L10n.text("Avatar"), value: L10n.format("Avatar %lld", [avatar.avatar + 1]),
                                     cycle: cycleAvatar)
                }
                .id("selene-row-Avatar")
                SeleneRow("Personal image", subtitle: "PNG, JPEG or animated GIF, up to 4 MB.") {
                    button("Choose an image…") { chooseImage() }
                    if profile.portrait != nil { button("Remove image", action: removeImage) }
                }
            }
            .onAppear(perform: publishActions)
            .onChange(of: profile.portrait != nil) { publishActions() }
        }
    }

    private func chooseImage() {
        guard let id = profiles.active?.id else { return }
        OortFilePickerPresentation.open(.files(["png", "jpg", "jpeg", "gif"]), title: L10n.text("Personal image"),
                                        message: L10n.text("PNG, JPEG or animated GIF, up to 4 MB.")) { urls in
            guard let url = urls.first, profiles.active?.id == id else { return }
            guard let bytes = ProfileAvatar.render(url, crop: .init()) else {
                viewModel.showSettingsNotice(title: L10n.text("Settings not saved"),
                                             message: L10n.text("Choose a valid image."))
                return
            }
            update { $0.portrait = bytes }
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(L10n.text(title), action: action)
            .buttonStyle(OortPressStyle()).seleneFont(.text, .semibold).foregroundStyle(SeleneTheme.glyph)
    }

    private func preset(_ profile: LocalProfile) -> LocalProfile {
        var avatar = profile
        avatar.portrait = nil
        return avatar
    }

    private func cycleAvatar(_ step: Int) {
        update {
            $0.avatar = Array(0..<LocalProfile.avatarCount).stepped(from: $0.avatar, step) ?? 0
        }
    }

    private func removeImage() { update { $0.portrait = nil } }

    @discardableResult
    private func update(_ change: (inout LocalProfile) -> Void) -> Bool {
        guard var profile = profiles.active else { return false }
        change(&profile)
        return saveProfileSetting(profile, in: profiles, notifying: viewModel)
    }

    private func publishActions() {
        onActions([
            .init(id: "profileName", title: "Name", rowID: "Name", activate: onEditName),
            .value("profileAvatar", "Avatar", cycle: cycleAvatar),
            .init(id: "profilePortrait", title: "Personal image", rowID: "Personal image",
                  secondary: profiles.active?.portrait == nil ? nil : ("Remove image", removeImage)) {
                chooseImage()
            },
        ])
    }
}

@discardableResult
func saveProfileSetting(_ profile: LocalProfile, in profiles: LocalProfileStore, notifying viewModel: AppViewModel) -> Bool {
    guard profiles.active?.id == profile.id else { return false }
    if profiles.update(profile) { return true }
    viewModel.showSettingsNotice(title: L10n.text("Settings not saved"),
                                 message: L10n.text("Your changes could not be saved. Try again."))
    return false
}
