import SwiftUI
import OortLibrary
import NxnativeAdapter

/// Porting → Cloud saves: one save-sync choice for every ported game, applied at its next launch.
struct SettingsCloudSavesSection: View {
    @ObservedObject var settings: SettingsEditor
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var cloudSaves: CloudSaves { settings.settings.cloudSaves }

    private var pickedFolderSubtitle: String {
        let picked = settings.settings.cloudSavesPickedFolder
        return picked.isEmpty ? L10n.text("None chosen yet.") : CloudSaves.displayPath(picked)
    }

    var body: some View {
        OortSettingsGroup {
            SeleneCycleRow("Cloud saves",
                            subtitle: "All games · Next launch",
                            info: "Applied before each game starts, including Off. Custom save-sync overrides are reported in Saves. Cloud sync covers only the primary user and device save.",
                            value: cloudSaves.title, verbatimValue: true, cycle: stepChoice)

            SeleneButtonRow("Cloud saves folder",
                            subtitle: pickedFolderSubtitle, verbatimSubtitle: true,
                            buttonTitle: "Choose…", action: chooseFolder)

        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        onActions([
            .value("cloudSaves", "Cloud saves", cycle: stepChoice),
            .init(id: "cloudSavesPickedFolder", title: "Cloud saves folder", activate: chooseFolder)
        ])
    }

    func stepChoice(_ step: Int) {
        let picked = settings.settings.cloudSavesPickedFolder
        let choices: [CloudSaves] = [.off, .iCloudDrive] + (picked.isEmpty ? [] : [.folder(picked)])
        if let next = choices.stepped(from: cloudSaves, step) { settings.settings.cloudSaves = next }
    }

    private func chooseFolder() {
        OortFilePickerPresentation.open(.folder, title: L10n.text("Cloud saves folder"),
            message: L10n.text("Choose the folder every game syncs its save through, for example one in iCloud Drive."),
            startingAt: CloudSaves.iCloudDriveRoot()) { urls in
            guard let url = urls.first else { return }
            var draft = settings.settings
            draft.cloudSavesPickedFolder = url.path
            draft.cloudSaves = .folder(url.path)
            settings.settings = draft
        }
    }
}
