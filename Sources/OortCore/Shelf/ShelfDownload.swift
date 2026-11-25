import Foundation

public struct ShelfProgress: Equatable, Sendable {
    public let received: Int64
    public let total: Int64
}

/// Where downloads live on the device. Everything waits in `.incoming` and only a whole, checked build gets a visible folder.
public struct ShelfStore: Sendable {
    public let root: URL
    let crypto: ShelfCrypto
    let available: @Sendable (URL) -> Int64?
    let keepOutOfBackup: @Sendable (URL) throws -> Void

    /// `available`: free bytes for something the player asked for. `keepOutOfBackup`: a build can always be read again from the source.
    public init(root: URL, crypto: ShelfCrypto, available: @escaping @Sendable (URL) -> Int64?,
                keepOutOfBackup: @escaping @Sendable (URL) throws -> Void) {
        self.root = root
        self.crypto = crypto
        self.available = available
        self.keepOutOfBackup = keepOutOfBackup
    }

    public func visible(_ build: ShelfBuild) -> URL {
        root.appendingPathComponent(build.titleID, isDirectory: true).appendingPathComponent(build.digest, isDirectory: true)
    }

    /// Where a download waits; it exists while one is stopped half-way.
    public func waiting(_ build: ShelfBuild) -> URL {
        root.appendingPathComponent(".incoming", isDirectory: true)
            .appendingPathComponent("\(build.titleID)-\(build.platform.rawValue)-\(build.digest)", isDirectory: true)
    }

    /// Forgets what a stopped download kept. The visible copy, if any, stays.
    public func discard(_ build: ShelfBuild) throws {
        try? FileManager.default.removeItem(at: waiting(build))
    }

    /// The digest that is visible for each title: what `ShelfCatalog.list` takes as `installed`. The newest folder wins.
    public func installed() -> [String: String] {
        let fm = FileManager.default
        var result: [String: String] = [:]
        for title in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where ShelfNames.isTitleID(title) {
            let folder = root.appendingPathComponent(title, isDirectory: true)
            let digests = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { ShelfNames.isHex($0, count: 64) }
            func date(_ name: String) -> Date {
                let values = try? fm.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
                return values?[.modificationDate] as? Date ?? .distantPast
            }
            result[title] = digests.max { (date($0), $0) < (date($1), $1) }
        }
        return result
    }
}

/// The player's rules for a source.
public struct ShelfRules: Equatable, Sendable {
    public var allowsMeteredNetwork: Bool
    /// One request's worth: what a broken connection can lose.
    public var chunk: Int64
    /// Left free on the device beyond the build itself.
    public var reserve: Int64

    public init(allowsMeteredNetwork: Bool = false, chunk: Int64 = 16 << 20, reserve: Int64 = 256 << 20) {
        self.allowsMeteredNetwork = allowsMeteredNetwork
        self.chunk = max(1, chunk)
        self.reserve = max(0, reserve)
    }
}

/// Brings one build onto the device. Stop it at any moment and run it again: it asks only for the ranges that are missing.
public struct ShelfDownload: Sendable {
    /// A tree larger or deeper than this is not a build.
    static let maximumNodes = 100_000

    let source: any ShelfSource
    let store: ShelfStore
    let rules: ShelfRules
    let retry: ShelfRetry
    let isMetered: @Sendable () -> Bool

    public init(source: any ShelfSource, store: ShelfStore, rules: ShelfRules = .init(), retry: ShelfRetry = .standard,
                isMetered: @escaping @Sendable () -> Bool) {
        self.source = source
        self.store = store
        self.rules = rules
        self.retry = retry
        self.isMetered = isMetered
    }

    /// Returns the visible folder. Cancelling the task keeps what was received.
    @discardableResult
    public func run(_ build: ShelfBuild, progress: (@Sendable (ShelfProgress) -> Void)? = nil) async throws -> URL {
        let fm = FileManager.default
        let visible = store.visible(build)
        if fm.fileExists(atPath: visible.path) { return visible }
        let waiting = store.waiting(build)
        let tree = waiting.appendingPathComponent("tree", isDirectory: true)
        let parts = waiting.appendingPathComponent("parts", isDirectory: true)
        try checkNetwork()
        // What is already here, before asking the source anything.
        var kept: [Int: Int64] = [:]
        var received: Int64 = 0
        for (index, entry) in build.entries.enumerated() {
            if size(of: tree.appendingPathComponent(entry.path)) == entry.size { received += entry.size; continue }
            let part = parts.appendingPathComponent("\(index).part")
            let length = size(of: part) ?? 0
            if length > entry.size { try? fm.removeItem(at: part) }
            kept[index] = length > entry.size ? 0 : length
            received += kept[index]!
        }
        try checkSpace(build.bytes - received)
        let nodes = try await locate(build)
        do {
            for folder in [tree, parts] {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            try store.keepOutOfBackup(store.root.appendingPathComponent(".incoming"))
        } catch { throw Self.local(error) }
        progress?(.init(received: received, total: build.bytes))
        for (index, entry) in build.entries.enumerated() {
            guard var offset = kept[index], let node = nodes[entry.path] else { continue }
            let part = parts.appendingPathComponent("\(index).part"), chunk = parts.appendingPathComponent("\(index).chunk")
            while offset < entry.size {
                try Task.checkCancellation()
                try checkNetwork()
                try checkSpace(build.bytes - received)
                let range = offset..<min(offset + rules.chunk, entry.size)
                try await retry.run { [source] in
                    try? FileManager.default.removeItem(at: chunk)
                    try await source.fetch(node, range: range, to: chunk)
                }
                guard size(of: chunk) == Int64(range.count) else {
                    try? fm.removeItem(at: chunk)
                    throw ShelfError.wrongSize
                }
                do { try append(chunk, to: part) } catch { throw Self.local(error) }
                offset = range.upperBound
                received += Int64(range.count)
                progress?(.init(received: received, total: build.bytes))
            }
            try Task.checkCancellation()
            do {
                if entry.size == 0 { try Data().write(to: part) }
                guard try digest(part) == entry.sha256 else {
                    try fm.removeItem(at: part)
                    throw ShelfError.wrongDigest
                }
                let file = tree.appendingPathComponent(entry.path)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: file)
                try fm.moveItem(at: part, to: file)
            } catch { throw Self.local(error) }
        }
        do {
            guard build.entries.allSatisfy({ size(of: tree.appendingPathComponent($0.path)) == $0.size }) else { throw ShelfError.wrongSize }
            try fm.createDirectory(at: visible.deletingLastPathComponent(), withIntermediateDirectories: true)
            try store.keepOutOfBackup(visible.deletingLastPathComponent())
            try store.keepOutOfBackup(tree)
            // One rename on one volume: the build appears whole, or not at all.
            try fm.moveItem(at: tree, to: visible)
            try? fm.removeItem(at: waiting)
        } catch { throw Self.local(error) }
        return visible
    }

    /// Finds every file of the build, and refuses a tree that does not match its manifest before downloading a byte of it.
    private func locate(_ build: ShelfBuild) async throws -> [String: ShelfNode] {
        guard let root = build.folder else { throw ShelfError.filesMissing }
        let wanted = Dictionary(uniqueKeysWithValues: build.entries.map { ($0.path, $0) })
        var folders: Set<String> = [""]
        for entry in build.entries {
            let pieces = entry.path.components(separatedBy: "/").dropLast()
            for count in pieces.indices { folders.insert(pieces[...count].joined(separator: "/")) }
        }
        var found: [String: ShelfNode] = [:]
        var queue = [(id: root, path: "")], count = 0
        while !queue.isEmpty {
            let (id, path) = queue.removeFirst()
            let nodes = try await retry.run { [source] in try await source.children(of: id) }
            count += nodes.count
            guard count <= Self.maximumNodes else { throw ShelfError.badResponse }
            let names = Dictionary(grouping: nodes, by: { ShelfNames.folded($0.name) })
            for node in nodes {
                let full = path.isEmpty ? node.name : path + "/" + node.name
                let isWanted = wanted[full].map { $0.path.utf8.elementsEqual(full.utf8) } ?? false
                // Only the folders the manifest names are opened; anything else in there is left alone.
                guard isWanted || folders.contains(where: { $0.utf8.elementsEqual(full.utf8) }) else { continue }
                guard names[ShelfNames.folded(node.name)]?.count == 1 else { throw ShelfError.ambiguous }
                if isWanted {
                    guard node.kind == .file else { throw ShelfError.filesMissing }
                    guard node.size == wanted[full]!.size else { throw ShelfError.wrongSize }
                    if let sha256 = node.sha256, sha256 != wanted[full]!.sha256 { throw ShelfError.wrongDigest }
                    found[full] = node
                } else {
                    guard node.kind == .folder else { throw ShelfError.filesMissing }
                    queue.append((node.id, full))
                }
            }
        }
        guard found.count == wanted.count else { throw ShelfError.filesMissing }
        return found
    }

    private func checkNetwork() throws {
        if !rules.allowsMeteredNetwork, isMetered() { throw ShelfError.networkNotAllowed }
    }

    private func checkSpace(_ remaining: Int64) throws {
        // A chunk is held twice while it is added to its file.
        let needed = remaining + min(rules.chunk, remaining) + rules.reserve
        guard let free = store.available(store.root) else { return }
        guard free >= needed else { throw ShelfError.noSpace(needed: needed) }
    }

    /// Nil for anything that is not a plain file: a link is never followed.
    private func size(of url: URL) -> Int64? {
        guard let values = try? FileManager.default.attributesOfItem(atPath: url.path),
              values[.type] as? FileAttributeType == .typeRegular else { return nil }
        return (values[.size] as? NSNumber)?.int64Value
    }

    private func append(_ chunk: URL, to part: URL) throws {
        let fm = FileManager.default
        if size(of: part) == nil {
            try fm.moveItem(at: chunk, to: part)
        } else {
            let input = try FileHandle(forReadingFrom: chunk), output = try FileHandle(forWritingTo: part)
            defer { try? input.close() }
            let start = try output.seekToEnd()
            do {
                while let data = try input.read(upToCount: 1 << 20), !data.isEmpty { try output.write(contentsOf: data) }
                try output.synchronize()
                try output.close()
            } catch {
                // A half-added chunk would shift everything after it.
                try? output.truncate(atOffset: start)
                try? output.close()
                throw error
            }
            try fm.removeItem(at: chunk)
        }
    }

    private func digest(_ file: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var hasher = store.crypto.sha256()
        var isDone = false
        while !isDone {
            try Task.checkCancellation()
            // Foundation keeps each block alive until the pool drains; a build is gigabytes.
            #if canImport(ObjectiveC)
            try autoreleasepool { isDone = try Self.hash(input, into: &hasher) }
            #else
            isDone = try Self.hash(input, into: &hasher)
            #endif
        }
        return hasher.hex()
    }

    private static func hash(_ input: FileHandle, into hasher: inout any ShelfHasher) throws -> Bool {
        guard let data = try input.read(upToCount: 1 << 20), !data.isEmpty else { return true }
        hasher.update(data)
        return false
    }

    /// A full disk is told apart; a path never leaves the device in an error.
    private static func local(_ error: any Error) -> any Error {
        if error is ShelfError || error is CancellationError { return error }
        let cocoa = error as NSError
        let posix = (cocoa.userInfo[NSUnderlyingErrorKey] as? NSError) ?? cocoa
        if cocoa.code == CocoaError.Code.fileWriteOutOfSpace.rawValue || (posix.domain == NSPOSIXErrorDomain && posix.code == 28) {
            return ShelfError.noSpace(needed: 0)
        }
        return ShelfError.localFile
    }
}
