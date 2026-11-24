import Darwin
import Foundation
import NXLibraryCore

public struct PlayersLaunchStatus: Equatable, Sendable {
    public enum PlanState: Equatable, Sendable { case absent, unreadable, active }
    public enum Omission: Equatable, Sendable {
        case unsupportedEngine, environmentFileUnreadable, environmentFile, gameOption
        case networkMode(PlayerLaunchNetworkMode), missingProfile, lockedProfile, invalidNickname
        case mergeMode, disconnectedController, unconfirmedController, controllerIdentityUnavailable
        case incompatibleKeyboardSlot, invalidMergePlayer, invalidPortrait, portraitExportFailed
    }

    public let plan: PlanState
    public let controllerMode: Omission?
    public let nickname: Omission?
    public let controllerOrder: [Int: Omission]
    public let profileNames: [Int: Omission]
    public let portraits: [Int: Omission]

    init(plan: PlanState, controllerMode: Omission?, nickname: Omission?,
         controllerOrder: [Int: Omission] = [:], profileNames: [Int: Omission] = [:],
         portraits: [Int: Omission] = [:]) {
        self.plan = plan
        self.controllerMode = controllerMode
        self.nickname = nickname
        self.controllerOrder = controllerOrder
        self.profileNames = profileNames
        self.portraits = portraits
    }
}

public struct PlayersLaunch: Sendable {
    static let controllerKeys: Set<String> = [PlayerLaunchEnvironment.pressToJoinKey, PlayerLaunchEnvironment.mergeKey]
    private static let nicknameKey = PlayerLaunchEnvironment.nicknameKey
    static let orderKey = "DM_PAD_ORDER"
    static func nameKey(_ slot: Int) -> String { "DM_USER_\(slot)_NAME" }
    static func imageKey(_ slot: Int) -> String { "DM_USER_\(slot)_IMAGE" }

    struct EngineFeatures: Equatable {
        var order = false
        var extendedMerge = false
        var names = false
        var images = false

        static let macFix = "4e48725b0785210ea51186a446c344a3fee04265"
        static let orderCommit = "4c5e76d212a512a7524b6183ba578b18f4c0aece"
        static let mergeCommit = "c77f82a732036858748990f8d048855673a7c3e0"
        static let namesCommit = "3b67ef1f03023507ecf6174add942a4f1f94942b"
        static let imagesCommit = "22143d4e80b29347d056a0868bfec520938ca1c9"

        static func installed(in app: URL, ancestry: EngineAncestry?) async -> Self {
            guard let ancestry, let commit = CheatLocator.engineCommit(appURL: app, recorded: nil),
                  commit.utf8.allSatisfy("0123456789abcdefABCDEF".utf8.contains),
                  FileManager.default.isReadableFile(atPath: HomeMenu.hostExecutable(in: app).path)
            else { return .init() }
            func contains(_ feature: String) async -> Bool {
                await ancestry.answer(feature, in: commit) == true
            }
            let fixed = await contains(macFix)
            let order = fixed ? await contains(orderCommit) : false
            let merge = fixed ? await contains(mergeCommit) : false
            let names = await contains(namesCommit)
            let images = await contains(imagesCommit)
            return .init(order: order, extendedMerge: merge, names: names, images: images)
        }
    }

    public let status: PlayersLaunchStatus
    let additions: [String: String]

    private init(plan: PlayersLaunchStatus.PlanState, controllerMode: PlayersLaunchStatus.Omission? = nil,
                 nickname: PlayersLaunchStatus.Omission? = nil, additions: [String: String] = [:],
                 controllerOrder: [Int: PlayersLaunchStatus.Omission] = [:],
                 profileNames: [Int: PlayersLaunchStatus.Omission] = [:],
                 portraits: [Int: PlayersLaunchStatus.Omission] = [:]) {
        status = .init(plan: plan, controllerMode: controllerMode, nickname: nickname,
                       controllerOrder: controllerOrder, profileNames: profileNames, portraits: portraits)
        self.additions = additions
    }

    public static func prepare(library: PlayerPlanLibrary, app: URL, titleID: String, explicit: [String: String],
                               profiles: [LocalProfile], ancestry: EngineAncestry? = nil, mergePlayer: Int = 1) async -> Self {
        let snapshot: (plan: PlayerPlan?, unlocked: Set<UUID>)
        do { snapshot = try await library.launchPlan(profiles: profiles) }
        catch { return .init(plan: .unreadable) }
        guard let plan = snapshot.plan else { return .init(plan: .absent) }
        let environment = NSWorkspaceLauncher.gameEnvironment(
            inheriting: ProcessInfo.processInfo.environment, explicit: explicit, suppressInheritedPlayerMode: true)
        // Use the child's HOME; nxnative derives the per-title env.txt from it, not from the save path.
        let home = environment["HOME"] ?? ""
        guard home.hasPrefix("/") else { return unreadableEnvironment(for: plan) }
        let features = await EngineFeatures.installed(in: app, ancestry: ancestry)
        return evaluate(plan: plan, app: app, titleID: titleID,
                        home: URL(fileURLWithPath: home, isDirectory: true), environment: environment,
                        profiles: profiles, unlocked: snapshot.unlocked, features: features, mergePlayer: mergePlayer)
    }

    static func evaluate(plan: PlayerPlan, app: URL, titleID: String, home: URL, environment: [String: String],
                         savedChoices: SavedChoicesStore = SystemSavedChoices(),
                         profiles: [LocalProfile] = [], unlocked: Set<UUID> = [],
                         features: EngineFeatures = .init(), mergePlayer: Int = 1) -> Self {
        let access = plan.slot(1)?.profileAccess(in: profiles, unlockedProfileIDs: unlocked)
        let info = ImportService.info(at: app)
        let installedTitle = (info?["DMTitleID"] as? String) ?? titleID
        let fileValues: [String: String]
        do {
            let hex = "0123456789abcdefABCDEF".utf8
            guard installedTitle.utf8.count == 16, installedTitle.utf8.allSatisfy(hex.contains) else {
                return unreadableEnvironment(for: plan)
            }
            let title = home.appendingPathComponent("Library/Application Support/nxnative")
                .appendingPathComponent(installedTitle).appendingPathComponent("env.txt")
            let bundled = app.appendingPathComponent("Contents/Resources/dm/env.txt")
            fileValues = try readEnv(title).merging(readEnv(bundled)) { title, _ in title }
        } catch {
            return unreadableEnvironment(for: plan)
        }

        let rules = (info?["DMSettings"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        func saved(_ key: String) -> String? {
            guard (environment["DM_SAVED_CHOICES"] ?? fileValues["DM_SAVED_CHOICES"]) != "0",
                  let domain = info?["CFBundleIdentifier"] as? String, !domain.isEmpty,
                  let rule = rules.first(where: { $0["env"] as? String == key }),
                  let value = savedChoices.value(key, domain: domain), value.utf8.count < 256,
                  !value.utf8.contains(0) else { return nil }
            if let values = rule["values"] as? [Any] {
                return values.contains { ($0 as? String) == value } ? value : nil
            }
            guard let min = rule["min"] as? Double, let max = rule["max"] as? Double,
                  let number = LauncherSetting.number(value), number >= min, number <= max else { return nil }
            return value
        }
        let fileKeys = Set(fileValues.keys)
        func blocked(_ key: String) -> PlayersLaunchStatus.Omission? {
            if fileKeys.contains(key) { return .environmentFile }
            if environment[key] != nil || saved(key) != nil { return .gameOption }
            return nil
        }
        let existing = Set(controllerKeys.union([nicknameKey]).filter { blocked($0) != nil })
        let networkKey = NextendoLaunch.networkKey
        let network = networkMode(environment[networkKey] ?? fileValues[networkKey] ?? saved(networkKey))
        let capabilities = capabilities(in: app)
        var additions = PlayerLaunchEnvironment.values(
            plan: plan, capabilities: capabilities, networkMode: network,
            envFileKeys: existing, profiles: profiles, unlockedProfileIDs: unlocked)

        let controller: PlayersLaunchStatus.Omission?
        if !fileKeys.isDisjoint(with: controllerKeys) { controller = .environmentFile }
        else if !existing.isDisjoint(with: controllerKeys) { controller = .gameOption }
        else if plan.mode == .merge, !(1...PlayerPlan.maximumPlayers).contains(mergePlayer) {
            controller = .invalidMergePlayer
        } else if plan.mode == .merge && mergePlayer != 1 && !features.extendedMerge {
            controller = .unsupportedEngine
        } else if plan.mode == .merge && features.order,
                  let reason = blocked(orderKey) {
            controller = reason
        } else if (plan.mode == .merge && !capabilities.merge && !features.extendedMerge) ||
                    (plan.mode == .pressToJoin && !capabilities.pressToJoin) {
            controller = .unsupportedEngine
        } else { controller = nil }
        if plan.mode == .merge {
            let legacyFallback = mergePlayer != 1 && controller == .unsupportedEngine && capabilities.merge && !features.extendedMerge
            // Preserve the existing P1 fallback on engines that only support legacy merge.
            if !legacyFallback {
                additions[PlayerLaunchEnvironment.mergeKey] = controller == nil ? String(mergePlayer) : nil
            }
        }

        let nickname: PlayersLaunchStatus.Omission?
        switch access {
        case nil, .guest: nickname = nil
        case .missing: nickname = .missingProfile
        case .locked: nickname = .lockedProfile
        case .ready:
            if let reason = blocked(nicknameKey) { nickname = reason }
            else if !capabilities.nickname { nickname = .unsupportedEngine }
            else if network != .offline && network != .local { nickname = .networkMode(network) }
            else { nickname = additions[nicknameKey] == nil ? .invalidNickname : nil }
        }
        var names: [Int: PlayersLaunchStatus.Omission] = [:]
        for (number, slot) in plan.slots where number != 1 && slot.profileID != nil {
            switch slot.profileAccess(in: profiles, unlockedProfileIDs: unlocked) {
            case .missing: names[number] = .missingProfile
            case .locked: names[number] = .lockedProfile
            case let .ready(profile):
                let key = nameKey(number)
                if let reason = blocked(key) { names[number] = reason }
                else if !features.names { names[number] = .unsupportedEngine }
                else if network != .offline && network != .local { names[number] = .networkMode(network) }
                else if let name = localName(profile.name) { additions[key] = name }
                else { names[number] = .invalidNickname }
            case .guest: break
            }
        }
        return .init(plan: .active, controllerMode: controller, nickname: nickname, additions: additions,
                     profileNames: names)
    }

    private static func localName(_ value: String) -> String? {
        guard !value.utf8.contains(0) else { return nil }
        var bytes = 0
        let name = value.unicodeScalars.prefix { scalar in
            bytes += scalar.utf8.count
            return bytes <= 32
        }
        return name.isEmpty ? nil : String(name)
    }

    private static func unreadableEnvironment(for plan: PlayerPlan) -> Self {
        .init(plan: .active, controllerMode: .environmentFileUnreadable,
              nickname: plan.slot(1)?.profileID == nil ? nil : .environmentFileUnreadable)
    }

    private static func networkMode(_ value: String?) -> PlayerLaunchNetworkMode {
        switch value {
        case "offline": return .offline
        case "ldn", "lan": return .local
        case "nextendo": return .nextendo
        default: return .automatic
        }
    }

    private static func capabilities(in app: URL) -> PlayerLaunchCapabilities {
        guard let host = try? Data(contentsOf: HomeMenu.hostExecutable(in: app), options: [.mappedIfSafe]) else {
            return .init()
        }
        func supports(_ key: String) -> Bool {
            host.range(of: Data("\0\(key)\0".utf8)) != nil || host.starts(with: Data("\(key)\0".utf8))
        }
        return .init(pressToJoin: supports(PlayerLaunchEnvironment.pressToJoinKey),
                     merge: supports(PlayerLaunchEnvironment.mergeKey), nickname: supports(nicknameKey))
    }

    private static func readEnv(_ url: URL) throws -> [String: String] {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        if fd == -1, errno == ENOENT { return [:] }
        guard fd >= 0 else { throw CocoaError(.fileReadUnknown) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        let limit = 1_048_576
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= limit else {
            // shortcut: ignore the plan for unusual files rather than guessing at nxnative's input.
            throw CocoaError(.fileReadCorruptFile)
        }
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count == info.st_size, String(data: data, encoding: .utf8) != nil, !data.contains(0) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let spaces = CharacterSet(charactersIn: " \t")
        var values: [String: String] = [:]
        for bytes in data.split(separator: 10) {
            guard bytes.count < 4095 else { throw CocoaError(.fileReadCorruptFile) }
            let line = bytes.drop(while: { $0 == 32 || $0 == 9 })
            guard line.first != 35, let equals = line.firstIndex(of: 61), equals != line.startIndex else { continue }
            let key = String(decoding: line[..<equals], as: UTF8.self).trimmingCharacters(in: spaces)
            let value = line[(equals + 1)...]
            let end = value.lastIndex(where: { $0 != 32 && $0 != 9 && $0 != 13 }).map { $0 + 1 } ?? value.startIndex
            if values[key] == nil { values[key] = String(decoding: value[..<end], as: UTF8.self) }
        }
        return values
    }
}
