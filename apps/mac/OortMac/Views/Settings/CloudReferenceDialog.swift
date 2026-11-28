import SwiftUI
import OortLibrary

struct CloudReferenceDialog: View {
    let viewModel: AppViewModel
    let onClose: () -> Void
    @State private var draft = ""
    @State private var focus: SeleneConfirmButton = .confirm
    @FocusState private var fieldFocused: Bool
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization

    private var folder: String? { CloudLibraryPreference.referenceFolderID(draft) }
    private var buttonFocus: Binding<SeleneConfirmButton> {
        Binding(get: { folder == nil ? .cancel : focus }, set: { focus = $0 })
    }

    var body: some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: onClose)
            SeleneConfirmDialog(title: text("Reference library"),
                message: text("You follow this folder in read-only mode. Your library is not shared in return. Readers can download apps, caches and game files that Google Drive lets them see.\n\nWhen sharing, use a dedicated folder without keys or saves."),
                confirmTitle: "Save", confirmEnabled: folder != nil, focus: buttonFocus,
                onCancel: onClose, onConfirm: save) {
                field
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink)
                    .padding(canvas.u(SeleneTokens.Space.medium))
                    .oortWell(radius: canvas.u(SeleneTokens.Radius.content))
                    .padding(.top, canvas.u(SeleneTokens.Space.large))
                if !draft.isEmpty, folder == nil {
                    Text(text("Enter a Google Drive folder link or a valid folder ID."))
                        .foregroundColor(SeleneTheme.danger)
                        .seleneFont(.text)
                }
            }
        }
        .onAppear {
            #if DEBUG
            if Self.oortProbeStill { return }
            #endif
            draft = viewModel.cloudLibrary.preference.referenceFolder ?? ""
            fieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxSettingsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            switch action {
            case .navigateUp: fieldFocused = true
            case .navigateLeft: focus = .left
            case .navigateRight where folder != nil: focus = .right
            case .confirm: buttonFocus.wrappedValue == .confirm ? save() : onClose()
            case .cancel: onClose()
            default: break
            }
        }
    }

    @ViewBuilder private var field: some View {
        #if DEBUG
        if Self.oortProbeStill {
            // ImageRenderer cannot draw the AppKit text field: the same text, laid out in its place.
            Text(draft.isEmpty ? text("Google Drive folder link or ID") : draft)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            textField
        }
        #else
        textField
        #endif
    }

    private var textField: some View {
        TextField(text("Google Drive folder link or ID"), text: $draft)
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .onSubmit(save)
            .onExitCommand(perform: onClose)
    }

    private func save() {
        guard let folder, viewModel.canConfigureCloudLibrary else { return }
        viewModel.followCloudReference(folder)
        if folder == viewModel.cloudLibrary.preference.referenceFolder { onClose() }
    }

    private func text(_ key: String) -> String { L10n.text(key, context: localization) }
}

#if DEBUG
/// Probes only (run_cloud_reference.py): the dialog offscreen, with a typed draft. Release builds do not contain them.
extension CloudReferenceDialog {
    @MainActor static var oortProbeStill = false
    func oortProbeDraft(_ draft: String) -> Self {
        var copy = self
        copy._draft = State(initialValue: draft)
        return copy
    }
}
#endif
