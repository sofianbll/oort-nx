import SwiftUI
import OortLibrary
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
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink)
                    .padding(canvas.u(SeleneTokens.Space.medium))
                    .oortWell(radius: canvas.u(SeleneTokens.Radius.content))
                    .padding(.top, canvas.u(SeleneTokens.Space.large))
                if !valid {
                    Text(NextendoError.clientID.localizedDescription)
                        .foregroundColor(SeleneTheme.danger)
                        .seleneFont(.text)
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
            case .navigateUp: fieldFocused = true
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
