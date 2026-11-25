// The cloud library on a simulator, against Tests/PhoneLibrary/fake_drive.py on this machine: no real account, no real game.
// OORT_PORT comes from scripts/test_app.sh.
import CryptoKit
import XCTest

final class OortCloudTests: OortScreens {
    private static let port = env["OORT_PORT"] ?? "8799"
    private let key = P256.Signing.PrivateKey()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var code: String {
        "{\"oort\":\"drive-1\",\"kind\":\"ios\",\"client\":\"1-oort.apps.googleusercontent.com\",\"folder\":\"ROOT\",\"signer\":\"\(key.publicKey.derRepresentation.base64EncodedString())\"}"
    }

    // MARK: The stand-in for Google Drive

    @discardableResult private func server(_ path: String, _ body: Data? = nil) -> Data {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.port)\(path)")!)
        if let body { (request.httpMethod, request.httpBody) = ("POST", body) }
        var answer = Data()
        let done = expectation(description: path)
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { XCTFail("the stand-in: \(error)") }
            answer = data ?? Data()
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 60)
        return answer
    }
    private func set(_ path: String, _ text: String) { server(path, Data(text.utf8)) }
    private struct Call: Decodable { let call: String, node: String?, first: Int64?, last: Int64? }
    private func asked() -> [Call] { (try? JSONDecoder().decode([Call].self, from: server("/__log"))) ?? [] }
    private func fault(_ text: String) { set("/__faults", "[\(text)]") }

    private var nodes: [[String: Any]] = []
    private var count = 0
    private func folder(_ parent: String?, _ name: String, id: String? = nil) -> String {
        count += 1
        let id = id ?? "d\(count)"
        nodes.append(["id": id, "name": name, "parent": parent as Any? ?? NSNull(), "type": "folder"])
        return id
    }
    @discardableResult private func file(_ parent: String, _ name: String, _ data: Data) -> String {
        count += 1
        nodes.append(["id": "f\(count)", "name": name, "parent": parent, "base64": data.base64EncodedString()])
        return "f\(count)"
    }
    private static func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// A build as the Mac would leave it. Returns the identifiers of its files.
    @discardableResult
    private func build(_ title: String, _ name: String, version: String = "1.0.0", stamp: Int64 = 1_790_000_000_000, files: [String: Data], os: String = "26.0",
                       features: [String] = [], host: Int = 1, signed: Bool = true, place: String? = nil) -> [String: String] {
        let game = place ?? folder("ROOT", "\(name) [\(title)]"), targets = folder(game, "targets"), ios = folder(targets, "ios")
        return add(to: ios, title, name, version, stamp, files, os, features, host, signed)
    }
    private func add(to ios: String, _ title: String, _ name: String, _ version: String, _ stamp: Int64, _ files: [String: Data], _ os: String = "26.0",
                     _ features: [String] = [], _ host: Int = 1, _ signed: Bool = true) -> [String: String] {
        let sorted = files.sorted { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }
        let canonical = "[" + sorted.map { "{\"path\":\"\($0.key)\",\"sha256\":\"\(Self.hex($0.value))\",\"size\":\($0.value.count)}" }.joined(separator: ",") + "]"
        let digest = Self.hex(Data(canonical.utf8)), total = files.values.reduce(0) { $0 + $1.count }
        let manifest: [String: Any] = ["format": "oort-target", "version": 1, "title_id": title, "game_name": name, "game_version": version, "platform": "ios",
            "created_at": "2026-11-25T10:00:00Z", "engine": ["commit": String(repeating: "ab", count: 20)],
            "requires": ["os": os, "arch": "arm64", "features": features, "host": host], "package": ["path": "Game.framework"], "unpacked_size": total,
            "entry_count": files.count, "inventory_sha256": digest, "entries": sorted.map { ["path": $0.key, "size": $0.value.count, "sha256": Self.hex($0.value)] }]
        let data = try! JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .withoutEscapingSlashes])
        let signer = signed ? key : P256.Signing.PrivateKey()
        let seal = try! signer.signature(for: Data("oort-target-1\n".utf8) + data).derRepresentation
        let stem = String(format: "%016lld", stamp) + "-" + Self.hex(data)
        file(ios, stem + ".json", data)
        file(ios, stem + ".sig", seal)
        var folders = ["": folder(ios, digest)], ids: [String: String] = [:]
        for (path, body) in sorted {
            let parts = path.split(separator: "/").map(String.init)
            var at = ""
            for part in parts.dropLast() {
                let next = at.isEmpty ? part : at + "/" + part
                if folders[next] == nil { folders[next] = folder(folders[at]!, part) }
                at = next
            }
            ids[path] = file(folders[at]!, parts.last!, body)
        }
        return ids
    }

    /// The framework of an invented game, with the simulator's code in the first one.
    private func framework(_ index: Int) throws -> [String: Data] {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("oort-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try CaptureGames.make(in: root, marker: Self.marker)
        let folder = root.appendingPathComponent("Frameworks/DmGame\(CaptureGames.all[index].id).framework")
        var files: [String: Data] = [:]
        for case let path as String in fm.enumerator(atPath: folder.path)! {
            var isFolder: ObjCBool = false
            fm.fileExists(atPath: folder.appendingPathComponent(path).path, isDirectory: &isFolder)
            if !isFolder.boolValue { files["Game.framework/" + path] = try Data(contentsOf: folder.appendingPathComponent(path)) }
        }
        files["Game.framework/DmGame"] = try Data(contentsOf: XCTUnwrap(Self.bundle.privateFrameworksURL).appendingPathComponent("DmGame.framework/DmGame"))
        return files
    }
    private func invented(_ size: Int, _ seed: UInt8) -> Data { Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 9) ^ seed }) }

    private var mainFiles: [String: String] = [:]
    /// One game that runs, one small one, and one for each reason a game does not go on this device.
    private func library(update: Bool = false) throws {
        (nodes, count) = ([], 0)
        _ = folder(nil, "Games", id: "ROOT")
        let g = CaptureGames.all
        let place = folder("ROOT", "\(g[0].name) [\(g[0].id)]"), ios = folder(folder(place, "targets"), "ios")
        var files = try framework(0)
        files["data/romfs/marker"] = Data("m".utf8)
        files["data/romfs/big.bin"] = invented(6 << 20, 1)
        mainFiles = add(to: ios, g[0].id, g[0].name, "1.0.0", 1_790_000_000_000, files)
        if update {
            files["data/romfs/big.bin"] = invented(2 << 20, 9)
            files["data/romfs/new.bin"] = invented(1000, 3)
            _ = add(to: ios, g[0].id, g[0].name, "1.1.0", 1_790_000_100_000, files)
        }
        var second = try framework(1)
        second["data/romfs/marker"] = Data("m".utf8)
        second["data/romfs/big.bin"] = invented(2 << 20, 2)
        build(g[1].id, g[1].name, version: "2.3.0", files: second)
        let mac = folder("ROOT", "\(g[2].name) [\(g[2].id)]")
        _ = folder(mac, "manifests")
        build(g[3].id, g[3].name, files: try framework(3), os: "99.0")
        build(g[4].id, g[4].name, files: try framework(4), features: ["apple99"])
        build(g[5].id, g[5].name, files: try framework(5), host: 2)
        build("0100000000AA7000", "Ombre", files: try framework(5), signed: false)
        let vector: [String: Any] = ["drive": ["root": "ROOT", "page_size": 1000, "nodes": nodes], "auth": ["refresh": "none"], "faults": []]
        server("/__vector", try JSONSerialization.data(withJSONObject: vector))
    }

    // MARK: Steps

    private func open(_ more: [String] = [], reset: Bool = true, library games: Games = .none) throws {
        set("/__down", "0"); set("/__slow", "0"); fault("")
        if reset {
            try start(games, ["-OortFakeDrivePort", Self.port, "-OortFakeReset", "YES"] + more) { documents in
                try? FileManager.default.removeItem(at: documents.deletingLastPathComponent().appendingPathComponent("Library/Application Support/Cloud"))
            }
        } else { again(more) }
    }
    private func again(_ more: [String] = []) {
        app.launchArguments = ["-AppleLanguages", "(\(Self.lang))", "-AppleLocale", Self.lang == "fr" ? "fr_FR" : "en_US", "-OortFakeDrivePort", Self.port] + more
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60))
    }
    private func line(_ label: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch }
    private func audit(_ screen: String) throws {
        auditing = true
        defer { auditing = false }
        try look(screen)
    }
    private func press(_ key: String) { tap(line(say(key)), say(key)) }

    private func toCloud() {
        tab("Settings")
        press("Integrations")
        press("Cloud library")
    }
    private func paste(_ text: String) {
        press("Paste the code")
        let field = app.descendants(matching: .any)["oort.code"].firstMatch
        guard field.waitForExistence(timeout: 15) else { return XCTFail("no field for the code") }
        field.tap()
        field.typeText(text)
        shot("61-code")
        press("Use this code")
    }
    private func signIn(_ allow: Bool = true) {
        press("Sign in with Google")
        let link = app.links[allow ? "Allow" : "Refuse"].firstMatch
        let go = springboard.buttons.matching(NSPredicate(format: "label IN {'Continue', 'Continuer'}")).firstMatch
        for _ in 0..<20 where !link.exists {
            if go.exists { go.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        guard link.waitForExistence(timeout: 20) else {
            note("\(name) browser\n\(app.debugDescription)", in: "missing.txt")
            return XCTFail("the sign-in page is not shown")
        }
        shot("62-browser")
        link.tap()
    }
    private func join() {
        toCloud()
        press("Turn on")
        paste(code)
        signIn()
        shows("Folder found", 40)
    }
    private func toGame(_ name: String) {
        tab("Library")
        let cloud = app.buttons["Cloud"].firstMatch
        if cloud.waitForExistence(timeout: 10) { cloud.tap() }
        tap(app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch, name)
    }
    private func dismissNotice() {
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN {'Allow', 'Autoriser'}")).firstMatch
        if allow.waitForExistence(timeout: 4) { allow.tap() }
    }
    private func files(_ path: String) throws -> Set<String> {
        let root = try home().appendingPathComponent(path)
        return Set(FileManager.default.enumerator(atPath: root.path)?.compactMap { $0 as? String } ?? [])
    }
    private func until(_ seconds: TimeInterval, _ what: String, _ done: () -> Bool) {
        let end = Date(timeIntervalSinceNow: seconds)
        while Date() < end { if done() { return }; Thread.sleep(forTimeInterval: 0.5) }
        note("\(name) never: \(what)\n\(app.debugDescription)", in: "missing.txt")
        XCTFail("never: \(what)")
    }

    // MARK: Tests

    func test60OffAsksNothing() throws {
        try library()
        _ = asked()
        try open()
        toCloud()
        shows("It reads")
        shot("60-off")
        try audit("cloud-off")
        tab("Library")
        XCTAssertFalse(app.buttons["Cloud"].exists, "no cloud in the library while it is off")
        XCTAssertTrue(asked().isEmpty, "nothing was asked while it is off")
    }

    func test61Codes() throws {
        try library()
        try open()
        toCloud()
        press("Turn on")
        shows("Scan your Mac's code")
        shot("63-steps")
        try audit("cloud-steps")
        paste("hello")
        shows("This is not a code from Oort NX on your Mac.")
        shot("64-code-refused")
        paste(code.replacingOccurrences(of: "\"ios\"", with: "\"desktop\""))
        shows("This code is for an Android device.")
        press("Scan your Mac's code")
        shows("No camera here")
        shot("65-scan-no-camera")
        press("Close")
        XCTAssertTrue(asked().isEmpty, "a code asks nothing of the network")
        paste(code)
        signIn(false)
        shows("Google did not give access. Nothing was changed.")
        shot("66-refused")
        XCTAssertFalse(asked().contains { ["list", "media", "token"].contains($0.call) })
        signIn()
        shows("Folder found", 40)
        shot("67-found")
        try audit("cloud-ready")
        app.swipeUp()
        shot("68-found-more")
    }

    func test62DownloadInstallPlay() throws {
        try library()
        try open()
        join()
        press("See the games")
        shows(CaptureGames.all[0].name)
        shot("70-cloud")
        try audit("cloud-library")
        app.swipeUp()
        shows("Not for this device")
        for key in ["Not prepared for this device yet. Prepare it on your Mac.", "Needs a newer system.", "This device's graphics cannot run it.",
                    "Needs another version of Oort NX.", "Not signed by your Mac: left out."] { shows(key) }
        app.swipeUp()
        shot("71-not-here")
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        toGame(CaptureGames.all[0].name)
        shot("72-cloud-game")
        try audit("cloud-game")
        set("/__slow", "500000")
        press("Download")
        dismissNotice()
        Thread.sleep(forTimeInterval: 4)
        shot("73-downloading")
        press("Pause")
        shows("Paused")
        shot("74-paused")
        let before = asked().filter { $0.call == "media" && $0.node == mainFiles["data/romfs/big.bin"] }
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(asked().filter { $0.call == "media" }.isEmpty, "paused: nothing is asked")
        set("/__slow", "900000")
        press("Resume")
        Thread.sleep(forTimeInterval: 3)
        // The app is ended, then opened again: the same range goes on, what is here is not asked for again.
        app.terminate()
        let cut = asked().filter { $0.call == "media" && $0.node == mainFiles["data/romfs/big.bin"] }
        set("/__slow", "0")
        again()
        toGame(CaptureGames.all[0].name)
        until(60, "ready after a relaunch") { line(say("Install")).exists }
        let after = asked().filter { $0.call == "media" && $0.node == mainFiles["data/romfs/big.bin"] }
        note("ranges before \(before.compactMap(\.first)) cut \(cut.compactMap(\.first)) after \(after.compactMap(\.first))", in: "words.txt")
        XCTAssertFalse(after.contains { $0.first == 0 } && before.count + cut.count > 2, "what was received is not asked for again")
        shot("75-ready")
        press("Install")
        until(40, "installed") { line(say("Play")).exists }
        shot("76-installed")
        let games = try files("Documents/games/\(CaptureGames.all[0].id)")
        XCTAssertTrue(games.contains("romfs/big.bin"))
        XCTAssertTrue(try files("Documents/Frameworks").contains("DmGame\(CaptureGames.all[0].id).framework/DmGame"))
        press("Play")
        let game = app.staticTexts["Invented game main, save ready"]
        XCTAssertTrue(game.waitForExistence(timeout: 30), "the installed game runs")
        shot("77-plays")
        tap(button("Quit the invented game"), "Quit")
        XCTAssertFalse(asked().contains { ["write", "other", "revoke"].contains($0.call) }, "the cloud is only read")
    }

    func test63UpdateThenRemove() throws {
        try library()
        try open()
        join()
        toGame(CaptureGames.all[0].name)
        press("Download")
        dismissNotice()
        until(60, "ready") { line(say("Install")).exists }
        press("Install")
        until(40, "installed") { line(say("Play")).exists }
        let save = try home().appendingPathComponent("Documents/games/\(CaptureGames.all[0].id)/save/slot")
        try FileManager.default.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("precious".utf8).write(to: save)
        try library(update: true)
        back()
        app.swipeDown()
        tab("Settings")
        press("Look again")
        toGame(CaptureGames.all[0].name)
        shows("Update")
        shot("78-update")
        press("Update")
        until(60, "ready") { line(say("Install")).exists }
        press("Install")
        until(40, "installed again") { line(say("Play")).exists }
        XCTAssertTrue(try files("Documents/games/\(CaptureGames.all[0].id)").contains("romfs/new.bin"))
        XCTAssertEqual(try String(contentsOf: save, encoding: .utf8), "precious", "an update leaves the save")
        app.swipeUp()
        press("Game page")
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        press("Remove from this device")
        press("Remove the game, keep its saves")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(try files("Documents/Frameworks").contains { $0.hasSuffix("DmGame") }, "the game is gone")
        XCTAssertEqual(try String(contentsOf: save, encoding: .utf8), "precious", "the save stays")
        shot("79-removed")
        XCTAssertFalse(asked().contains { ["write", "other", "revoke"].contains($0.call) }, "the cloud is only read")
    }

    func test64WhatGoesWrong() throws {
        try library()
        try open()
        join()
        // A file that is not the one that was signed.
        toGame(CaptureGames.all[1].name)
        fault("{\"on\": \"media\", \"times\": 99, \"do\": \"corrupt\"}")
        press("Download")
        dismissNotice()
        shows("The file received is not the one your Mac sent. Nothing was installed.", 60)
        shot("80-wrong-file")
        fault("{\"on\": \"media\", \"times\": 99, \"do\": \"status\", \"status\": 403, \"reason\": \"downloadQuotaExceeded\"}")
        press("Try again")
        shows("Google has reached its download limit for now. Try again tomorrow.", 60)
        shot("81-quota")
        fault("")
        press("Cancel the download")
        until(20, "cancelled") { line(say("Download")).exists }
        XCTAssertTrue(try files("Library/Application Support/Cloud/builds/.incoming").isEmpty, "a cancelled download leaves nothing")
        // No room.
        app.terminate()
        again(["-OortFakeFree", "1000000"])
        toGame(CaptureGames.all[0].name)
        press("Download")
        let room = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", Self.lang == "fr" ? "Pas assez de place" : "Not enough room")).firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 30), "no room is said")
        shot("82-no-room")
        press("Cancel the download")
        // Mobile data.
        app.terminate()
        again(["-OortFakeMetered", "YES"])
        toGame(CaptureGames.all[0].name)
        press("Download")
        shows("Waiting for Wi-Fi.", 30)
        shot("83-wifi")
        _ = asked()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(asked().contains { $0.call == "media" }, "no mobile data")
        // The connection breaks and comes back.
        app.terminate()
        again()
        set("/__slow", "400000")
        toGame(CaptureGames.all[0].name)
        Thread.sleep(forTimeInterval: 3)
        set("/__down", "1")
        Thread.sleep(forTimeInterval: 6)
        shot("84-cut")
        set("/__down", "0")
        set("/__slow", "0")
        until(120, "ready after a cut") { line(say("Install")).exists }
        // Access withdrawn.
        set("/__revoke", "")
        app.terminate()
        again()
        tab("Library")
        let cloud = app.buttons["Cloud"].firstMatch
        if cloud.waitForExistence(timeout: 10) { cloud.tap() }
        shows("Google asks you to sign in again.", 40)
        shot("85-revoked")
        try audit("cloud-revoked")
    }

    func test65TurnOff() throws {
        for deleting in [false, true] {
            try library()
            try open()
            join()
            toGame(CaptureGames.all[1].name)
            press("Download")
            dismissNotice()
            until(60, "ready") { line(say("Install")).exists }
            toCloudAgain()
            press("Turn off")
            shows("Turn the cloud library off?")
            shot(deleting ? "87-off-delete" : "86-off")
            if !deleting { try audit("cloud-turn-off") }
            press(deleting ? "Delete the downloads" : "Keep the downloads")
            shows("It reads", 20)
            let left = try files("Library/Application Support/Cloud/builds").contains { $0.hasSuffix("big.bin") }
            XCTAssertEqual(left, !deleting)
            _ = asked()
            app.terminate()
            again()
            tab("Library")
            Thread.sleep(forTimeInterval: 2)
            XCTAssertFalse(app.buttons["Cloud"].exists)
            XCTAssertTrue(asked().isEmpty, "off again: nothing is asked")
        }
    }
    private func toCloudAgain() {
        tab("Settings")
        if !line(say("Turn off")).waitForExistence(timeout: 3) { toCloud() }
        app.swipeUp()
    }

    func test66Background() throws {
        try library()
        try open()
        join()
        toGame(CaptureGames.all[0].name)
        set("/__slow", "600000")
        press("Download")
        dismissNotice()
        Thread.sleep(forTimeInterval: 2)
        _ = asked()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 25)
        let away = asked().filter { $0.call == "media" }
        note("in the background: \(away.count) ranges asked", in: "words.txt")
        shot("88-home-screen")
        app.activate()
        set("/__slow", "0")
        until(60, "ready after the background") { line(say("Install")).exists }
    }

    func test67EndedInTheBackground() throws {
        try library()
        try open(["-OortFakeExit", "YES"])
        join()
        toGame(CaptureGames.all[0].name)
        set("/__slow", "300000")
        press("Download")
        dismissNotice()
        Thread.sleep(forTimeInterval: 2)
        _ = asked()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
        note("ended in the background: \(app.state != .runningForeground), state \(app.state.rawValue)", in: "words.txt")
        Thread.sleep(forTimeInterval: 25)
        let away = asked().filter { $0.call == "media" }
        note("after the app was ended: \(away.count) ranges asked, inbox \((try? files("Library/Application Support/Cloud/inbox")) ?? []), state \(app.state.rawValue)", in: "words.txt")
        set("/__slow", "0")
        again()
        toGame(CaptureGames.all[0].name)
        until(60, "ready after being ended") { line(say("Install")).exists }
    }

    func test68LargestTextAndLandscape() throws {
        try library()
        try open(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        toCloud()
        shot("90-off-large")
        app.swipeUp(); app.swipeUp()
        press("Turn on")
        shot("91-steps-large")
        paste(code)
        signIn()
        shows("Folder found", 40)
        shot("92-found-large")
        tab("Library")
        tap(app.buttons["Cloud"].firstMatch, "Cloud")
        shot("93-cloud-large")
        try audit("cloud-library-large")
        app.terminate()
        again()
        toGame(CaptureGames.all[0].name)
        XCUIDevice.shared.orientation = .landscapeLeft
        shot("94-game-landscape")
        back()
        shot("95-cloud-landscape")
        toCloudAgain()
        shot("96-settings-landscape")
    }
}
