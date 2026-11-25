#if os(macOS)
import Foundation
import OortCore
import Testing
@testable import OortDrive

/// The cases of `Tests/PhoneLibrary/vectors`, which the Android module answers too.
@Suite(.serialized) struct VectorTests {
    static let names: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: FakeDrive.folder.appendingPathComponent("vectors").path)) ?? [])
        .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()

    @Test func everyVectorIsThere() { #expect(Self.names.count >= 75) }

    @Test(arguments: names) func vector(_ name: String) async throws {
        let file = FakeDrive.folder.appendingPathComponent("vectors/\(name).json")
        let vector = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let client = vector["client"] as! [String: Any], device = client["device"] as! [String: Any]
        let free = (client["free"] as! NSNumber).int64Value, isMetered = client["metered"] as! Bool
        let drive = try FakeDrive(file)
        let work = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let scratch = work.appendingPathComponent("scratch"), waits = Box<[Int]>([])
        let vault = MemoryVault(DriveSecret("RT-CANARY-0"))
        let key = Data(base64Encoded: vector["key"] as! String)!, crypto = ShelfCrypto.apple(signer: key)
        let root = (vector["drive"] as! [String: Any])["root"] as! String
        let invite = DriveInvite(client: .init(id: "1-a.apps.googleusercontent.com", kind: .ios, secret: nil), folder: root, signer: key)
        let connection = DriveConnection(invite: invite, vault: vault, transport: DriveSession(allowsMeteredNetwork: true),
                                         endpoints: drive.endpoints(up: client["network"] as! String == "up"), scratch: scratch)
        let connectors = ShelfConnectors([connection.connector], choices: MemoryChoices())
        if client["on"] as! Bool { try connectors.turnOn(DriveConnection.id, granting: Set(ShelfConnector.Permission.allCases)) }
        let retry = ShelfRetry { seconds in waits.change { $0.append(seconds) } }
        let protected = Box<Set<String>>([])
        let store = ShelfStore(root: work.appendingPathComponent("store"), crypto: crypto,
                               available: { _ in free },
                               keepOutOfBackup: { url in
                                   var url = url, values = URLResourceValues()
                                   values.isExcludedFromBackup = true
                                   try url.setResourceValues(values)
                                   protected.change { _ = $0.insert(url.path) }
                               })
        let here = ShelfDevice(platform: ShelfPlatform(rawValue: device["platform"] as! String)!, system: device["system"] as! String,
                               architecture: device["architecture"] as! String, features: Set(device["features"] as! [String]), host: device["host"] as! Int)
        let rules = ShelfRules(allowsMeteredNetwork: client["allow_metered"] as! Bool, chunk: (client["chunk"] as! NSNumber).int64Value,
                               reserve: (client["reserve"] as! NSNumber).int64Value)
        func catalog() async throws -> ShelfCatalog {
            ShelfCatalog(source: try await connectors.source(DriveConnection.id), crypto: crypto, retry: retry, scratch: scratch)
        }
        func list(_ installed: [String: String] = [:], _ order: ShelfOrder = .name) async throws -> ShelfListing {
            try await catalog().list(for: here, installed: installed, order: order)
        }
        // The builds are known from an unhurried listing; a fault may be meant for the download alone.
        var known: [String: ShelfBuild] = [:]

        for (number, step) in (vector["steps"] as! [[String: Any]]).enumerated() {
            let expected = step["expect"] as! [String: Any], label = Comment(rawValue: "\(name), step \(number)")
            let title = step["title"] as? String
            if let title, known[title] == nil, ["download", "discard", "tamper_part"].contains(step["do"] as! String) {
                for game in try await list().games { known[game.titleID] = game.build }
                #expect(known[title] != nil, label)
            }
            _ = try drive.log()
            waits.change { $0 = [] }
            var code: String?
            do {
                switch step["do"] as! String {
                case "list":
                    let installed = step["installed"] as? String == "store" ? store.installed() : step["installed"] as? [String: String] ?? [:]
                    let listing = try await list(installed, ShelfOrder(rawValue: step["order"] as? String ?? "name")!)
                    if let games = expected["games"] as? [[String: String]] {
                        let seen = listing.games.map { ["title": $0.titleID, "name": $0.name, "version": $0.build.gameVersion, "digest": $0.build.digest, "state": $0.state.rawValue] }
                        #expect(seen == games, label)
                    }
                    if let hidden = expected["hidden"] as? [[String]] { #expect(listing.hidden.map { [$0.titleID, $0.name, $0.reason.rawValue] } == hidden, label) }
                    if let problems = expected["problems"] as? [[String]] { #expect(listing.problems.map { [$0.titleID, $0.error.code] } == problems, label) }
                case "mac":
                    let build = try #require(try await catalog().macBuild(of: title!))
                    if let version = expected["version"] as? String {
                        #expect(build.name == expected["name"] as? String && build.gameVersion == version && build.engineCommit == expected["engine"] as? String, label)
                        #expect(build.bytes == (expected["bytes"] as! NSNumber).int64Value && build.stamp == (expected["stamp"] as! NSNumber).int64Value, label)
                    }
                case "download":
                    let build = known[title!]!, stop = step["cancel_after"] as? Int, chunks = Box(-1), task = Box<Task<URL, any Error>?>(nil)
                    let started = Box(false)
                    let download = ShelfDownload(source: try await connectors.source(DriveConnection.id), store: store, rules: rules, retry: retry,
                                                 isMetered: { isMetered })
                    task.change { slot in
                        slot = Task {
                            while !started.value { await Task.yield() }
                            return try await download.run(build) { progress in
                                #expect(progress.received <= progress.total && progress.total == build.bytes)
                                chunks.change { $0 += 1 }
                                if chunks.value == stop { task.value?.cancel() }
                            }
                        }
                    }
                    started.change { $0 = true }
                    let visible = try await task.value!.value
                    let wanted = try #require(expected["files"] as? [String: String], label)
                    var seen: [String: String] = [:]
                    for path in paths(under: visible) { seen[path] = try sha256(visible.appendingPathComponent(path)) }
                    #expect(seen == wanted, label)
                    #expect(try visible.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, label)
                case "discard": try store.discard(known[title!]!)
                case "turn_off": try await connectors.turnOff(DriveConnection.id)
                case "credential": break
                case "tamper_part":
                    let part = try #require(files(under: work).first { $0.pathExtension == "part" })
                    var data = try Data(contentsOf: part)
                    data[0] ^= 0xFF
                    try data.write(to: part)
                default: Issue.record(label)
                }
            } catch is CancellationError { code = "cancelled" } catch let error as ShelfError {
                code = error.code
                for text in [String(describing: error), String(reflecting: error), error.localizedDescription] { #expect(!text.contains("CANARY"), label) }
                var dumped = ""
                dump(error, to: &dumped)
                #expect(!dumped.contains("CANARY"), label)
            }
            #expect(code == expected["error"] as? String, label)
            let calls = try drive.log()
            #expect(!calls.contains { ["write", "other", "revoke"].contains($0.call) }, label)
            if let count = step["calls"] as? Int { #expect(calls.filter { $0.call != "token" }.count == count, label) }
            if let wanted = step["waits"] as? [Int] { #expect(waits.value == wanted, label) }
            if let media = step["media"] as? [[Any]] {
                let seen = calls.filter { $0.call == "media" }.map { "\($0.node!) \($0.first!)-\($0.last!)" }
                #expect(seen == media.map { "\($0[0]) \($0[1])-\($0[2])" }, label)
            }
            if let wanted = expected["credential"] as? Bool { #expect(try (vault.read() != nil) == wanted, label) }
            if let build = title.flatMap({ known[$0] }) {
                if let wanted = expected["visible"] as? Bool { #expect(FileManager.default.fileExists(atPath: store.visible(build).path) == wanted, label) }
                if let wanted = expected["waiting"] as? Bool { #expect(FileManager.default.fileExists(atPath: store.waiting(build).path) == wanted, label) }
                if expected["waiting"] as? Bool == true { #expect(protected.value.contains { $0.hasSuffix(".incoming") }, label) }
            }
            for file in files(under: work) { #expect(try Data(contentsOf: file).range(of: Data("CANARY".utf8)) == nil, label) }
        }
        #expect(files(under: scratch).isEmpty, "nothing is left behind")
    }
}
#endif
