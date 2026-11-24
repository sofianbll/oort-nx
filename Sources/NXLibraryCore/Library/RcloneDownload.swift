import CryptoKit
import Darwin
import Foundation
import Security

/// The optional Drive helper is not part of the app or of the game build runtime.
public struct RcloneDownload: Sendable {
    public static let version = "1.75.2"
    public static let host = "downloads.rclone.org"

    struct Release: Sendable {
        let url: URL
        let bytes: Int
        let sha256: String
        let member: String
        let executableBytes: Int
    }

    static let release = Release(
        url: URL(string: "https://\(host)/v\(version)/rclone-v\(version)-osx-arm64.zip")!,
        bytes: 32_648_708, sha256: "610ab7d48615135dfc60b763858b11a426a0d3d1160c1bb76fb0ae6011b02edd",
        member: "rclone-v\(version)-osx-arm64/rclone", executableBytes: 88_766_114)
    public static var downloadBytes: Int { release.bytes }

    public enum Failure: Error, Equatable, Sendable {
        case network, response, redirect, integrity, space, installation

        public var messageKey: String {
            switch self {
            case .network: return "Could not reach the rclone download server. Check your connection and retry."
            case .response, .redirect: return "The official rclone download did not complete. Retry."
            case .integrity: return "The rclone download could not be verified. Nothing was installed."
            case .space: return "There is not enough space on this Mac to install rclone."
            case .installation: return "Could not change Oort NX’s copy of rclone. Retry."
            }
        }
    }

    let directory: URL
    private var executable: URL { directory.appendingPathComponent("rclone") }
    private static let receipt = "oort-install"

    public init(supportRoot: URL) {
        directory = supportRoot.appendingPathComponent("DriveTools", isDirectory: true)
            .appendingPathComponent("rclone-\(Self.version)", isDirectory: true)
    }

    private var parent: URL { directory.deletingLastPathComponent() }
    private var supportRoot: URL { parent.deletingLastPathComponent() }

    public var installedExecutable: URL? {
        guard Self.isDirectory(supportRoot), Self.isDirectory(parent), Self.isDirectory(directory),
              !Self.isLink(executable), RcloneStorageBackend.isExecutable(executable),
              Self.hasReceipt(in: directory),
              (try? FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()) == [Self.receipt, "rclone"],
              Self.hasValidSignature(executable)
        else { return nil }
        return executable
    }

    private static func isLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func isDirectory(_ url: URL) -> Bool {
        !isLink(url) && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func hasReceipt(in directory: URL) -> Bool {
        let receipt = directory.appendingPathComponent(Self.receipt)
        let values = try? receipt.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        return !isLink(receipt) && values?.isRegularFile == true && values?.fileSize == 0
    }

    public func moveInstalledCopyToTrash() throws {
        let files = FileManager.default
        guard installedExecutable != nil else { throw Failure.installation }
        do { try files.trashItem(at: directory, resultingItemURL: nil) }
        catch { throw Failure.installation }
    }

    public func install(progress: @escaping @MainActor @Sendable (Double) async -> Void) async throws -> URL {
        try await install(Self.release, transport: .ephemeral, progress: progress)
    }

    func install(_ release: Release, transport: URLSessionConfiguration,
                 available: (URL) throws -> Int? = { try $0.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity },
                 progress: @escaping @MainActor @Sendable (Double) async -> Void = { _ in }) async throws -> URL {
        let files = FileManager.default
        do {
            try Task.checkCancellation()
            guard RedirectPolicy.allows(release.url, origin: Self.release.url) else { throw Failure.redirect }
            if let installedExecutable { return installedExecutable }
            if !Self.isDirectory(supportRoot) {
                try files.createDirectory(at: supportRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            guard Self.isDirectory(supportRoot) else { throw Failure.installation }
            if !Self.isDirectory(parent) {
                try files.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
            guard Self.isDirectory(parent) else { throw Failure.installation }
            if let free = try available(parent), free < release.bytes + release.executableBytes { throw Failure.space }
            let stage = parent.appendingPathComponent(".download-\(UUID())", isDirectory: true)
            try files.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? files.removeItem(at: stage) }
            let archive = stage.appendingPathComponent("download.zip")
            try await Self.fetch(release, to: archive, configuration: transport, progress: progress)
            let payload = stage.appendingPathComponent("payload", isDirectory: true)
            try files.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let candidate = payload.appendingPathComponent("rclone")
            try Self.extract(release, archive: archive, to: candidate)
            guard Self.hasValidSignature(candidate) else { throw Failure.integrity }
            try Data().write(to: payload.appendingPathComponent(Self.receipt), options: .withoutOverwriting)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: candidate.path)
            try Task.checkCancellation()
            guard renamex_np(payload.path, directory.path, UInt32(RENAME_EXCL)) == 0 else {
                if errno == ENOSPC { throw Failure.space }
                throw Failure.installation
            }
            return executable
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if let failure = error as? Failure { throw failure }
            if Self.outOfSpace(error) { throw Failure.space }
            if error is URLError { throw Failure.network }
            throw Failure.installation
        }
    }

    private static func fetch(_ release: Release, to archive: URL, configuration: URLSessionConfiguration,
                              progress: @escaping @MainActor @Sendable (Double) async -> Void) async throws {
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: RedirectPolicy(origin: release.url), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: release.url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (body, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              RedirectPolicy.allows(response.url, origin: release.url) else { throw Failure.redirect }
        if (300..<400).contains(response.statusCode) { throw Failure.redirect }
        guard response.statusCode == 200,
              response.expectedContentLength == -1 || response.expectedContentLength == Int64(release.bytes)
        else { throw Failure.response }
        try Data().write(to: archive, options: .withoutOverwriting)
        let output = try FileHandle(forWritingTo: archive)
        defer { try? output.close() }
        var hash = SHA256(), chunk = Data(), received = 0
        chunk.reserveCapacity(256 * 1024)
        for try await byte in body {
            guard received < release.bytes else { throw Failure.response }
            received += 1
            chunk.append(byte)
            if chunk.count == 256 * 1024 {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
                hash.update(data: chunk)
                chunk.removeAll(keepingCapacity: true)
                if received.isMultiple(of: 1024 * 1024) { await progress(Double(received) / Double(release.bytes)) }
            }
        }
        try Task.checkCancellation()
        guard received == release.bytes else { throw Failure.response }
        hash.update(data: chunk)
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == release.sha256 else {
            throw Failure.integrity
        }
        try output.write(contentsOf: chunk)
        try output.close()
        await progress(1)
    }

    private static func extract(_ release: Release, archive: URL, to candidate: URL) throws {
        try Task.checkCancellation()
        try Data().write(to: candidate, options: .withoutOverwriting)
        let output = try FileHandle(forWritingTo: candidate)
        defer { try? output.close() }
        // Only the pinned member of an already verified archive is ever extracted; no archive path becomes a local path.
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-p", archive.path, release.member]
        unzip.environment = [:]
        unzip.standardOutput = output
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            if unzip.terminationStatus == 50 { throw Failure.space } // Info-ZIP: disk full.
            throw Failure.integrity
        }
        guard try candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize == release.executableBytes else {
            throw Failure.integrity
        }
    }

    private static func hasValidSignature(_ url: URL) -> Bool {
        var code: SecStaticCode?
        return SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess
            && code.map { SecStaticCodeCheckValidity($0, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess } == true
    }

    private static func outOfSpace(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC))
            || (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError)
            || (error.userInfo[NSUnderlyingErrorKey] as? NSError).map(outOfSpace) == true
    }

    final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let origin: URL
        init(origin: URL) { self.origin = origin }

        static func allows(_ url: URL?, origin: URL) -> Bool {
            guard let url else { return false }
            return url.scheme == "https" && url.host == origin.host && (url.port == nil || url.port == 443)
                && url.user == nil && url.password == nil
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(Self.allows(request.url, origin: origin) ? request : nil)
        }
    }
}
