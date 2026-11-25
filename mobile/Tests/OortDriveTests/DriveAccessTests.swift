#if os(macOS)
import CryptoKit
import Foundation
import OortCore
import Testing
@testable import OortDrive

@Suite(.serialized) struct DriveAccessTests {
    let signer = P256.Signing.PrivateKey().publicKey.derRepresentation.base64EncodedString()
    let client = "1234-abc.apps.googleusercontent.com"
    static let vector = FakeDrive.folder.appendingPathComponent("vectors/list-ios.json")

    func code(_ changes: [String: String?] = [:]) throws -> String {
        var object = ["oort": "drive-1", "kind": "ios", "client": client, "folder": "1AbC_d-E", "signer": signer]
        for (key, value) in changes { object[key] = value }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    @Test func theCodeToScanIsStrict() throws {
        let invite = try #require(DriveInvite.parse(try code()))
        #expect(invite.folder == "1AbC_d-E" && invite.client.callbackScheme == "com.googleusercontent.apps.1234-abc")
        let desktop = try #require(DriveInvite.parse(try code(["kind": "desktop", "secret": "GOCSPX-s3cret_value"])))
        #expect(!"\(desktop)".contains("s3cret") && !String(reflecting: desktop).contains("s3cret"))
        let refused: [[String: String?]] = [["refresh_token": "x"], ["access_token": "x"], ["token": "x"], ["extra": ""], ["oort": "drive-2"], ["kind": "web"],
            ["client": "evil.example.com"], ["client": "a.apps.googleusercontent.com.evil"], ["client": client + "\n"], ["folder": "root"], ["folder": "a'b"],
            ["folder": "-x"], ["folder": ""], ["signer": "AAAA"], ["signer": nil], ["client": nil], ["secret": "with-ios"],
            ["kind": "desktop", "secret": "a&b=c"], ["folder": String(repeating: "a", count: 2000)]]
        for changes in refused { #expect(DriveInvite.parse(try code(changes)) == nil, "\(changes)") }
        for text in ["", "https://example.com", "[]", "{\"oort\":1}", "drive-1"] { #expect(DriveInvite.parse(text) == nil) }
    }

    @Test func theSignInPageAsksToReadAndNothingElse() throws {
        let signIn = DriveSignIn(client: try #require(DriveInvite.parse(try code())).client)
        let parts = try #require(URLComponents(url: signIn.page, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(parts.scheme == "https" && parts.host == "accounts.google.com" && parts.path == "/o/oauth2/v2/auth")
        #expect(items["scope"] == "https://www.googleapis.com/auth/drive.readonly" && items["response_type"] == "code")
        #expect(items["code_challenge_method"] == "S256" && items["redirect_uri"] == "com.googleusercontent.apps.1234-abc:/oauth2redirect")
        #expect(items.keys.sorted() == ["client_id", "code_challenge", "code_challenge_method", "redirect_uri", "response_type", "scope", "state"])
        #expect(!signIn.page.absoluteString.contains(signIn.verifier.reveal()))
        let other = DriveSignIn(client: signIn.client)
        #expect(other.verifier != signIn.verifier && other.state != signIn.state && signIn.verifier.reveal().count == 64)
        // RFC 7636, appendix B.
        #expect(DriveSignIn.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func googleOnlyHosts() { #expect(DriveEndpoints.google.hosts == ["accounts.google.com", "oauth2.googleapis.com", "www.googleapis.com"]) }

    private func connection(_ drive: FakeDrive, _ vault: MemoryVault, _ work: URL) throws -> DriveConnection {
        let invite = try #require(DriveInvite.parse(try code(["folder": "ROOT"])))
        return DriveConnection(invite: invite, vault: vault, transport: DriveSession(allowsMeteredNetwork: true), endpoints: drive.endpoints(), scratch: work)
    }

    private func signIn(_ connection: DriveConnection, _ drive: FakeDrive) throws -> DriveSignIn {
        let client = try #require(DriveInvite.parse(try code())).client
        return DriveSignIn(client: client, verifier: DriveSignIn.random(), state: DriveSignIn.random(), redirect: client.redirect, endpoints: drive.endpoints())
    }

    @Test func signingInKeepsTheRefreshTokenInTheVaultOnly() async throws {
        let drive = try FakeDrive(Self.vector), vault = MemoryVault(nil), work = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let connection = try connection(drive, vault, work), signIn = try signIn(connection, drive)
        try await drive.remember(code: "CODE-1", challenge: DriveSignIn.challenge(signIn.verifier.reveal()))
        try await connection.access.finish(signIn, callback: URL(string: signIn.redirect + "?state=\(signIn.state.reveal())&code=CODE-1&scope=x")!)
        #expect(try vault.read()?.reveal() == "RT-CANARY-NEW")
        let source = DriveSource(root: "ROOT", access: connection.access, transport: DriveSession(allowsMeteredNetwork: true), endpoints: drive.endpoints(), scratch: work)
        #expect(try await !source.children(of: "ROOT").isEmpty)
        let token = try #require(try drive.log().first { $0.call == "token" })
        #expect(token.fields == ["client_id", "code", "code_verifier", "grant_type", "redirect_uri"])
        #expect(!"\(connection.access)".contains("CANARY") && files(under: work).isEmpty)
        var dumped = ""
        dump(connection.access, to: &dumped)
        dump(try vault.read(), to: &dumped)
        #expect(!dumped.contains("CANARY"))
        try await connection.access.forget()
        #expect(try vault.read() == nil)
        await #expect(throws: ShelfError.signInNeeded) { _ = try await source.children(of: "ROOT") }
        #expect(try !drive.log().contains { $0.call == "revoke" })
    }

    @Test func aStolenOrForeignAnswerIsRefused() async throws {
        let drive = try FakeDrive(Self.vector), vault = MemoryVault(nil), work = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let connection = try connection(drive, vault, work), signIn = try signIn(connection, drive)
        let state = signIn.state.reveal(), back = signIn.redirect
        let refused: [(String, ShelfError)] = [(back + "?code=C", .badResponse), (back + "?state=other&code=C", .badResponse), (back + "?state=\(state)", .badResponse),
            (back + "?state=\(state)&code=C&code=D", .badResponse), (back + "?state=\(state)&state=\(state)&code=C", .badResponse),
            ("other.app:/oauth2redirect?state=\(state)&code=C", .badResponse), (signIn.client.callbackScheme + ":/elsewhere?state=\(state)&code=C", .badResponse),
            (back + "?state=\(state)&error=access_denied", .accessDenied), (back + "?error=access_denied", .badResponse)]
        for (text, error) in refused {
            await #expect(throws: error) { try await connection.access.finish(signIn, callback: URL(string: text)!) }
        }
        #expect(try drive.log().isEmpty)
        // A code taken by another app is worth nothing without the verifier.
        try await drive.remember(code: "CODE-2", challenge: DriveSignIn.challenge("another verifier"))
        await #expect(throws: ShelfError.signInNeeded) { try await connection.access.finish(signIn, callback: URL(string: back + "?state=\(state)&code=CODE-2")!) }
        #expect(try vault.read() == nil)
    }

    @Test(arguments: ["https://www.googleapis.com/auth/drive", "https://www.googleapis.com/auth/drive.readonly https://www.googleapis.com/auth/drive", "openid", ""])
    func anotherScopeIsRefused(_ scope: String) async throws {
        let work = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        var vector = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.vector)) as! [String: Any]
        vector["faults"] = [["on": "token", "times": 9, "do": "shrink", "scope": scope]]
        let file = work.appendingPathComponent("vector.json")
        try JSONSerialization.data(withJSONObject: vector).write(to: file)
        let drive = try FakeDrive(file), vault = MemoryVault(nil)
        let connection = try connection(drive, vault, work.appendingPathComponent("scratch")), signIn = try signIn(connection, drive)
        try await drive.remember(code: "CODE", challenge: DriveSignIn.challenge(signIn.verifier.reveal()))
        await #expect(throws: ShelfError.accessDenied) {
            try await connection.access.finish(signIn, callback: URL(string: signIn.redirect + "?state=\(signIn.state.reveal())&code=CODE")!)
        }
        #expect(try vault.read() == nil)
    }

    @Test func requestsRefusedTogetherRenewOnce() async throws {
        let drive = try FakeDrive(Self.vector), work = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let connection = try connection(drive, MemoryVault(DriveSecret("RT-CANARY-0")), work)
        let tokens = try await withThrowingTaskGroup(of: DriveSecret.self) { group in
            for _ in 0..<8 { group.addTask { try await connection.access.token() } }
            return try await group.reduce(into: Set<String>()) { $0.insert($1.reveal()) }
        }
        #expect(tokens.count == 1)
        #expect(try drive.log().filter { $0.call == "token" }.count == 1)
    }

    /// The real keychain is not touched here: only what would be asked of it.
    @Test func theKeychainItemStaysOnThisDevice() {
        let item = DriveKeychain(account: client).item.merging(DriveKeychain(account: client).attributes(DriveSecret("x"))) { $1 }
        #expect(item[kSecAttrAccessible] as! CFString == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        #expect(item[kSecAttrSynchronizable] as? Bool == false && item[kSecUseDataProtectionKeychain] as? Bool == true)
        #expect(item[kSecAttrAccessGroup] == nil)
    }

    @Test func aBackgroundSessionTakesTheSamePathAndKeepsNothing() {
        let configuration = URLSessionConfiguration.ephemeral
        _ = DriveSession(configuration: configuration)
        #expect(configuration.urlCache == nil && configuration.httpCookieStorage == nil && configuration.urlCredentialStorage == nil)
        #expect(!configuration.allowsCellularAccess && !configuration.allowsExpensiveNetworkAccess)
    }
}
#endif
