import SwiftUI
import NXLibraryCore
import ArcanePorting

/// Porting → Keys: the private copy of prod.keys that new portings need.
struct SettingsKeysSection: View {
    @ObservedObject var viewModel: AppViewModel
    /// The imported keys (`SetupModel`), observed on their own.
    @ObservedObject var setup: SetupModel
    let onActions: ([SettingsRowAction]) -> Void

    @Environment(\.seleneFocusedRowID) private var focusedRowTitle
    @Environment(\.seleneFocusedButton) private var focusedButton
    private var configurationLocked: Bool { viewModel.isBuilding || viewModel.isUpdatingApp }

    var body: some View {
        OortSettingsGroup {
            SelenePanel(GameFoldersCopy.keysTitle,
                        info: L10n.text("Nintendo Switch cryptographic keys required to decrypt game packages (NSP/XCI). Arcane stores a private copy with mode 0600 permissions; key values are never displayed or logged."), infoRow: "prod.keys") {
                OortReadout(text: setup.readiness?.keysContents ?? GameFoldersCopy.keysContents)
                if let readiness = setup.readiness {
                    proposal(readiness)
                } else {
                    current
                }

                Text(setup.readiness == nil
                     ? L10n.text("The original file is untouched. The stored copy is mode 0600 and key values are never shown or logged.")
                     : L10n.text("The original file is untouched. Oort keeps a copy only you can read, and never shows or logs key values."))
                    .seleneFont(.badge)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .seleneRowFocus(focusedRowTitle == "prod.keys", radius: SeleneTheme.cardRadius)
        }
        .onAppear(perform: publishActions)
        .onChange(of: configurationLocked) { publishActions() }
    }

    /// Proposal (feat/proposition-accueil-ryujinx): the keys' reach in firmware, title.keys checked when present,
    /// and a failed choice explained here, where it was made. Same words on the Mac and the PC.
    @ViewBuilder
    private func proposal(_ readiness: SwitchReadiness) -> some View {
        OortFormatBadges(labels: GameFoldersCopy.keyBadges + ["title.keys"])
        ReadinessStatus(line: readiness.keysLine)
        ReadinessStatus(line: readiness.titleKeysLine)
        HStack(spacing: SeleneTokens.Space.line) {
            let imported = if case .imported = readiness.keys { true } else { false }
            ReadinessButton(title: imported ? "Replace Key..." : "Import Key...",
                            focused: focusedRowTitle == "prod.keys" && focusedButton == 0) {}
            ReadinessButton(title: "Detect Ryujinx...", focused: focusedRowTitle == "prod.keys" && focusedButton == 1) {}
            ReadinessButton(title: "Add title.keys…", focused: focusedRowTitle == "prod.keys" && focusedButton == 2) {}
            Spacer()
        }
    }

    @ViewBuilder
    private var current: some View {
                OortFormatBadges(labels: GameFoldersCopy.keyBadges)
                HStack(spacing: SeleneTokens.Space.compact) {
                    Image(systemName: setup.isProdKeysValid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .seleneFont(.text, .bold)
                        .foregroundColor(setup.isProdKeysValid ? SeleneTheme.success : SeleneTheme.danger)
                    Text(setup.isProdKeysValid ? L10n.text("Keys imported") : L10n.text("No prod.keys imported"))
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                    Spacer()
                    if !setup.isProdKeysValid {
                        Text(L10n.text("Choose your file once"))
                            .seleneFont(.text, .regular, design: .monospaced)
                            .foregroundColor(SeleneTheme.ink60)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if let count = setup.keyGenerationCount {
                    Text(L10n.format("header_key present · %@ application key generations", [String(describing: count)]))
                        .seleneFont(.text, .regular, design: .monospaced)
                        .foregroundColor(SeleneTheme.success)
                }

                HStack(spacing: SeleneTokens.Space.line) {
                    Button(setup.isProdKeysValid ? L10n.text("Replace Key...") : L10n.text("Import Key...")) {
                        setup.selectProdKeysFile()
                    }
                    .buttonStyle(OortPressStyle())
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                    .seleneKeyRing(focusedRowTitle == "prod.keys" && focusedButton == 0)
                    .disabled(configurationLocked)
                    Button(L10n.text("Detect Ryujinx...")) { viewModel.selectRyujinxFolder() }
                        .buttonStyle(OortPressStyle())
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                        .seleneKeyRing(focusedRowTitle == "prod.keys" && focusedButton == 1)
                        .disabled(configurationLocked)
                    Spacer()
                }
    }

    private func publishActions() {
        onActions([
            .init(id: "keys", title: "prod.keys", isEnabled: !configurationLocked,
                  secondary: ("Detect Ryujinx...", { viewModel.selectRyujinxFolder() })) {
                setup.selectProdKeysFile()
            }
        ])
    }
}
