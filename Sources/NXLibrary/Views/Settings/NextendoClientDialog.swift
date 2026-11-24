import SwiftUI
import NXLibraryCore
import ArcanePorting

struct NextendoClientDialog: View {
    @ObservedObject var settings: SettingsEditor
    let onClose: () -> Void
    @State private var draft = ""
    @State private var focus: SeleneConfirmButton = .confirm
    @FocusState private var fieldFocused: Bool
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization

    private var valid: Bool { draft.isEmpty || NextendoAuthorization.validClientID(draft) }

    var body: some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: onClose)
            SeleneConfirmDialog(title: L10n.text("Nextendo client ID", context: localization),
                                message: L10n.text("Public OAuth client ID for sign-in and online play. Clear the field to use the build default.", context: localization),
                                 confirmTitle: "Done", confirmEnabled: valid, focus: $focus,
                                onCancel: onClose, onConfirm: save) {
                TextField(L10n.text("Nextendo client ID", context: localization), text: $draft)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit(save)
                    .onExitCommand(perform: onClose)
                    .seleneFont(17)
                    .foregroundColor(SeleneTheme.ink)
                    .padding(canvas.u(16))
                    .background(RoundedRectangle(cornerRadius: canvas.u(12)).fill(SeleneTheme.glassLight))
                    .padding(.top, canvas.u(24))
                if !valid {
                    Text(NextendoError.clientID.localizedDescription)
                        .foregroundColor(SeleneTheme.danger)
                        .seleneFont(15)
                }
            }
        }
        .onAppear {
            draft = settings.settings.nextendoClientID ?? NextendoLaunch.buildClientID ?? ""
            fieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxSettingsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            switch action {
            case .navigateLeft: focus = .left
            case .navigateRight: focus = .right
            case .confirm: focus == .confirm ? save() : onClose()
            case .cancel: onClose()
            default: break
            }
        }
    }

    private func save() {
        guard valid else { return }
        settings.settings.nextendoClientID = draft.isEmpty || draft == NextendoLaunch.buildClientID ? nil : draft
        onClose()
    }
}
