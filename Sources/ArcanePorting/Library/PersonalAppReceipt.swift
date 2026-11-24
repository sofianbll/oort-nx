import Foundation
import NXLibraryCore

/// Proof of a successful personal transfer, kept only in this launcher's profile.
package struct PersonalAppReceipt: Codable, Equatable, Sendable {
    private let titleID: String
    private let origin: Origin
    package let inventorySHA256: String
    package let publishedAt: Date?
    private let localSHA256: String

    private struct Origin: Codable, Equatable, Sendable {
        let account: String
        let folder: String

        init?(_ scope: CloudDriveScope?) {
            guard let scope, [scope.account, scope.library.id].allSatisfy({
                $0 != "root" && $0 != "appDataFolder"
                    && $0.range(of: #"^[A-Za-z0-9_-]{1,256}\z"#, options: .regularExpression) != nil
            }) else { return nil }
            account = scope.account
            folder = scope.library.id
        }
    }

    package struct Store: Sendable {
        private let directory: URL

        package init(in profile: URL = AppData.supportRoot) {
            directory = profile.appendingPathComponent("personal-app-receipts", isDirectory: true)
        }

        package func receipt(titleID: String, scope: CloudDriveScope?) -> PersonalAppReceipt? {
            guard let origin = Origin(scope), let file = location(titleID),
                  let data = try? SaveFiles.readRegular(file, limit: 4096),
                  let receipt = try? JSONDecoder().decode(PersonalAppReceipt.self, from: data),
                  receipt.origin == origin, receipt.titleID == titleID.uppercased(),
                  [receipt.inventorySHA256, receipt.localSHA256].allSatisfy({
                      $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
                  }) else { return nil }
            return receipt
        }

        package func record(_ manifest: CloudGameManifest, for game: CloudArchiveGame,
                            scope: CloudDriveScope?) throws {
            guard let origin = Origin(scope), let file = location(game.titleID),
                  manifest.titleID == game.titleID,
                  let artifact = manifest.artifacts.first(where: { $0.kind == .app }),
                  let app = game.locations[.app] else { return }
            try SaveFiles.safePath(app)
            let before = try CloudArchiveInventory.signature(app, kind: .app)
            let snapshot = try CloudArchiveInventory.scan(app, kind: .app)
            let digest = try artifact.files == nil ? snapshot.sha256
                : CloudArtifactFiles.digest(CloudArtifactFiles.entries(at: app, snapshot: before))
            guard !before.hasExcludedFiles, !snapshot.hasExcludedFiles, digest == artifact.inventorySHA256,
                  try CloudArchiveInventory.signature(app, kind: .app).sha256 == before.sha256 else { return }
            let receipt = PersonalAppReceipt(titleID: game.titleID, origin: origin, inventorySHA256: digest,
                                             publishedAt: artifact.publishedAt, localSHA256: snapshot.sha256)
            try SaveFiles.makeDirectory(directory)
            try SaveFiles.durableWrite(receipt, to: file)
        }

        private func location(_ titleID: String) -> URL? {
            let title = titleID.uppercased()
            return SaveLocation.validID(title) ? directory.appendingPathComponent(title + ".json") : nil
        }
    }
}
