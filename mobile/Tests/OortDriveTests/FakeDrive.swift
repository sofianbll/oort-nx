import CryptoKit
import Foundation
import OortCore
@_spi(Checks) @testable import OortDrive

/// `Tests/PhoneLibrary/fake_drive.py`, one process per test, on 127.0.0.1.
final class FakeDrive {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../Tests/PhoneLibrary").standardized

    let process = Process()
    let port: Int
    private let input = Pipe()

    init(_ vector: URL) throws {
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-I", "-B", Self.folder.appendingPathComponent("fake_drive.py").path, vector.path]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
        guard let port = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ShelfError.localFile }
        self.port = port
    }

    deinit {
        // Not `waitUntilExit`: it runs a run loop, which can wait for ever on one of Swift's own threads.
        try? input.fileHandleForWriting.close()
        process.terminate()
    }

    func endpoints(up: Bool = true) -> DriveEndpoints {
        let base = URL(string: "http://127.0.0.1:\(up ? port : 1)")!
        return .init(authorize: base.appendingPathComponent("auth"), token: base.appendingPathComponent("token"),
                     revoke: base.appendingPathComponent("revoke"), files: base.appendingPathComponent("drive/v3/files"))
    }

    struct Call: Decodable { let call: String, node: String?, first: Int64?, last: Int64?, fields: [String]? }

    /// What was asked since the last time.
    func log() throws -> [Call] {
        try JSONDecoder().decode([Call].self, from: Data(contentsOf: URL(string: "http://127.0.0.1:\(port)/__log")!))
    }

    func remember(code: String, challenge: String) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/__code")!)
        request.httpMethod = "POST"
        request.httpBody = Data("code=\(code)&challenge=\(challenge)".utf8)
        _ = try await URLSession.shared.data(for: request)
    }
}

final class MemoryVault: DriveVault, @unchecked Sendable {
    private let lock = NSLock()
    private var secret: DriveSecret?
    init(_ secret: DriveSecret?) { self.secret = secret }
    func read() throws -> DriveSecret? { lock.withLock { secret } }
    func write(_ secret: DriveSecret) throws { lock.withLock { self.secret = secret } }
    func erase() throws { lock.withLock { secret = nil } }
}

final class MemoryChoices: ShelfChoices, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Set<String>] = [:]
    func permissions(of connector: String) -> Set<String>? { lock.withLock { values[connector] } }
    func set(_ permissions: Set<String>?, of connector: String) { lock.withLock { values[connector] = permissions } }
}

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.withLock { stored } }
    func change(_ body: (inout T) -> Void) { lock.withLock { body(&stored) } }
}

func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("oort-drive-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

func sha256(_ file: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
}

/// Relative paths of the plain files.
func paths(under root: URL) -> [String] {
    guard let walk = FileManager.default.enumerator(atPath: root.path) else { return [] }
    var result: [String] = []
    while let path = walk.nextObject() as? String { if walk.fileAttributes?[.type] as? FileAttributeType != .typeDirectory { result.append(path) } }
    return result
}

func files(under root: URL) -> [URL] { paths(under: root).map { root.appendingPathComponent($0) } }
