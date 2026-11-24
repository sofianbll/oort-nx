import SwiftUI
import AppKit
import NXLibraryCore

/// Left column of Settings: app mark, name and version, then the sections under their group headings.
struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    var isFocused: Bool = false
    let context: AppLocale
    @Environment(\.seleneCanvas) private var canvas

    private var version: String {
        L10n.format("Version %@", [AppUpdate.versionLabel(Bundle.main.infoDictionary, context: context)], context: context)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, canvas.u(26))
            // The groups can be taller than the window: the selected section is always scrolled into view,
            // at once like a macOS sidebar. An animated scroll started in the same frame as the new section's
            // content and stuttered.
            ScrollViewReader { proxy in
                ScrollView {
                    groups
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(selection) }
                .onChange(of: selection) { _, section in proxy.scrollTo(section) }
            }
        }
    }

    /// App-wide groups, then one per platform (`SettingsSidebarGroup`); a heading is a label, not a stop.
    private var groups: some View {
        VStack(alignment: .leading, spacing: canvas.u(6)) {
            ForEach(SettingsSidebarGroup.all) { group in
                if let heading = group.title(in: context) {
                    Text(heading)
                        .seleneFont(.compactCaption, .semibold)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.leading, canvas.u(SeleneTokens.Space.panel))
                        .padding(.top, canvas.u(SeleneTokens.Space.control))
                        .padding(.bottom, canvas.u(SeleneTokens.Space.seam))
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(group.sections) { section in groupRow(section).id(section) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: canvas.u(16)) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: canvas.u(48), height: canvas.u(48))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: canvas.u(2)) {
                Text(AppIdentity.displayName)
                    .seleneFont(.title, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                Text(version)
                    .seleneFont(.caption)
                    .foregroundColor(SeleneTheme.ink.opacity(0.55))
            }
        }
    }

    private func groupRow(_ section: SettingsSection) -> some View {
        let selected = selection == section
        let lit = selected && isFocused
        return Button {
            selection = section
        } label: {
            HStack(spacing: canvas.u(16)) {
                // Selene's section icons take the row's ink, like the title.
                Group {
                    if section == .multiplayer {
                        Image(systemName: "person.2.fill")
                            .seleneFont(20)
                            .frame(width: canvas.u(24))
                            .accessibilityHidden(true)
                    } else {
                        MaterialIconView(section.icon, size: 24)
                    }
                }
                .foregroundColor(lit ? SeleneTheme.onFocus : SeleneTheme.ink)
                Text(section.title(in: context))
                    .seleneFont(.rowTitle, .medium)
                    .foregroundColor(lit ? SeleneTheme.onFocus : SeleneTheme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, canvas.u(SeleneTokens.Space.panel))
            .padding(.vertical, canvas.u(SeleneTokens.Space.line))
            .background(
                RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge), style: .continuous)
                    .fill(lit ? SeleneTheme.focus : (selected ? SeleneTheme.glass : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title(in: context))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
