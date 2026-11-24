import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

struct GameBananaFindPanel: View {
    @ObservedObject var model: GameBananaFindModel
    @ObservedObject var band: GameBananaBandModel
    let gameName: String

    @Environment(\.seleneCanvas) private var canvas
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            SeleneTheme.scrim65
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
            VStack(alignment: .leading, spacing: canvas.u(14)) {
                Text(L10n.text("GAMEBANANA"))
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                Text(L10n.format("Which game is %@?", [String(describing: gameName)]))
                    .seleneFont(.screen)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(2)
                GameBananaSearchField(prompt: L10n.text("Game name"), query: $model.query, focused: $fieldFocused,
                                      onSubmit: {
                                          model.editing = true
                                          model.confirm(using: band)
                                      }, onClose: close)
                .onChange(of: model.editing) { _, editing in if fieldFocused != editing { fieldFocused = editing } }
                .onChange(of: fieldFocused) { _, focused in if model.editing != focused { model.editing = focused } }

                if model.searching {
                    Text(L10n.text("Searching GameBanana…")).seleneFont(.text).foregroundColor(SeleneTheme.ink60)
                } else if model.searched && model.results.isEmpty {
                    Text(L10n.text("No games found. Try another name.")).seleneFont(.text).foregroundColor(SeleneTheme.ink60)
                }
                VStack(alignment: .leading, spacing: canvas.u(8)) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, game in
                        row(index: index, title: game.name, icon: game.iconURL)
                    }
                    row(index: model.results.count, title: "None of these", icon: nil)
                        .opacity(model.searched && !model.searching ? 1 : 0.5)
                }
                Text(L10n.text("Mod data provided by GameBanana"))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink60)
            }
            .padding(canvas.u(36))
            .frame(width: canvas.u(820), alignment: .leading)
            .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.field), style: .continuous).fill(SeleneTheme.glassSolid))
        }
    }

    private func row(index: Int, title: String, icon: URL?) -> some View {
        let focused = model.focus == index && !model.editing
        return HStack(spacing: canvas.u(14)) {
            if let icon {
                GameBananaImageView(url: icon, maxPixelSize: 128)
                    .frame(width: canvas.u(40), height: canvas.u(40))
                    .clipShape(RoundedRectangle(cornerRadius: canvas.u(8), style: .continuous))
            } else {
                MaterialIconView(.close, size: 22).foregroundColor(SeleneTheme.ink60)
                    .frame(width: canvas.u(40), height: canvas.u(40))
            }
            Text(title)
                .seleneFont(.text, .medium)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.line))
        .padding(.vertical, canvas.u(SeleneTokens.Space.compact))
        .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content), style: .continuous)
            .fill(focused ? SeleneTheme.glass : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge), style: .continuous)
            .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(2.5))
            .padding(canvas.u(-3))
            .opacity(focused ? 1 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            SoundEffectService.shared.play(.click)
            model.activate(index, using: band)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }

    private func close() {
        SoundEffectService.shared.play(.focus)
        model.close()
    }
}

struct GameBananaModSearchPanel: View {
    @ObservedObject var band: GameBananaBandModel
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            SeleneTheme.scrim65.ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: canvas.u(14)) {
                Text(L10n.text("GAMEBANANA", context: localization))
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                Text(L10n.text("Search mods", context: localization))
                    .seleneFont(.screen)
                    .foregroundColor(SeleneTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                GameBananaSearchField(prompt: L10n.text("Mod name or GameBanana link", context: localization),
                                      query: $band.modQuery, focused: $fieldFocused,
                                      onSubmit: submit, onClose: close)
                if let status {
                    Text(status).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                }
                HStack(spacing: canvas.u(18)) {
                    SelenePillButton(title: "Cancel", focused: false, action: close)
                    SelenePillButton(title: "Search", focused: false, enabled: band.canSubmitModSearch, action: submit)
                        .disabled(!band.canSubmitModSearch)
                }
            }
            .padding(canvas.u(36))
            .frame(width: canvas.u(820), alignment: .leading)
            .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.field), style: .continuous).fill(SeleneTheme.glassSolid))
        }
        .onAppear { fieldFocused = true }
    }

    private var status: String? {
        switch band.searchPanel {
        case .loading: return L10n.text("Searching GameBanana…", context: localization)
        case .empty: return L10n.text("No compatible mods found. Try another name or link.", context: localization)
        case .invalidLink: return L10n.text("Paste a GameBanana mod link.", context: localization)
        case .offline: return L10n.text("No connection. Mods you installed still work.", context: localization)
        case .failed: return L10n.text("GameBanana didn't answer. Try again in a moment.", context: localization)
        case .editing, nil: return nil
        }
    }

    private func submit() {
        guard band.canSubmitModSearch else { return }
        SoundEffectService.shared.play(.click)
        band.submitModSearch()
    }

    private func close() {
        SoundEffectService.shared.play(.focus)
        band.closeModSearch()
    }
}

private struct GameBananaSearchField: View {
    let prompt: String
    @Binding var query: String
    @FocusState.Binding var focused: Bool
    let onSubmit: () -> Void
    let onClose: () -> Void
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        HStack(spacing: canvas.u(10)) {
            MaterialIconView(.search, size: 22).foregroundColor(SeleneTheme.ink60)
                .accessibilityHidden(true)
            TextField("", text: $query, prompt: Text(prompt).foregroundColor(SeleneTheme.ink60))
                .textFieldStyle(.plain)
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink)
                .focused($focused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onClose)
                .accessibilityLabel(prompt)
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.medium))
        .padding(.vertical, canvas.u(10))
        .background(Capsule().fill(SeleneTheme.glassSolid))
        .overlay(Capsule().strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(2.5)).opacity(focused ? 1 : 0))
    }
}
