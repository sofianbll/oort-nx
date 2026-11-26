import AppKit
import NXLibraryCore
import ArcanePorting

/// Drives the Setup check: probes off the main thread, runs each card's action
/// with live progress, and fixes what it can by itself each time the screen
/// opens. The cards' states come from `SetupCheck`; an action in progress shows
/// over them until it ends (`SetupOverride`). AppViewModel owns one, so an
/// install keeps going while the screen is closed.
final class SetupCheckModel: ObservableObject {
    @Published private(set) var items: [SetupItem] = []
    @Published private(set) var installAllRunning = false
    @Published private(set) var installAllProgress: String?
    /// Cards that turned ready at the last probe, for the chip's pop.
    @Published private(set) var justReady: Set<SetupItemID> = []

    static let lastStatesKey = "NXLibrary_SetupLastStates"
    static let requirements = ToolchainRequirements.current

    private unowned let viewModel: AppViewModel
    private let runner = SystemCommandRunner()
    private let queue = DispatchQueue(label: L10n.text("nxlibrary.setup-check"), qos: .userInitiated)
    private var facts: SetupFacts?
    private var overrides: [SetupItemID: SetupOverride] = [:]
    private var timer: Timer?
    private var probing = false

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Checking

    private static func makeProbe(_ viewModel: AppViewModel, runner: CommandRunning, developerDir: URL) -> SetupProbe {
        SetupProbe(runner: runner, toolchain: viewModel.setup.engineToolchain,
                   developerDir: developerDir,
                   engineFolder: URL(fileURLWithPath: viewModel.setup.nxnativePath),
                   pinnedCommit: viewModel.pinnedEngineCommit,
                   certifiedMetal: viewModel.setup.requiredMetalVersion ?? requirements.fallbackMetal,
                   allowUntested: viewModel.setup.allowUntestedToolchain,
                   keyStore: viewModel.setup.keyStore, libraryFolder: viewModel.libraryFolder,
                   sourcesFolder: viewModel.porting.gameFilesFolder,
                   libraryNeedsConfirmation: viewModel.requiresGameAppsFolderChoice,
                   newestEngine: viewModel.setup.newestEngineChoice, engineRemote: viewModel.engineOverride?.remote)
    }

    func refresh() {
        guard !probing else { return }
        probing = true
        // Every recheck (4 s) asks xcode-select again, off the main thread; the probe reads the view model on main.
        queue.async { [weak self] in
            let developerDir = SetupModel.resolveDeveloperDir()
            DispatchQueue.main.async {
                guard let self else { return }
                let probe = Self.makeProbe(self.viewModel, runner: self.runner, developerDir: developerDir)
                self.queue.async { [weak self] in
                    let facts = probe.facts()
                    DispatchQueue.main.async {
                        self?.probing = false
                        self?.apply(facts)
                    }
                }
            }
        }
    }

    private func baseItems(from probed: SetupFacts) -> [SetupItem] {
        var facts = probed
        facts.keysError = viewModel.setup.keyImportError ?? facts.keysError
        return SetupCheck.items(from: facts)
    }

    private func apply(_ probed: SetupFacts) {
        facts = probed
        let base = baseItems(from: probed)
        // A card that is ready now ends what was waiting on it ("Finish in Installer",
        // an old failure); a running action keeps its chip until it reports back.
        for item in base where item.state == .ready && item.actionTitle == nil {
            if case .working? = overrides[item.id] { continue }
            overrides[item.id] = nil
        }
        let updated = SetupCheck.applying(overrides, to: base)
        let wasReady = Set(items.filter { $0.state == .ready }.map(\.id))
        let newlyReady = Set(updated.filter { $0.state == .ready }.map(\.id)).subtracting(wasReady)
        if !items.isEmpty, !newlyReady.isEmpty { SoundEffectService.shared.play(.focus) }
        justReady = items.isEmpty ? [] : newlyReady
        items = updated
    }

    func startRechecking() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopRechecking() {
        timer?.invalidate()
        timer = nil
    }

    func rememberStates() {
        var states = AppData.preferences.dictionary(forKey: Self.lastStatesKey) as? [String: String] ?? [:]
        for item in items where item.state != .working {
            states[item.id.rawValue] = item.state.rawValue
        }
        AppData.preferences.set(states, forKey: Self.lastStatesKey)
    }

    /// At launch, after setup: opens the Setup check when something that was ready
    /// broke or fell out of step with the engine; opening it starts the fix.
    static func checkAtLaunch(viewModel: AppViewModel) {
        guard viewModel.setupCompleted else { return }
        let enginePath = viewModel.setup.nxnativePath
        DispatchQueue.global(qos: .utility).async {
            // xcode-select runs here, not on the main thread at launch; the probe reads the view model on main.
            let developerDir = SetupModel.resolveDeveloperDir()
            let probe = DispatchQueue.main.sync { makeProbe(viewModel, runner: SystemCommandRunner(), developerDir: developerDir) }
            let current = SetupCheck.items(from: probe.facts())
            DispatchQueue.main.async {
                guard !viewModel.isBuilding, !viewModel.isUpdatingApp,
                      viewModel.setup.nxnativePath == enginePath else { return }
                let stored = AppData.preferences.dictionary(forKey: lastStatesKey) as? [String: String] ?? [:]
                var previous: [SetupItemID: SetupState] = [:]
                for (key, value) in stored {
                    if let id = SetupItemID(rawValue: key), let state = SetupState(rawValue: value) { previous[id] = state }
                }
                if SetupCheck.shouldReopen(previous: previous, current: current) {
                    viewModel.showSetupCheck = true
                } else {
                    AppData.preferences.set(
                        Dictionary(uniqueKeysWithValues: current.map { ($0.id.rawValue, $0.state.rawValue) }),
                        forKey: lastStatesKey)
                }
            }
        }
    }

    // MARK: - Actions

    /// What Install all runs, in card order.
    var missingAutomatic: [SetupItemID] {
        SetupCheck.automatic(items)
    }

    func activate(_ id: SetupItemID) {
        guard let item = items.first(where: { $0.id == id }), item.state != .working else { return }
        if case .failed? = overrides[id] { overrides[id] = nil }
        switch id {
        case .xcode:
            if item.state == .missing || (item.state == .needsYou && facts?.xcodeStatus != 69) {
                NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/id497799835")!)
            } else if item.state == .needsYou {
                let app = viewModel.setup.resolvedDeveloperDir().deletingLastPathComponent().deletingLastPathComponent()
                NSWorkspace.shared.open(app)
            }
        case .metal:
            guard item.actionTitle != nil || item.state == .needsYou else { return }
            perform(id) { _ in }
        case .engine:
            guard let facts, let action = item.actionTitle else { return }
            if case .checkout = facts.engine {
                let resolved = facts.engineFolder.resolvingSymlinksInPath()
                viewModel.confirmSetting(item.title, message: item.detail + "\n\n" +
                                         L10n.format("Engine folder: %@", [facts.engineFolder.path]),
                                         action: action, duringSetup: true) { [weak self] in
                    guard let self, self.facts?.engineFolder == facts.engineFolder, self.facts?.engine == facts.engine,
                          self.facts?.pinnedCommit == facts.pinnedCommit,
                          facts.engineFolder.resolvingSymlinksInPath() == resolved else { return }
                    self.fetchEngine(approvedCheckout: true) { _ in }
                }
            } else {
                perform(id) { _ in }
            }
        case .runtime:
            break
        case .keys:
            viewModel.setup.selectProdKeysFile { [weak self] in
                if let facts = self?.facts { self?.apply(facts) }
                self?.refresh()
            }
        case .library:
            viewModel.selectLibraryFolder(onPick: { [weak self] in self?.refresh() })
        case .sources:
            viewModel.porting.selectGameFolder(onPick: { [weak self] in self?.refresh() })
        }
    }

    func installAll() {
        let ids = missingAutomatic
        guard !ids.isEmpty, !installAllRunning else { return }
        installAllRunning = true
        step(ids, 0)
    }

    private func step(_ ids: [SetupItemID], _ index: Int) {
        guard index < ids.count else {
            installAllRunning = false
            installAllProgress = nil
            refresh()
            return
        }
        installAllProgress = "Installing \(index + 1) of \(ids.count)…"
        // Each action ends on its own card; a failure never stops the next one.
        perform(ids[index]) { [weak self] _ in self?.step(ids, index + 1) }
    }

    private func setOverride(_ id: SetupItemID, _ override: SetupOverride?) {
        overrides[id] = override
        if let facts { items = SetupCheck.applying(overrides, to: baseItems(from: facts)) }
    }

    /// From any thread: moves a working card's bar, skipping changes too small to see.
    private func report(_ id: SetupItemID, _ chip: String, _ progress: InstallProgress) {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .working(let oldChip, let old, _)? = self.overrides[id] else { return }
            if oldChip == chip, let old, let new = progress.fraction, abs(new - old) < 0.005 { return }
            self.setOverride(id, .working(chip, progress: progress.fraction ?? old, detail: progress.label))
        }
    }

    private func perform(_ id: SetupItemID, completion: @escaping (Bool) -> Void) {
        switch id {
        case .metal: installMetal(completion)
        case .engine: fetchEngine(completion)
        default: completion(false)
        }
    }

    private func finish(_ id: SetupItemID, _ result: CommandResult, _ name: String,
                        _ completion: @escaping (Bool) -> Void) {
        let output = [result.stdout, result.stderr].joined(separator: "\n")
        viewModel.logs.append(LogEntry(level: result.status == 0 ? .success : .error,
                                       message: "\(name): \(output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(2000))"))
        if result.status == 0 {
            setOverride(id, nil)
        } else {
            let last = output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).last.map(String.init) ?? "exit \(result.status)"
            setOverride(id, .failed(last))
        }
        refresh()
        completion(result.status == 0)
    }

    private var environment: [String: String] {
        viewModel.setup.engineToolchain.environment(base: ProcessInfo.processInfo.environment,
                                              developerDir: viewModel.setup.resolvedDeveloperDir())
    }

    private func stream(_ executable: String, _ arguments: [String], env: [String: String],
                        onLine: @escaping @Sendable (String) -> Void) -> CommandResult {
        (try? runner.stream(URL(fileURLWithPath: executable), arguments, environment: env,
                            currentDirectory: nil, onLine: onLine))
            ?? CommandResult(status: -1, stdout: "", stderr: "\(executable) could not start")
    }

    /// The certified compiler first, by Apple's asset build; with no Metal at all
    /// and no certified asset on offer, whatever matches this Xcode. Nothing is deleted.
    private func installMetal(_ completion: @escaping (Bool) -> Void) {
        guard let facts else { completion(false); return }
        let certified = facts.certifiedMetal
        let hadMetal = facts.metalVersion != nil
        let allowUntested = facts.allowUntested
        let pinned = Self.requirements.metalDownload(for: certified)
        let chip = L10n.text("DOWNLOADING…")
        setOverride(.metal, .working(chip, detail: L10n.format("Asking Apple for Metal %@…", [String(describing: certified)])))
        let env = environment
        queue.async { [weak self] in
            guard let self else { return }
            let onLine: @Sendable (String) -> Void = { line in
                if let fraction = InstallProgress.percent(line) {
                    self.report(.metal, chip, InstallProgress(fraction: fraction, label: line.trimmingCharacters(in: .whitespaces)))
                }
            }
            var result = pinned.map { self.stream("/usr/bin/xcodebuild", $0, env: env, onLine: onLine) }
            if result?.status != 0, !hadMetal {
                result = self.stream("/usr/bin/xcodebuild", ToolchainRequirements.anyMetalDownload, env: env, onLine: onLine)
            }
            var final = result ?? CommandResult(status: 1, stdout: "", stderr: "Apple offers no Metal \(certified) for this Xcode.")
            if final.status == 0, !allowUntested {
                let now = (try? self.runner.run(URL(fileURLWithPath: "/usr/bin/xcrun"), ["metal", "--version"],
                                                environment: env, currentDirectory: nil))
                    .flatMap { MetalVersion.parse($0.stdout) }
                if let now, now != certified {
                    final = CommandResult(status: 1, stdout: final.stdout,
                                          stderr: "This Xcode uses Metal \(now); builds wait for an update to \(AppIdentity.displayName) tested with it.")
                }
            }
            DispatchQueue.main.async {
                self.viewModel.setup.detectEnvironment()
                self.finish(.metal, final, "Metal compiler", completion)
            }
        }
    }

    private func fetchEngine(approvedCheckout: Bool = false, _ completion: @escaping (Bool) -> Void) {
        guard let facts, viewModel.setup.canMutateEngine,
              facts.engineFolder.path == viewModel.setup.nxnativePath else { completion(false); return }
        if case .checkout = facts.engine, !approvedCheckout { completion(false); return }
        if case .checkout(let head, false) = facts.engine, head == facts.newestEngine?.commit {
            guard viewModel.setup.canSwitchEngine else { completion(false); return }
            backToTestedEngine(completion)
            return
        }
        let action = SetupActions.engineAction(for: facts.engine, pinned: facts.pinnedCommit,
                                               newest: facts.newestEngine?.commit)
        let commands = SetupActions.gitCommands(for: action, folder: facts.engineFolder, pinned: facts.pinnedCommit,
                                               remote: facts.engineRemote)
        guard !commands.isEmpty else { completion(false); return }
        let probe = Self.makeProbe(viewModel, runner: runner, developerDir: viewModel.setup.resolvedDeveloperDir())
        viewModel.setup.isSwitchingEngine = true
        let chip = action == .clone ? L10n.text("CLONING…") : L10n.text("UPDATING…")
        setOverride(.engine, .working(chip, progress: 0, detail: L10n.text("Connecting to GitHub…")))
        let env = environment
        queue.async { [weak self] in
            guard let self else { return }
            guard probe.checkoutFacts() == facts.engine else {
                DispatchQueue.main.async {
                    self.viewModel.setup.isSwitchingEngine = false
                    self.setOverride(.engine, nil)
                    self.refresh()
                    completion(false)
                }
                return
            }
            var result = CommandResult(status: 0, stdout: "", stderr: "")
            for command in commands {
                result = self.stream("/usr/bin/git", command, env: env) { line in
                    if let progress = InstallProgress.git(line) { self.report(.engine, chip, progress) }
                }
                if result.status != 0 { break }
            }
            DispatchQueue.main.async {
                self.viewModel.setup.isSwitchingEngine = false
                self.viewModel.setup.detectEnvironment()
                self.finish(.engine, result, "nxnative engine", completion)
            }
        }
    }

    /// The newest engine's card: A returns to the tested engine, the same action as Settings → Setup and engine.
    private func backToTestedEngine(_ completion: @escaping (Bool) -> Void) {
        setOverride(.engine, .working(L10n.text("SWITCHING…"), detail: L10n.text("Returning to the tested engine…")))
        viewModel.setup.useTestedEngine()
        waitForEngineSwitch(completion)
    }

    private func waitForEngineSwitch(_ completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if self.viewModel.setup.isSwitchingEngine { self.waitForEngineSwitch(completion); return }
            if let problem = self.viewModel.setup.newestEngineProblem {
                self.setOverride(.engine, .failed(problem))
                completion(false)
            } else {
                self.setOverride(.engine, nil)
                self.refresh()
                completion(true)
            }
        }
    }
}
