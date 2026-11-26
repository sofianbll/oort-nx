import AppKit
import Foundation
import NXLibraryCore
import ArcanePorting

/// The Switch Setup's state: the engine (folder, commit, upstream, newest engine), the keys, the environment check
/// and the Metal gate. The screens that show any of it observe it on their own: Settings, Add Game, Game options, the
/// home, the game page and the shell's update offer. It reaches the rest of Arcane only through `app`, the list of
/// what the Porting module will ask of the base.
final class SetupModel: ObservableObject {
    /// The coordinator: library, building state, alerts and the tested pin.
    unowned let app: AppViewModel

    // MARK: - Engine
    @Published var nxnativePath: String = "" {
        didSet {
            if oldValue != nxnativePath { app.refreshInstalledEngineVersions(reset: true) }
        }
    }
    @Published var isNxnativeValid: Bool = false
    @Published var currentEngineCommit: String? = nil
    @Published var upstreamState: UpstreamCheckState = .idle
    /// The newest nxnative the player chose in Settings → Setup and engine; nil while the tested engine is in use.
    @Published var newestEngineChoice: NewestEngineChoice? = nil {
        didSet {
            if let choice = newestEngineChoice, let data = try? JSONEncoder().encode(choice) {
                AppData.preferences.set(data, forKey: AppViewModel.StorageKeys.newestEngineChoice)
            } else {
                AppData.preferences.removeObject(forKey: AppViewModel.StorageKeys.newestEngineChoice)
            }
            if oldValue?.commit != newestEngineChoice?.commit { app.refreshInstalledEngineVersions(reset: true) }
        }
    }
    /// Whether upstream main can be used here, read from its lock after an Upstream check.
    @Published var newestEngineReadiness: NewestEngineReadiness? = nil
    @Published var isSwitchingEngine = false
    /// Why the last switch did not happen, shown calmly in the Newest engine row.
    @Published var newestEngineProblem: String? = nil

    /// What the engine in use can read: title selection, extracted folders and NUP containers or programs.
    var engineSourceCapabilities: EngineSourceCapabilities {
        EngineSourceCapabilities(repo: URL(fileURLWithPath: nxnativePath))
    }

    // MARK: - Keys
    @Published var localKeyStatus: LocalKeyStatus = .required
    var isProdKeysValid: Bool { keyGenerationCount != nil }
    var keyGenerationCount: Int? {
        if case .available(let count) = localKeyStatus { return count }
        return nil
    }
    private(set) var keyImportError: String?
    lazy var keyStore = KeyStore(directory: app.core.appendingPathComponent("keys"))

    // MARK: - Environment and the Metal gate
    @Published var environmentStatus: EnvironmentStatus? = nil
    @Published var compatibilityReport: CompatibilityReport? = nil
    @Published var isCheckingEnvironment = false
    var environmentCheckGeneration = UUID()
    var legacyToolchainOverride: Bool {
        AppData.preferences.bool(forKey: AppViewModel.StorageKeys.allowUntestedToolchain)
    }
    var allowUntestedToolchain: Bool {
        usesNewestEngine || (app.settingsStore?.settings.toolchainOverride ?? legacyToolchainOverride)
    }

    init(app: AppViewModel) {
        self.app = app
        if let data = AppData.preferences.data(forKey: AppViewModel.StorageKeys.newestEngineChoice) {
            // Restoring through the setter would refresh versions via app.setup while it is still being initialized.
            _newestEngineChoice = Published(initialValue: try? JSONDecoder().decode(NewestEngineChoice.self, from: data))
        }
        if let cached = MacNXNative.cachedReview(from: app.pinnedEngineCommit) {
            upstreamState = .loaded(cached)
        }
    }

    // MARK: - Engine folder and upstream
    func checkUpstreamChangelog() {
        if case .checking = upstreamState { return }
        // Always against the tested pin, so the newest engine stays measurable from the engine Arcane tested.
        let base = app.pinnedEngineCommit
        upstreamState = .checking
        let place = Place(UUID())
        let engine: any EngineAdapter = MacNXNative(place: place, checkout: nxnativePath, prescribed: base,
                                                     expected: activeEngineCommit)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let workshop = try await engine.workshop(place)
                let status = try await workshop.checkUpstream.run(Confirmed(UUID()), request: RequestID(UUID()))
                self.upstreamState = .loaded(status)
                self.checkNewestEngineReadiness(status)
            } catch {
                self.upstreamState = .failed(Self.upstreamErrorMessage(error))
            }
        }
    }

    func openUpstreamCompare() {
        guard case .loaded = upstreamState, let url = MacNXNative.compareURL(from: app.pinnedEngineCommit) else { return }
        NSWorkspace.shared.open(url)
    }

    static func upstreamErrorMessage(_ error: Error) -> String {
        if let refusal = error as? Refusal, case .upstream(let failure) = refusal {
            switch failure {
            case .invalidBase: return UpstreamCheckerError.invalidBase.localizedDescription
            case .invalidURL: return UpstreamCheckerError.invalidURL.localizedDescription
            case .decoding: return UpstreamCheckerError.decoding.localizedDescription
            case .rateLimited(let date): return UpstreamCheckerError.rateLimited(date).localizedDescription
            case .http(let code, let message): return UpstreamCheckerError.http(code, message).localizedDescription
            case .connection(let message): return message
            }
        }
        return error.localizedDescription
    }

    var legacyEnginePath: String? { AppData.preferences.string(forKey: AppViewModel.StorageKeys.savedEngineFolder) }

    func selectNxnativeFolder(startingAt start: URL? = nil, stage: ((URL) -> Void)? = nil) {
        guard !app.isBuilding, !app.isUpdatingApp else { return }
        OortFilePickerPresentation.open(.folder, title: L10n.text("nxnative folder"),
                                        message: L10n.text("Choose the directory containing the nxnative scripts and tools."),
                                        startingAt: start) { [weak self] urls in
            guard let self, let url = urls.first, !app.isBuilding, !app.isUpdatingApp else { return }
            guard EngineLocation.isEngine(url) else {
                app.alertMessage = L10n.format("%@ is not the nxnative engine folder. Choose the folder that contains scripts and dm.", [url.path])
                SoundEffectService.shared.play(.error)
                return
            }
            if let stage { stage(url.standardizedFileURL); return }
            // Remembered, so launch and every check use it; ~/nxnative itself needs nothing stored.
            if let saved = EngineLocation.savedValue(for: url, home: SystemDetector.shared.resolveRootDirectory()) {
                AppData.preferences.set(saved, forKey: AppViewModel.StorageKeys.savedEngineFolder)
            } else {
                AppData.preferences.removeObject(forKey: AppViewModel.StorageKeys.savedEngineFolder)
            }
            useSavedEnginePath(url.path)
        }
    }

    func useSavedEnginePath(_ path: String) {
        nxnativePath = path
        isNxnativeValid = EngineLocation.isEngine(URL(fileURLWithPath: path))
        refreshCompatibility()
    }

    // MARK: - Keys import
    func ensureKeysImported(customRyujinxDir: String? = nil) {
        let fm = FileManager.default
        let read = keyStore.readStatus()
        localKeyStatus = read.status
        if read.status != .required {
            if let error = read.error {
                app.logs.append(LogEntry(level: .error,
                                     message: L10n.format("Stored prod.keys is invalid: %@", [String(describing: error.localizedDescription)])))
            }
            return
        }
        let saved = AppData.preferences.string(forKey: AppViewModel.StorageKeys.savedProdKeysPath)
        let detected = SystemDetector.shared.detectProdKeys(additionalSearchDir: customRyujinxDir)
        let candidate = [saved, detected?.path].compactMap { $0 }.first {
            !$0.isEmpty && fm.fileExists(atPath: $0)
        }
        guard let candidate else {
            return
        }
        importKeys(from: URL(fileURLWithPath: candidate))
    }

    func importKeys(from url: URL) {
        guard !app.isBuilding, !app.isUpdatingApp else {
            let message = L10n.text("Change keys after the porting finishes.")
            if app.showSetupCheck {
                keyImportError = message
            } else {
                app.showSettingsNotice(title: L10n.text("Porting in progress"), message: message)
            }
            return
        }
        do {
            let summary = try keyStore.importKey(from: url)
            keyImportError = nil
            localKeyStatus = .available(applicationGenerations: summary.applicationKeyGenerations.count)
            app.porting.refreshKeyCheck()
            if let folder = app.porting.selectedGameFolder { app.porting.scanGameFolder(folder) }
            app.lastError = nil
            app.logs.append(LogEntry(
                level: .success,
                message: L10n.format("prod.keys imported: header key present, %@ application key generations.", [String(describing: summary.applicationKeyGenerations.count)])
            ))
        } catch {
            localKeyStatus = keyStore.readStatus().status
            keyImportError = ((error as? KeyStoreError) ?? .unreadable).localizedDescription
            app.lastError = keyImportError
            if !app.showSetupCheck {
                app.showSettingsNotice(title: L10n.text("Keys not changed"), message: isProdKeysValid
                    ? L10n.text("The key file could not be imported. Your previous copy is kept.")
                    : L10n.text("The key file could not be imported. Choose a valid prod.keys file."))
            }
            app.logs.append(LogEntry(level: .error,
                                 message: L10n.format("Could not import prod.keys: %@", [keyImportError ?? ""])))
        }
    }

    func selectProdKeysFile(onPick: (() -> Void)? = nil) {
        guard !app.isBuilding, !app.isUpdatingApp else { return }
        OortFilePickerPresentation.open(.keys, title: L10n.text("Keys"),
            message: L10n.text("Choose your prod.keys file. It stays on this Mac.")) { [weak self] urls in
            guard let self, !self.app.isBuilding, !self.app.isUpdatingApp, let url = urls.first else { return }
            self.importKeys(from: url)
            onPick?()
        }
    }

    // MARK: - Environment check and the gate
    /// The Python and PATH every engine process runs with (bundled runtime, else the venv).
    var engineToolchain: EngineToolchain {
        .resolve(runtime: .locate(), repo: URL(fileURLWithPath: self.nxnativePath))
    }

    func detectEnvironment(customRyujinxDir: String? = nil) {
        guard !app.isBuilding, !app.isUpdatingApp else { return }
        restoreBuildInputs(customRyujinxDir: customRyujinxDir)
        refreshCompatibility()
    }

    func restoreBuildInputs(customRyujinxDir: String? = nil, automatic: Bool = false, readKeys: Bool = true) {
        let nxResult = SystemDetector.shared.detectNxnativeDirectory(
            saved: app.settingsStore?.settings.launcherChoices.enginePath ?? legacyEnginePath)
        self.nxnativePath = nxResult.path
        self.isNxnativeValid = nxResult.isValid
        if readKeys && (!automatic || !AppData.profile.isDevelopment) { self.ensureKeysImported(customRyujinxDir: customRyujinxDir) }
    }

    /// With launch checks off, inspecting a build screen performs the check on demand.
    func prepareBuildEnvironmentIfNeeded() {
        if environmentStatus == nil, !isCheckingEnvironment { detectEnvironment() }
    }

    func refreshCompatibility() {
        guard !app.isBuilding, !app.isUpdatingApp else { return }
        app.refreshInstalledEngineVersions()
        let generation = UUID()
        environmentCheckGeneration = generation
        guard self.isNxnativeValid, !self.nxnativePath.isEmpty else {
            compatibilityReport = nil
            environmentStatus = nil
            isCheckingEnvironment = false
            app.porting.scheduleNextBuild()
            return
        }
        isCheckingEnvironment = true
        environmentStatus = nil
        compatibilityReport = nil
        let repo = URL(fileURLWithPath: self.nxnativePath)
        let toolchain = engineToolchain
        let developerDir = resolvedDeveloperDir()
        let expected = self.activeEngineCommit
        let pinned = app.pinnedEngineCommit
        let choice = self.newestEngineChoice
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let environment = NXNativeEnvironment(repoURL: repo, toolchain: toolchain,
                                                  developerDir: developerDir)
            let status = environment.inspect()
            let includedInPin = choice.flatMap { NewestEngineSwitcher(repo: repo).isIncluded($0.commit, in: pinned) }
            let checker = CompatibilityChecker(repoURL: repo, toolchain: toolchain,
                                               developerDir: developerDir)
            let report = try? checker.check(expectedEngineCommit: expected)
            DispatchQueue.main.async {
                guard let self, self.environmentCheckGeneration == generation,
                      self.nxnativePath == repo.path else { return }
                self.isCheckingEnvironment = false
                self.environmentStatus = status
                self.compatibilityReport = report
                self.currentEngineCommit = report?.selectedEngine.value
                if let choice, !NewestEngine.keeps(choice, head: self.currentEngineCommit, pinned: pinned,
                                                    includedInPin: includedInPin) {
                    // The checkout moved (Setup, Back to tested, by hand) or an Arcane update tested this
                    // commit: the tested engine is in charge again.
                    self.forgetNewestEngine()
                    self.refreshCompatibility()
                    return
                }
                if let report, !report.ok {
                    let blocked = report.checks.filter { $0.status == .block }
                        .map { "\($0.title): \($0.detail)" }.joined(separator: " | ")
                    self.app.logs.append(LogEntry(level: .warning, message: L10n.format("Toolchain gate: %@", [String(describing: blocked)])))
                }
                self.app.porting.scheduleNextBuild()
            }
        }
    }

    func resolvedDeveloperDir() -> URL { Self.resolveDeveloperDir() }

    /// Reads no state of the view model, so it can run off the main thread (it runs `xcode-select`).
    static func resolveDeveloperDir(runner: CommandRunning = SystemCommandRunner()) -> URL {
        let fm = FileManager.default
        // An explicit DEVELOPER_DIR always wins.
        if let env = ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
           fm.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        // Respect xcode-select when it points at a full Xcode, not the CLT.
        if let selected = try? runner.run(
            URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"],
            environment: nil, currentDirectory: nil
        ), selected.status == 0 {
            let path = selected.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.contains(".app/Contents/Developer"), fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Prefer a normal Xcode install over the beta when xcode-select is CLT.
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer",
            "/Applications/Xcode-beta.app/Contents/Developer",
            "/Library/Developer/CommandLineTools",
        ]
        for path in candidates where fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/Library/Developer/CommandLineTools")
    }

    var requiredMetalVersion: String? {
        let lock = URL(fileURLWithPath: self.nxnativePath)
            .appendingPathComponent("dm/gfx/tools/dmsh_chain.lock")
        guard let text = try? String(contentsOf: lock, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("metal_macosx\t") {
            guard let raw = line.split(separator: "\t").last.map(String.init) else { return nil }
            return MetalVersion.parse(raw) ?? raw
        }
        return nil
    }

    var installedMetalVersion: String? { environmentStatus?.metalVersion }

    var canPassToolchainGate: Bool {
        compatibilityReport?.ok == true || allowUntestedToolchain
    }

    /// A profile in `dm/games/<title ID>` is the engine's verified support for
    /// a title. Without one the engine builds from a provisional profile and
    /// may fail in the rewrite or at run time.
    func hasVerifiedEngineProfile(for game: PortedGame) -> Bool {
        hasVerifiedEngineProfile(titleId: game.titleId)
    }

    func hasVerifiedEngineProfile(titleId: String?) -> Bool {
        guard let titleId, !titleId.isEmpty else { return true }
        guard !self.nxnativePath.isEmpty else { return true }
        var isDirectory: ObjCBool = false
        let path = URL(fileURLWithPath: self.nxnativePath)
            .appendingPathComponent("dm/games/\(titleId.uppercased())").path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// What the compatibility gate says now; nil until the first check has run.
    var toolchainGateSummary: ToolchainGateCopy.Summary? {
        compatibilityReport.map { ToolchainGateCopy.summary(report: $0, overrideOn: allowUntestedToolchain, newest: self.usesNewestEngine) }
    }
}
