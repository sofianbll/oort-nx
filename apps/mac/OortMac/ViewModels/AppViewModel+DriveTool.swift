import Foundation
import OortLibrary

extension AppViewModel {
    @MainActor func offerDriveUpgrade() {
        guard settingsNotice == nil, cloudLibrary.preference.enabled, cloudLibrary.needsDriveToolChoice, !cloudLibrary.driveToolOfferSeen,
              canStartLibraryMove else { return }
        cloudLibrary.markDriveToolOfferSeen()
        prepareDriveTool(fromStartup: true) {}
    }

    /// Explicit activation and migration share one consent boundary; browsing settings does not download.
    @MainActor func prepareDriveTool(fromStartup: Bool = false, then ready: @escaping () -> Void) {
        let cloud = cloudLibrary
        guard canStartLibraryMove, settingsNotice == nil else { return }
        let preference = cloud.preference
        let chosen = cloud.chosenExecutable
        let legacySources = cloud.legacySourcesToConfirm
        let resumeSources = legacySources.flatMap { folder in
            preference.storage.map { L10n.format("Oort NX will reconnect “%@” and keep “%@” as its game files folder.", [$0, folder]) }
        }.map { "\n\n" + $0 } ?? ""
        func stillCurrent() -> Bool {
            canStartLibraryMove && cloud.preference == preference && cloud.chosenExecutable == chosen
        }
        if let tool = cloud.resolvedDriveTool {
            if !cloud.needsDriveToolChoice {
                if cloud.archive == nil { cloud.acceptDriveTool() }
                ready()
                return
            }
            confirmSetting(L10n.text("Cloud library"),
                message: L10n.text("Use the rclone already on this Mac to reconnect to the same cloud library without moving your files?") + resumeSources,
                action: "Use existing rclone") { [weak self] in
                guard let self, stillCurrent(), cloud.resolvedDriveTool == tool else { return }
                if fromStartup { self.router?.openSettings(.cloudLibrary) }
                cloud.acceptDriveTool(confirmLegacySources: legacySources != nil)
                ready()
            }
            return
        }
        let size = (Double(RcloneDownload.downloadBytes) / 1_000_000)
            .formatted(.number.locale(L10n.context.formatLocale).precision(.fractionLength(1)))
        let download = L10n.format("Oort NX will download rclone %@ from %@ (%@ MB, MIT licence).",
                                   [RcloneDownload.version, RcloneDownload.host, size])
        let purpose = L10n.text("rclone is the open-source tool that reads and writes files in your own Google Drive; nothing is sent to Oort NX.")
        confirmSetting(L10n.text("Download rclone"),
             message: "\(download)\n\n\(purpose)\(resumeSources)",
            action: "Download") { [weak self] in
            guard let self, stillCurrent(), cloud.resolvedDriveTool == nil else { return }
            if fromStartup { self.router?.openSettings(.cloudLibrary) }
            cloud.driveToolFailure = nil
            cloud.isChangingConnection = true
            cloud.driveToolProgress = 0
            let installer = cloud.driveTool
            cloud.driveToolTask = Task { @MainActor [weak cloud = cloud] in
                guard let cloud else { return }
                defer {
                    cloud.driveToolProgress = nil
                    cloud.driveToolTask = nil
                    cloud.isChangingConnection = false
                }
                do {
                    _ = try await installer.install { [weak cloud] fraction in cloud?.driveToolProgress = fraction }
                    // The install is already atomic. On quit let the next launch pick up the verified tool.
                    guard !Task.isCancelled, !cloud.isQuitting, cloud.preference == preference,
                          cloud.chosenExecutable == chosen else { return }
                    cloud.acceptDriveTool(confirmLegacySources: legacySources != nil)
                    cloud.driveToolProgress = nil
                    cloud.isChangingConnection = false
                    ready()
                } catch is CancellationError {
                } catch {
                    cloud.driveToolFailure = (error as? RcloneDownload.Failure) ?? .installation
                }
            }
        }
    }

    @MainActor func trashDriveTool() {
        guard !cloudLibrary.preference.enabled, canStartLibraryMove, cloudLibrary.canTrashDriveTool else { return }
        cloudLibrary.stopRemoteControl()
        do { try cloudLibrary.driveTool.moveInstalledCopyToTrash() }
        catch {
            showSettingsNotice(title: L10n.text("rclone"), message: L10n.text(RcloneDownload.Failure.installation.messageKey))
        }
    }
}
