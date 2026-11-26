import AppKit
import ArcanePorting
import Foundation
@testable import NXLibrary
import NXLibraryCore
import SwiftUI

@main struct DowngradeProbe {
    private static let fm = FileManager.default
    private static let gameID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private static let profileID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
    private static let title = "0100123456789ABC"
    private static let date = Date(timeIntervalSinceReferenceDate: 20_000)
    private static let lastKnown = "NXLibrary_CloudLastKnownAvailability"
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
    private static let root = AppData.supportRoot
    private static var preferences: URL { root.appendingPathComponent("fixture-preferences.plist") }
    private static var catalog: CatalogRepository { CatalogRepository(store: .init(directory: root)) }
    private static let queue = CloudTransferQueue()
    private static func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    @MainActor static func main() async throws {
        let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!).resolvingSymlinksInPath()
        precondition(AppData.profile.home.resolvingSymlinksInPath().path == home.path)
        precondition(root.path.hasPrefix(home.path + "/"))
        switch CommandLine.arguments[1] {
        #if LEGACY
        case "seed": try await seed()
        case "direct": try await baseline(direct: true)
        case "restored": try await baseline(direct: false)
        #else
        case "upgrade": try await upgrade()
        case "after-direct": try await updated(restored: false)
        case "restored": try await updated(restored: true)
        case "capture":
            let language: AppLanguage = CommandLine.arguments[2] == "fr" ? .french : .english
            let scenario = CommandLine.arguments[4]
            let notice: DevelopmentStartup.Notice = switch scenario {
            case "failed": .failed
            case "disk-full": .diskFull
            case "partial": .copy([.artwork, .sound])
            default: .copy([])
            }
            let context = AppLocale(language: language, region: nil)
            let warning = DowngradeWarningView(notice: notice, retry: {}, proceed: {}, context: context)
            check(warning.risk.contains("Oort\u{00a0}NX\u{00a0}0.3.0"), "version does not break across lines")
            let renderer = ImageRenderer(content: Group {
                if scenario == "progress" { DowngradeCopyProgress(context: context) }
                else { warning }
            }.seleneCanvasRoot().frame(width: 1120, height: 630))
            guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        #endif
        default: preconditionFailure("Unknown fixture phase")
        }
    }

    private static func write(_ data: Data, _ name: String) throws {
        let file = url(name)
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    private static func savePrefs(_ values: [String: Any]) throws {
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0).write(to: preferences)
    }

    private static func prefs() throws -> [String: Any] {
        try PropertyListSerialization.propertyList(from: Data(contentsOf: preferences), format: nil) as! [String: Any]
    }

    private static func readJSON(_ name: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url(name))) as! [String: Any]
    }

    private static func readCloud() throws -> CloudLibraryModel {
        AppData.preferences.setVolatileDomain(try prefs(), forName: UserDefaults.argumentDomain)
        return CloudLibraryModel()
    }

    private static func check(_ condition: Bool, _ detail: String) {
        precondition(condition, detail)
    }

    @MainActor private static func play(seconds: Double) {
        var time = date.addingTimeInterval(10_000)
        let history = PlaySessionStore(now: { time })
        check(history.start(gameID: gameID, sourceID: title), "new session")
        time += seconds
        check(history.end(gameID: gameID).count == 1 && history.loadError == nil, "save session")
    }

    private static func profiles(_ settings: AppSettings) -> LocalProfileStore {
        LocalProfileStore(settings: settings, name: "Unexpected")
    }

    #if LEGACY
    @MainActor private static func seed() async throws {
        var document = try catalog.load()
        let game = PortedGame(id: gameID, name: "Fixture NX", url: url("uninstalled.app"), platform: .macApp,
                             sizeBytes: 0, modificationDate: date, titleId: title)
        document.games = [.init(nxnative: game), .init(steam: .init(appID: 42, name: "Fixture Steam"))]
        document.sources = [.init(integration: .nxnative, isEnabled: true),
                            .init(integration: .steam, isEnabled: true, rootURL: url("fixture-steam"))]
        _ = try CatalogStore(directory: root).save(document, expectedRevision: document.revision)
        let settings = AppSettingsStore()
        settings.settings.soundVolume = 0.2
        let profileStore = profiles(settings.settings)
        var player = LocalProfile(id: profileID, name: "Before", look: .init(settings.settings))
        check(player.setPIN("0420") && profileStore.update(player) && profileStore.choose(profileID), "profile and selection")

        let sessions = (0..<200).map { i in
            let start = date.addingTimeInterval(Double(i) * 20)
            return PlaySession(gameID: gameID, titleID: title, bundleID: nil, startedAt: start,
                               endedAt: start + 10, lastHeartbeatAt: start + 10)
        }
        try write(JSONEncoder().encode(sessions), "play-sessions.json")
        try write(JSONSerialization.data(withJSONObject: [["gameID": gameID.uuidString,
            "playtime": ["duration": 300, "lastPlayed": date.timeIntervalSinceReferenceDate - 1]]]), "play-sessions-totals.json")
        check(PlaySessionStore().totalDuration(for: gameID) == 2300, "old split sessions and totals")

        try savePrefs([CloudLibraryPreference.storageKey: "fixture:Old",
                       CloudLibraryPreference.enabledKey: true,
                       CloudLibraryPreference.sourcesRootKey: "Old/GameFiles",
                       "NXLibrary_SetupSteamChoice": false])
        _ = try ArtworkPicks().save(png, titleID: title, slot: .icon)
        try write(png, "artwork/\(title)/square.png")
        let steam = SteamPersonalizationStore(directory: url("integrations/steam/personal"))
        try steam.save(fields: [.developer: "Before"], images: [.icon: png], automatic: [], titleID: "steam-42")
        print("0.3.0 seed: 200 sessions + 300 s carried = 2300 s; selected PIN profile; Steam and Switch.")
    }

    @MainActor private static func baseline(direct: Bool) async throws {
        let history = PlaySessionStore()
        check(history.sessions.count == 200 && history.totalDuration(for: gameID) == 2300, "0.3.0 only reads split history")
        let settings = AppSettingsStore()
        check(settings.settings.soundVolume == (direct ? 0.7 : 0.2), "shared setting survives")
        check(settings.settings.interfaceSounds, "old sound control remains available")
        let profileStore = profiles(settings.settings)
        check(profileStore.active?.id == profileID && profileStore.active?.matchesPIN("0420") == true, "profile selection and PIN")
        check(profileStore.active?.name == (direct ? "After" : "Before"), "profile data")

        let document = try catalog.load()
        check(document.source(.steam)?.isEnabled == true, "Steam source recognized")
        check(document.games.count == 2 && document.preservedGames.count == (direct ? 1 : 0), "opaque Mac shortcut")
        check(document.preservedSources.count == (direct ? 1 : 0), "opaque Mac integration")
        let game = document.games.first { $0.id == gameID }!.nxnativeGame!
        check(game.cloudImportPending == (direct ? true : nil), "cloud placeholder fields known to both")
        let pick = ArtworkPicks().url(titleID: title, slot: .icon)
        check(pick != nil && ArtworkStore().cachedURL(titleID: title, kind: .square) != nil, "artwork pick and cache")
        let steam = SteamPersonalizationStore(directory: url("integrations/steam/personal"))
        check(steam.value(titleID: "steam-42", field: .developer) == (direct ? "After" : "Before"), "Steam personalization")
        check(steam.url(titleID: "steam-42", slot: .icon) != nil, "Steam art")

        let state = try readCloud()
        let entries = await queue.load()
        check(state.preference.storage == "fixture:Old" && state.preference.sourcesRoot == "Old/GameFiles", "old cloud config")
        check(state.archive != nil && !state.downloadsCloudApp(game), "old model ignores move and last-known availability")
        if direct {
            let settingsBefore = try readJSON("settings.json")
            check(settingsBefore["soundPackID"] as? String == "oort" && settingsBefore["tileBadgePosition"] as? String == "bottomLeft",
                  "new settings untouched by read")
            let stateData = try Data(contentsOf: url("play-sessions-state.json"))
            let move = try Data(contentsOf: url("cloud-library-move.json"))
            let retained = prefsOrFail(lastKnown)
            check(entries.count == 1 && entries[0].action == .upload(.app)
                  && CloudTransferQueue.restoring(entries, gameIDs: [gameID]).count == 1
                  && state.storageScope(for: entries[0].action) == entries[0].storage, "old upload is eligible for resumption")
            check(settings.save(), "old settings rewrite")
            let saved = try readJSON("settings.json")
            check(saved["soundPackID"] == nil && saved["tileBadgePosition"] == nil, "unknown setting keys erased")
            let rewritten = try catalog.toggleFavorite(for: gameID)
            check(rewritten.preservedGames == document.preservedGames && rewritten.preservedSources == document.preservedSources,
                  "old rewrite preserves opaque entries")
            let records = try readJSON("catalog.json")["games"] as! [[String: Any]]
            let port = records.first { $0["integration"] as? String == "nxnative" }!["data"] as! [String: Any]
            check(port["discoveredCloudSourceDirectory"] == nil, "old rewrite strips new field in known record")
            var player = profileStore.active!
            player.rename(to: "Legacy edit")
            check(profileStore.update(player), "old profile rewrite")
            play(seconds: 40)
            check(PlaySessionStore().totalDuration(for: gameID) == 2340, "old edits its split sessions and totals")
            check(try Data(contentsOf: url("play-sessions-state.json")) == stateData, "new history bytes untouched")
            check(try Data(contentsOf: url("cloud-library-move.json")) == move, "pending move bytes untouched")
            check(AppData.preferences.data(forKey: lastKnown) == retained, "last-known preference unconsumed and unchanged")
            queue.save([])
            await queue.flush()
            check(await queue.load().isEmpty, "old queue writer can replace newer queue")
            print("Direct 0.3.0: 2300 s, then 2340 s in split history; settings keys and discovery lost on write; Mac preserved opaque; move ignored, upload eligible; artwork and profile read.")
        } else {
            check(entries.isEmpty && !fm.fileExists(atPath: url("cloud-library-move.json").path), "restored clean queue")
            print("Restored 0.3.0: 2300 s, original catalog, settings, profile and artwork; no next journal/queue.")
        }
    }

    private static func prefsOrFail(_ key: String) -> Data {
        guard let value = AppData.preferences.data(forKey: key) else { preconditionFailure("missing fixture preference") }
        return value
    }
    #else
    @MainActor private static func upgrade() async throws {
        let previous = AppData.profile.legacySupportRoot.appendingPathComponent("fixture-preferences.plist")
        check(try LibraryMove(from: AppData.profile.legacySupportRoot, to: root).prepare(preferences: {
            try PropertyListSerialization.propertyList(from: Data(contentsOf: previous), format: nil) as! [String: Any]
        }, savePreferences: savePrefs), "0.3.0 data copied into the beta's own folder")
        check(LibraryMove.moved(root), "the beta uses a separate verified library")
        check(try DowngradeCheckpoint.prepare(in: root, acceptingWarning: LibraryMove.moved(root), preferences: prefs) == .ready,
              "No downgrade warning is needed when the original folder remains")
        let split = try ["play-sessions.json", "play-sessions-totals.json"].map { try Data(contentsOf: url($0)) }
        play(seconds: 60)
        check(PlaySessionStore().totalDuration(for: gameID) == 2360, "next imports split and folds atomically")
        check(try ["play-sessions.json", "play-sessions-totals.json"].map { try Data(contentsOf: url($0)) } == split, "split inputs untouched")
        let settings = AppSettingsStore()
        settings.settings.soundVolume = 0.7
        settings.settings.soundPackID = "oort"
        settings.settings.tileBadgePosition = .bottomLeft
        let profileStore = profiles(settings.settings)
        var player = profileStore.active!
        player.rename(to: "After")
        check(profileStore.update(player), "new profile data")

        var document = try catalog.load()
        let i = document.games.firstIndex { $0.id == gameID }!
        var game = document.games[i].nxnativeGame!
        game.url = url("source-placeholder")
        game.cloudImportPending = true
        game.discoveredCloudSourceDirectory = "New Game Source"
        try document.games[i].replaceRecord(game)
        _ = try CatalogStore(directory: root).save(document, expectedRevision: document.revision)
        let shortcut = url("synthetic-shortcut.app")
        try write(PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Fixture Mac", "CFBundleIdentifier": "invalid.test.fixture",
            "CFBundlePackageType": "APPL", "CFBundleExecutable": "Synthetic",
        ], format: .xml, options: 0), "synthetic-shortcut.app/Contents/Info.plist")
        let synthetic = "synthetic-shortcut.app/Contents/MacOS/Synthetic"
        try write(Data(), synthetic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url(synthetic).path)
        _ = try catalog.addMacShortcut(at: shortcut)

        let cloud = try readCloud()
        cloud.remember { $0.personalApps.insert(gameID) }
        var preferences = try prefs()
        preferences[lastKnown] = AppData.preferences.data(forKey: lastKnown)!
        try savePrefs(preferences)
        let name = String(repeating: "a", count: 64) + ".aar"
        let plan = try JSONDecoder().decode(CloudDriveFolders.MovePlan.self, from: Data("""
        {"source":"Old","remote":"fixture","games":1,"bytes":7,
        "binding":{"account":"accountA","sourceID":"oldID","destinationID":"newID","destination":"New"},
        "entries":[{"file":{"key":{"value":"\(title)/app/\(name)"},"size":7,"hashes":{}},"dependencies":[]}]}
        """.utf8))
        let journal = LibraryMoveJournal(in: root)
        try journal.begin(.init(id: UUID(), request: .init(plan: plan, destination: "New"), sourcesRoot: "Old/GameFiles"))
        queue.save([.init(id: gameID, action: .upload(.app), token: UUID(), storage: "fixture:Old")])
        await queue.flush()
        try SteamPersonalizationStore(directory: url("integrations/steam/personal"))
            .save(fields: [.developer: "After"], images: [.icon: png], automatic: [], titleID: "steam-42")
        print("next: 2360 s in unified history; test data from real next writers, including a bound pending cloud move.")
    }

    @MainActor private static func updated(restored: Bool) async throws {
        check(PlaySessionStore().totalDuration(for: gameID) == 2360, "new history ignores 0.3.0 writes to split inputs")
        let settings = AppSettingsStore()
        check(settings.settings.soundPackID == (restored ? "oort" : "selene"), "new sound choice across old rewrite")
        check(settings.settings.tileBadgePosition == (restored ? .bottomLeft : .topRight), "badge setting across old rewrite")
        let document = try catalog.load()
        check(document.games.count == 3 && document.games.contains { $0.macShortcut != nil }, "Mac shortcut available again")
        let game = document.games.first { $0.id == gameID }!.nxnativeGame!
        check(game.discoveredCloudSourceDirectory == (restored ? "New Game Source" : nil), "source discovery across old rewrite")
        check(profiles(settings.settings).active?.name == (restored ? "After" : "Legacy edit"), "profiles remain shared")
        let cloud = try readCloud()
        check(cloud.hasPendingMove && cloud.archive == nil, "new app respects pending move")
        check(cloud.lastKnown.personalApps == [gameID], "new app reads last-known preference")
        check(await queue.load().count == (restored ? 1 : 0), "variant of queue retained in each fixture")
        print(restored ? "Restored next: 2360 s, sound, discovery, shortcut, profile, queue and pending move recovered."
                       : "Direct next after 0.3.0: 2360 s (old +40 hidden), settings/discovery lost; shortcut and move still readable.")
    }
    #endif
}
