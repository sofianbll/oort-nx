import Darwin
import Foundation
import NXLibraryCore

public struct PlayersLaunchStatus: Equatable, Sendable {
    public enum PlanState: Equatable, Sendable { case absent, unreadable, active }
    public enum Omission: Equatable, Sendable {
        case unsupportedEngine, environmentFileUnreadable, environmentFile, gameOption
        case networkMode(PlayerLaunchNetworkMode), missingProfile, lockedProfile, invalidNickname
    }

    public let plan: PlanState
    public let controllerMode: Omission?
    public let nickname: Omission?
}

public struct PlayersLaunch: Sendable {
    static let controllerKeys: Set<String> = [PlayerLaunchEnvironment.pressToJoinKey, PlayerLaunchEnvironment.mergeKey]
    private static let nicknameKey = PlayerLaunchEnvironment.nicknameKey
    private static let keys = controllerKeys.union([nicknameKey])

    public let status: PlayersLaunchStatus
    let additions: [String: String]

    private init(plan: PlayersLaunchStatus.PlanState, controllerMode: PlayersLaunchStatus.Omission? = nil,
                 nickname: PlayersLaunchStatus.Omission? = nil, additions: [String: String] = [:]) {
        status = .init(plan: plan, controllerMode: controllerMode, nickname: nickname)
        self.additions = additions
    }

    public static func prepare(library: PlayerPlanLibrary, app: URL, titleID: String, explicit: [String: String],
                               profiles: [LocalProfile]) async -> Self {
        let snapshot: (plan: PlayerPlan?, unlocked: Set<UUID>)
        do { snapshot = try await library.launchPlan(profiles: profiles) }
        catch { return .init(plan: .unreadable) }
        guard let plan = snapshot.plan else { return .init(plan: .absent) }
        let environment = NSWorkspaceLauncher.gameEnvironment(
            inheriting: ProcessInfo.processInfo.environment, explicit: explicit, suppressInheritedPlayerMode: true)
        // Use the child's HOME; nxnative derives the per-title env.txt from it, not from the save path.
        let home = environment["HOME"] ?? ""
        guard home.hasPrefix("/") else { return unreadableEnvironment(for: plan) }
        return evaluate(plan: plan, app: app, titleID: titleID,
                        home: URL(fileURLWithPath: home, isDirectory: true), environment: environment,
                        profiles: profiles, unlocked: snapshot.unlocked)
    }

    static func evaluate(plan: PlayerPlan, app: URL, titleID: String, home: URL, environment: [String: String],
                         savedChoices: SavedChoicesStore = SystemSavedChoices(),
                         profiles: [LocalProfile] = [], unlocked: Set<UUID> = []) -> Self {
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
        let optionKeys = Set(keys.filter { environment[$0] != nil || saved($0) != nil })
        let networkKey = NextendoLaunch.networkKey
        let network = networkMode(environment[networkKey] ?? fileValues[networkKey] ?? saved(networkKey))
        let capabilities = capabilities(in: app)
        let additions = PlayerLaunchEnvironment.values(
            plan: plan, capabilities: capabilities, networkMode: network,
            envFileKeys: fileKeys.union(optionKeys), profiles: profiles, unlockedProfileIDs: unlocked)

        let controller: PlayersLaunchStatus.Omission?
        if !fileKeys.isDisjoint(with: controllerKeys) { controller = .environmentFile }
        else if !optionKeys.isDisjoint(with: controllerKeys) { controller = .gameOption }
        else if (plan.mode == .merge && !capabilities.merge) || (plan.mode == .pressToJoin && !capabilities.pressToJoin) {
            controller = .unsupportedEngine
        } else { controller = nil }

        let nickname: PlayersLaunchStatus.Omission?
        switch access {
        case nil, .guest: nickname = nil
        case .missing: nickname = .missingProfile
        case .locked: nickname = .lockedProfile
        case .ready:
            if fileKeys.contains(nicknameKey) { nickname = .environmentFile }
            else if optionKeys.contains(nicknameKey) { nickname = .gameOption }
            else if !capabilities.nickname { nickname = .unsupportedEngine }
            else if network != .offline && network != .local { nickname = .networkMode(network) }
            else { nickname = additions[nicknameKey] == nil ? .invalidNickname : nil }
        }
        return .init(plan: .active, controllerMode: controller, nickname: nickname, additions: additions)
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
