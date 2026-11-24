import SwiftUI
import NXLibraryCore
import ArcanePorting

/// Porting → Cloud saves: one save-sync choice for every ported game, applied at its next launch.
struct SettingsCloudSavesSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var cloudSaves: CloudSaves { settings.settings.cloudSaves }

    private var pickedFolderSubtitle: String {
        let picked = settings.settings.cloudSavesPickedFolder
        return picked.isEmpty ? L10n.text("None chosen yet.") : (picked as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SeleneButtonRow("Cloud saves",
                            subtitle: "All games · Next launch",
                            info: "Applied before each game starts, including Off. Custom save-sync overrides are reported in Saves. Cloud sync covers only the primary user and device save.",
                            buttonTitle: cloudSaves.title, action: viewModel.askCloudSaves)

            SeleneButtonRow("Cloud saves folder",
                            subtitle: pickedFolderSubtitle,
                            buttonTitle: "Choose…") { viewModel.chooseCloudSavesFolder() }

        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        onActions([
            .init(id: "cloudSaves", title: "Cloud saves", activate: viewModel.askCloudSaves),
            .init(id: "cloudSavesFolder", title: "Cloud saves folder") { viewModel.chooseCloudSavesFolder() }
        ])
    }
}
