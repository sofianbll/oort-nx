import SwiftUI
import AppKit
import NXLibraryCore

/// Adds the player's SteamGridDB API key: pasted, checked with SteamGridDB, then kept on this Mac. Shown from
/// Settings → Online services and from Change artwork. Return saves, Esc cancels; on a controller A chooses the focused pill,
/// Left/Right move between them and B cancels. The owner stops its own input while the dialog is open.
struct SteamGridDBKeyDialog: View {
    @ObservedObject var viewModel: AppViewModel
    /// Where the owner's screen posts controller actions.
    let gamepad: Notification.Name
    /// True when a key was saved.
    let onClose: (Bool) -> Void

    @State private var draft = ""
    @State private var message: String?
    @State private var checking = false
    @State private var focus: SeleneConfirmButton = .confirm
    @FocusState private var fieldFocused: Bool
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { close(saved: false) }
            SeleneConfirmDialog(title: L10n.text("SteamGridDB key"),
                                message: L10n.text("Paste the API key from Preferences → API in your SteamGridDB profile. It stays on this Mac."),
                                confirmTitle: checking ? "Checking…" : L10n.text("Save"),
                                confirmEnabled: !checking && SteamGridDBKey.normalized(draft) != nil,
                                focus: $focus, onCancel: { close(saved: false) }, onConfirm: save) {
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small)) {
                    TextField(L10n.text("API key"), text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: max(13, canvas.u(17)), design: .monospaced))
                        .focused($fieldFocused)
                        .onSubmit(save)
                        .onExitCommand { close(saved: false) }
                        .disabled(checking)
                    HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                        Text(message ?? L10n.text("Free with a SteamGridDB account."))
                            .foregroundColor(message == nil ? SeleneTheme.ink60 : SeleneTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        OortLink(title: "Get a key") { NSWorkspace.shared.open(SteamGridDBArt.keyPage) }
                    }
                    .seleneFont(.text)
                }
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink)
                .padding(canvas.u(SeleneTokens.Space.medium))
                .oortWell(radius: canvas.u(SeleneTokens.Radius.content))
                .padding(.top, canvas.u(SeleneTokens.Space.large))
                .onAppear { fieldFocused = true }
            }
        }
        .onExitCommand { close(saved: false) }
        .onReceive(NotificationCenter.default.publisher(for: gamepad)) { note in
            guard let action = note.object as? GamepadAction else { return }
            switch action {
            case .navigateUp: fieldFocused = true
            case .navigateLeft: focus = .left
            case .navigateRight: focus = .right
            case .confirm: focus == .cancel ? close(saved: false) : save()
            case .cancel: close(saved: false)
            default: break
            }
        }
    }

    private func close(saved: Bool) {
        guard !checking else { return }
        if !saved { SoundEffectService.shared.play(.focus) }
        onClose(saved)
    }

    private func save() {
        guard !checking, SteamGridDBKey.normalized(draft) != nil else {
            message = SteamGridDBError.invalidKey.localizedDescription
            SoundEffectService.shared.play(.error)
            return
        }
        checking = true
        message = nil
        let text = draft
        Task { @MainActor in
            let problem = await viewModel.saveSteamGridDBKey(text)
            checking = false
            if let problem {
                message = problem
                SoundEffectService.shared.play(.error)
            } else {
                SoundEffectService.shared.play(.click)
                close(saved: true)
            }
        }
    }
}
