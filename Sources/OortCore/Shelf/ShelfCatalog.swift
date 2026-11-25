import Foundation

public struct ShelfGame: Equatable, Sendable {
    public enum State: String, Sendable { case available, installed, update }

    public let build: ShelfBuild
    public let state: State

    public var titleID: String { build.titleID }
    public var name: String { build.name }
}

/// A game of the library that this device does not show, and why.
public struct ShelfHidden: Equatable, Sendable {
    public enum Reason: String, Sendable { case notPrepared, system, graphics, launcher, filesMissing }

    public let titleID: String
    public let name: String
    public let reason: Reason
}

public struct ShelfProblem: Equatable, Sendable {
    public let titleID: String
    public let error: ShelfError
}

public struct ShelfListing: Equatable, Sendable {
    public let games: [ShelfGame]
    public let hidden: [ShelfHidden]
    public let problems: [ShelfProblem]
}

public enum ShelfOrder: String, CaseIterable, Sendable {
    case name, newest, size
}

/// Reads a library folder the way the Mac lays it out, and keeps what runs on this device.
public struct ShelfCatalog: Sendable {
    public static let maximumGames = 2_000
    /// How many older builds are looked at when the newest does not run here.
    static let olderBuilds = 8
    static let signatureLimit: Int64 = 512

    let source: any ShelfSource
    let crypto: ShelfCrypto
    let retry: ShelfRetry
    let scratch: URL

    public init(source: any ShelfSource, crypto: ShelfCrypto, retry: ShelfRetry = .standard, scratch: URL) {
        self.source = source
        self.crypto = crypto
        self.retry = retry
        self.scratch = scratch
    }

    /// One damaged game is a problem of that game; a source that cannot answer stops the whole list. `installed` maps a title to its digest.
    public func list(for device: ShelfDevice, installed: [String: String] = [:], order: ShelfOrder = .name) async throws -> ShelfListing {
        let root = try await children(source.root)
        let names = Dictionary(grouping: root, by: { ShelfNames.folded($0.name) })
        var folders: [String: [ShelfNode]] = [:]
        for node in root where node.kind == .folder {
            if let title = ShelfNames.titleID(inFolder: node.name) { folders[title, default: []].append(node) }
        }
        guard folders.count <= Self.maximumGames else { throw ShelfError.badResponse }
        var games: [ShelfGame] = [], hidden: [ShelfHidden] = [], problems: [ShelfProblem] = []
        for (title, nodes) in folders.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            do {
                guard nodes.allSatisfy({ names[ShelfNames.folded($0.name)]?.count == 1 }) else { throw ShelfError.ambiguous }
                let found = try await best(title, in: nodes, for: device) { problems.append(.init(titleID: title, error: $0)) }
                switch found {
                case .build(let build):
                    let state: ShelfGame.State = installed[title].map { $0 == build.digest ? .installed : .update } ?? .available
                    games.append(.init(build: build, state: state))
                case .hidden(let reason, let name):
                    let label = name ?? ShelfNames.displayName((nodes.first { $0.name != title } ?? nodes[0]).name, titleID: title)
                    hidden.append(.init(titleID: title, name: label, reason: reason))
                case .nothing: break
                }
            } catch let error as ShelfError where Self.isAboutOneGame(error) {
                problems.append(.init(titleID: title, error: error))
            }
        }
        return .init(games: Self.sorted(games, by: order), hidden: hidden, problems: problems)
    }

    /// The Mac's newest app of a game, across its snapshots: an app kept from an older snapshot keeps its own date.
    public func macBuild(of titleID: String) async throws -> ShelfMacBuild? {
        var found: [(name: (stamp: Int64, sha256: String), node: ShelfNode)] = []
        for folder in try await children(source.root) where folder.kind == .folder && ShelfNames.titleID(inFolder: folder.name) == titleID {
            guard let manifests = try ShelfNode.only("manifests", kind: .folder, in: await children(folder.id)) else { continue }
            for node in try await children(manifests.id) where node.kind == .file {
                if let name = ShelfNames.manifestName(node.name) { found.append((name, node)) }
            }
        }
        var best: ShelfMacBuild?
        for item in found.sorted(by: { ($0.name.stamp, $0.name.sha256) > ($1.name.stamp, $1.name.sha256) }) {
            if let best, best.stamp >= item.name.stamp { break }
            let data = try await read(item.node, limit: ShelfMacBuild.manifestLimit)
            if let build = try ShelfMacBuild.read(data, name: item.name, titleID: titleID, crypto: crypto),
               build.stamp > best?.stamp ?? 0 { best = build }
        }
        return best
    }

    private enum Found { case build(ShelfBuild), hidden(ShelfHidden.Reason, name: String?), nothing }

    private func best(_ title: String, in folders: [ShelfNode], for device: ShelfDevice, problem: (ShelfError) -> Void) async throws -> Found {
        var isOnMac = false, isElsewhere = false
        var candidates: [(name: (stamp: Int64, sha256: String), node: ShelfNode, siblings: [ShelfNode])] = []
        for folder in folders {
            let inside = try await children(folder.id)
            isOnMac = try isOnMac || ShelfNode.only("manifests", kind: .folder, in: inside) != nil
            guard let targets = try ShelfNode.only("targets", kind: .folder, in: inside) else { continue }
            let platforms = try await children(targets.id)
            isElsewhere = isElsewhere || ShelfPlatform.allCases.contains { platform in platforms.contains { $0.name == platform.rawValue } }
            guard let own = try ShelfNode.only(device.platform.rawValue, kind: .folder, in: platforms) else { continue }
            let siblings = try await children(own.id)
            for node in siblings where node.kind == .file {
                if let name = ShelfNames.manifestName(node.name) { candidates.append((name, node, siblings)) }
            }
        }
        candidates.sort { ($0.name.stamp, $0.name.sha256) > ($1.name.stamp, $1.name.sha256) }
        var refusal: (ShelfHidden.Reason, String)?
        for candidate in candidates.prefix(Self.olderBuilds) {
            try Task.checkCancellation()
            do {
                var build = try await build(candidate.node, name: candidate.name, siblings: candidate.siblings, title: title, device: device)
                if let reason = device.refusal(of: build) {
                    refusal = refusal ?? (reason, build.name)
                    continue
                }
                guard let folder = try ShelfNode.only(build.digest, kind: .folder, in: candidate.siblings) else {
                    refusal = refusal ?? (.filesMissing, build.name)
                    continue
                }
                build.folder = folder.id
                return .build(build)
            } catch let error as ShelfError where Self.isAboutOneGame(error) {
                problem(error)
            }
        }
        if let refusal { return .hidden(refusal.0, name: refusal.1) }
        return candidates.isEmpty && (isOnMac || isElsewhere) ? .hidden(.notPrepared, name: nil) : .nothing
    }

    private func build(_ node: ShelfNode, name: (stamp: Int64, sha256: String), siblings: [ShelfNode], title: String,
                       device: ShelfDevice) async throws -> ShelfBuild {
        guard siblings.filter({ ShelfNames.folded($0.name) == ShelfNames.folded(node.name) }).count == 1 else { throw ShelfError.ambiguous }
        guard let seal = try ShelfNode.only(String(node.name.dropLast(5)) + ".sig", kind: .file, in: siblings),
              let length = seal.size, (1...Self.signatureLimit).contains(length) else { throw ShelfError.unsigned }
        let data = try await read(node, limit: ShelfBuild.manifestLimit)
        let signature = try await read(seal, limit: Self.signatureLimit)
        return try ShelfBuild.read(data, signature: signature, stamp: name.stamp, sha256: name.sha256, titleID: title,
                                   platform: device.platform, crypto: crypto)
    }

    private func children(_ folder: String) async throws -> [ShelfNode] {
        try await retry.run { [source] in try await source.children(of: folder) }
    }

    private func read(_ node: ShelfNode, limit: Int64) async throws -> Data {
        guard let size = node.size, (1...limit).contains(size) else { throw ShelfError.invalidManifest }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let file = scratch.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try await retry.run { [source] in
            try? FileManager.default.removeItem(at: file)
            try await source.fetch(node, range: 0..<size, to: file)
        }
        let data = try Data(contentsOf: file)
        guard Int64(data.count) == size else { throw ShelfError.wrongSize }
        return data
    }

    static func isAboutOneGame(_ error: ShelfError) -> Bool {
        switch error {
        case .ambiguous, .unsafeName, .invalidManifest, .unsigned, .filesMissing, .wrongSize, .wrongDigest, .notFound: true
        default: false
        }
    }

    static func sorted(_ games: [ShelfGame], by order: ShelfOrder) -> [ShelfGame] {
        func key(_ game: ShelfGame) -> String {
            // Accents and case do not count; no language rule, so both phones agree.
            String(String.UnicodeScalarView(game.name.decomposedStringWithCanonicalMapping.unicodeScalars
                .filter { $0.properties.generalCategory != .nonspacingMark })).lowercased()
        }
        func byName(_ a: ShelfGame, _ b: ShelfGame) -> Bool {
            let left = Array(key(a).utf8), right = Array(key(b).utf8)
            return left == right ? a.titleID < b.titleID : left.lexicographicallyPrecedes(right)
        }
        return games.sorted { a, b in
            switch order {
            case .newest where a.build.stamp != b.build.stamp: a.build.stamp > b.build.stamp
            case .size where a.build.bytes != b.build.bytes: a.build.bytes > b.build.bytes
            default: byName(a, b)
            }
        }
    }
}
