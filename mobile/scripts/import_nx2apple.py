#!/usr/bin/env python3
"""Bring NX2Apple's MIT host layer into mobile/, with Oort's cuts, and write PROVENANCE.md.

usage: import_nx2apple.py <NX2Apple checkout>
Every cut names the text it starts and ends at: an upstream change that moves one stops the import.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parents[1]
CREDIT = "MIT, Copyright (c) 2026 seedds, jhaizhou, LNPANDY and NX2Apple contributors"
HOST = """BackupExclusion BookmarkStore CheatFilePicker CheatFuseGuard CloudSaveSyncCheck DataFolderDiagnostics DataParts
DeepLinkRouter EngineLaunchPlan FolderPicker GameBannerStore GameCatalogue GameCheatsStore GameDeletion GameDirectoryWatcher
GameEnvFileSync GameLauncher GameMods GamePadMapStore GameSettingsStore HomeScreenShortcutSupport HostText
LibraryOrder LogReader LooseRomfsClaimer PlayHistoryStore ProvisioningProfile RomfsIdentity RomfsLanguages
ShaderResources ShellHostModel ShellHostModel+Cheats ShellHostModel+PlayHistory ShellInGameMenu""".split()
CORE = "GameManifest LauncherProfile".split()
MODEL = "ShellInputs ShellArtwork PadMap ShellCheatsModels ShellFormat ShellSettingsStore TouchLayout TouchPadGeometry".split()
APP = "SegSnap.h ShellEngine.h ShellGlue.h ShellOrientation.h ShellSnap.h ShellMain.m ShellShortcuts.swift".split()
TESTS = """ShellHostModelTests ShellHostSettingsRefreshTests ShellDataFolderTests LiveJoinAndWatchTests BackupExclusionTests BookmarkStoreTests CatalogueStateTests CheatFuseGuardTests DataPartsTests DeepLinkRouterTests
EngineLaunchPlanTests FolderPickAnswerTests FrameworkCatalogueTests FrameworkTestSupport GameCheatsStoreTests GameDeletionTests
GameEnvSettingsSyncTests LauncherTests LooseRomfsClaimTests ParsingTests PartialImageTests PictureFitTests PlayHistoryTests
RomfsLanguagesTests SettingsTests ShaderResourcesTests ShellInGameMenuTests ShellSettingsStoreTests TestDefaults
TestDefaultsTests TestSupport""".split()

# (file, from this text, up to this text (kept), what replaces it, why)
SIGN = "Signing a game on the device with the player's own certificate is left out."
NET = "Oort NX mobile makes no network request: downloaded banners are left out."
PIP = "The floating Picture in Picture guide is left out; the shortcut itself stays."
CUTS = [
    ("ShellHostModel", "    /// Fetches official 16:9 banner bytes", "    public var activeRunningGameID", "", NET),
    ("ShellHostModel", "    /// Secure storage backing for", "    /// Whether the running app's signing", "", SIGN),
    ("ShellHostModel", "                fetchBannerData: (@Sendable", "                activeRunningGameID: @escaping", "", NET),
    ("ShellHostModel", "                sideloadCertBacking: any", "                supportsHotFrameworkLoading: @escaping", "", SIGN),
    ("ShellHostModel", "        self.fetchBannerData = fetchBannerData", "        self.activeRunningGameID", "", NET),
    ("ShellHostModel", "        self.sideloadCertBacking", "        self.supportsHotFrameworkLoading", "", SIGN),
    ("ShellHostModel", "    /// Summary of the imported sideload", "    public private(set) var globalPadMap", "", SIGN),
    ("ShellHostModel", "    @ObservationIgnored private let certificatePicker", "    @ObservationIgnored let cheatPicker", "", SIGN),
    ("ShellHostModel", "    @ObservationIgnored private let sideloadCertificateStore", "    @ObservationIgnored var pendingCheatImport", "", SIGN),
    ("ShellHostModel", "    @ObservationIgnored private var certificateGeneration", "    @ObservationIgnored private let adapter", "", SIGN),
    ("ShellHostModel", "    @ObservationIgnored private let homeScreenGuidePiP", "    @ObservationIgnored private var dataStores", "", PIP),
    ("ShellHostModel", "    @ObservationIgnored private var bannerFetchGeneration", "    @ObservationIgnored private var ", "", NET),
    ("ShellHostModel", "    @ObservationIgnored private var bannerFetchTask", "    @ObservationIgnored private var ", "", NET),
    ("ShellHostModel", "    @ObservationIgnored private var attemptedBannerFetches", "    @ObservationIgnored", "", NET),
    ("ShellHostModel", "                certificatePicker: any", "                cheatPicker: any", "", SIGN),
    ("ShellHostModel", "        self.certificatePicker =", "        self.cheatPicker =", "", SIGN),
    ("ShellHostModel", "        self.sideloadCertificateStore =", "        self.shellSettings =", "", SIGN),
    ("ShellHostModel", "        let certStore = sideloadCertificateStore", "        defaultsObserver =", "", SIGN),
    ("ShellHostModel", "                self.stopHomeScreenFloatingGuide()\n", "                guard !self.isBusyWithGame", "", PIP),
    ("ShellHostModel", "            onAddToHomeScreen: {", "            onSaveCustomCover:", """            onAddToHomeScreen: { [weak self] id in
                guard let self else { return false }
                return await self.saveIconAndOpenShortcuts(for: id)
            },
""", PIP),
    ("ShellHostModel", "            onPickSideloadCertificateFile:", "            onLoadCheats:", "", SIGN),
    ("ShellHostModel", "    // MARK: Sideload .p12", "    // MARK: Custom and backfilled", "", SIGN),
    ("ShellHostModel", "    /// Low-priority background backfill", "    public func change(_ id: String, setting", "", NET),
    ("ShellHostModel", "    public func prepareHomeScreenFloatingGuide", "    @discardableResult\n    public func saveIconAndOpenShortcuts", "", PIP),
    ("ShellHostModel", "        if showFloatingGuide {", "        config.openURL(HomeScreenShortcutSupport", "", PIP),
    ("ShellHostModel", "                let fwURL = game.frameworkURL", "            game.shaderResourcesURL = try", "            }\n\n", SIGN),
    ("ShellHostModel", "            do {\n                try await launcher.launch(game)", "        } catch {\n            guard isLaunchStillValid", """            try await launcher.launch(game)
            recordSessionDidStart(for: game)
            return .launched
""", SIGN),
    ("GameBannerStore", "    public static let maxStoreHTMLBytes", "    public enum StoreError", "", NET),
    ("GameBannerStore", "    public struct RemoteResponse", "    /// Normalizes a game title ID", "", NET),
    ("GameBannerStore", "    public static func nlibBannerURL", "    /// Returns pixel dimensions", "", NET),
    ("GameBannerStore", "    /// Extracts an official banner image URL", "    private static func writeValidatedBanner", "", NET),
    ("HomeScreenShortcutSupport", "/// Renders high-contrast 16:9 dark step cards", None, "", PIP),
    ("ShellInputs", "/// Read-only summary of an imported sideload", "/// Player choice in `CloudSaveConflictView`", "", SIGN),
    ("ShellInputs", "    /// Opens the system file picker for a `.p12`", "    /// Loads the current cheats snapshot", "", SIGN),
    ("ShellInputs", "    public var supportsSideloadCertificate", "    public var supportsCheats", "", SIGN),
    ("ShellInputs", "                onPickSideloadCertificateFile:", "                onLoadCheats:", "", SIGN),
    ("ShellInputs", "        self.onPickSideloadCertificateFile", "        self.onLoadCheats", "", SIGN),
    ("ShellMain", '#import "DmShell-Swift.h"', "\n", '#import "OortNX-Swift.h"', "The Swift module is OortNX."),
]
CUTS.append(("SideloadCertificateStore", "/// Raw credential storage backend for the sideload `.p12` certificate.", None, "", SIGN + " Only the certificate reader stays, to check who signed a game."))
CUTS.append(("TestSupport", "                fetchBannerData: @escaping", "                now: @escaping", "", NET))
CUTS.append(("DeepLinkRouterTests", "    @Test func projectShellYmlDeclares", None, "}\n", PIP + " Their project file has no test here."))
REPO = "A test that reads another file of NX2Apple's repository is left out."
CUTS += [
    ("RomfsLanguagesTests", "    #if os(macOS)\n    /// Generate the row from the pinned engine", "    @Test func theRowStaysWhenTheRomFSCannotNarrowIt", "", REPO),
    ("TestDefaultsTests", "    @Test func copiesInTestTargetsMatch", "    @Test func noTestMakesASuiteAnotherWay", "", REPO),
    ("ShellHostModelTests", "    @Test func theQuitPromptTextsFollowTheTextRules", "    @Test func padOverridesPersistMergeAndReset", "", REPO),
]
SHARED = "In OortCore, for every system: the words are English, ShellHost says them in the player's language."
CUTS.append(("HostText", "/// What is wrong with a bundle", "    /// The short state label", "extension ProblemCause {\n", SHARED))
CUTS.append(("HostText", "/// Why a game cannot be shown as playable", "    /// The broken state a tile shows", "extension GameProblem {\n", SHARED))
EDITS = [
    ("HostText", ".broken(reason: reason, detail:", ".broken(reason: spokenReason, detail:", SHARED),
    *((name, "hostText(", "(", SHARED) for name in CORE),
    ("LauncherProfile", "LauncherSetting", "GameLauncherSetting", SHARED),  # ArcanePorting has a LauncherSetting of its own
    ("LauncherProfile", "dm/ios/Sources/GameLauncherSetting", "dm/ios/Sources/LauncherSetting", SHARED),
    *((name, old, new, SHARED) for name, old, new in (
        ("GameManifest", "func isTitleID", "public func isTitleID"), ("GameManifest", "func parseVersion", "public func parseVersion"),
        ("GameManifest", "func isVersion", "public func isVersion"), ("GameManifest", "    var minOSVersion", "    public var minOSVersion"),
        ("GameManifest", "func describe", "public func describe"), ("GameManifest", ".label", ".words"), ("LauncherProfile", ".label", ".words"))),
]
EDITS.append(("LauncherProfile", "    public var id: String { env }\n", """    public var id: String { env }
    /// A row made outside a `launcher.json` (the languages found in a game's own files).
    public init(env: String, kind: String, section: String?, label: String, note: String, def: String, needs: String?, level: String?,
                options: [[String]]?, min: Double?, max: Double?, step: Double?, on: String?, off: String?) {
        self.env = env
        self.kind = kind
        self.section = section
        self.label = label
        self.note = note
        self.def = def
        self.needs = needs
        self.level = level
        self.options = options
        self.min = min
        self.max = max
        self.step = step
        self.on = on
        self.off = off
    }
""", SHARED))
TABS = "L and R change the tab."
EDITS += [
    ("ShellArtwork", "    let image: CGImage\n", "    public let image: CGImage\n", "Read by Oort NX's screens."),
    ("PadMapping", "        case .leftShoulder, .rightShoulder: nil\n", "        case .leftShoulder: .previousTab\n        case .rightShoulder: .nextTab\n", TABS),
    ("ShellInputs", "controllers, shellSettings }", "controllers, shellSettings, previousTab, nextTab }", TABS),
    ("PadMappingTests", "        XCTAssertNil(PadMapper.action(for: .leftShoulder))\n", "        XCTAssertEqual(PadMapper.action(for: .leftShoulder), .previousTab)\n", TABS),
    ("GameCheatsStoreTests", ",\n            sideloadCertBacking: InMemoryCertBacking()", "", SIGN),
    ("TestSupport", "                               openURL: open, fetchBannerData: fetchBannerData,\n                               fetchBannerOutcome: fetchBannerOutcome,\n                               fetchStoreResponse: fetchStoreResponse, now: now,\n                               sideloadCertBacking: InMemoryCertBacking())",
     "                               openURL: open, now: now)", NET + " " + SIGN),
    ("ShellHostModel", "        startMissingBannerFetch()\n", "", NET),
    ("ShellHostModel", "        await certificateLoadTask?.value\n", "", SIGN),
    ("ShellHostModel", "        await bannerFetchTask?.value\n", "", NET),
    ("ShellHostModel", "                MachOLocalSigner.removeReceipt(for: entry.directory)\n", "", SIGN),
    ("ShellHostModel", "            MachOLocalSigner.removeReceipt(for: canonicalHot)\n", "", SIGN),
    ("ShellHostModel", "            let isHotExternal = hotRoot.map { MachOLocalSigner.isInsideAllowedRoot(game.frameworkURL, allowedRoot: $0) } ?? false\n            var usedCachedReceipt = false\n",
     "            let isHotExternal = hotRoot.map { game.frameworkURL.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path + \"/\") } ?? false\n", SIGN),
    ("ShellHostModel", "            if let hotRoot, isHotExternal {", "            if isHotExternal {", SIGN),
    ("ShellHostModel", "saveIconAndOpenShortcuts(for id: String, showFloatingGuide: Bool = true)", "saveIconAndOpenShortcuts(for id: String)", PIP),
    ("ShellHostModel", "        stopHomeScreenFloatingGuide()\n", "", PIP),
]
# The catalogue has no launcher, engine or update address of NX2Apple's.
BRAND = [("dev.nx2apple.shell", "io.github.sofianbll.oortnx.mobile"), ("nx2apple", "oortnx"), ("NX2APPLE", "OORTNX"),
         (", or import your sideload .p12 certificate in Settings to sign it automatically on this device", "")]


def edit(name, text, notes):
    def note(why):
        if why not in notes:
            notes.append(why)
    for file, start, stop, new, why in CUTS:
        if file != name:
            continue
        i = text.find(start)
        j = len(text) if stop is None else text.find(stop, i + len(start))
        if i < 0 or j < 0:
            sys.exit(f"{name}: cut not found: {start.strip()[:60]!r}")
        text = text[:i] + new + text[j:]
        note(why)
    for file, old, new, why in EDITS:
        if file != name:
            continue
        if old not in text:
            sys.exit(f"{name}: edit not found: {old.strip()[:60]!r}")
        text = text.replace(old, new)
        note(why)
    return text


def brand(text, notes):
    out = []
    for line in text.split("\n"):
        new = line
        if not line.lstrip().startswith("//"):
            for old, value in BRAND:
                new = new.replace(old, value)
            new = re.sub(r"NX2Apple(?!#)", "Oort NX", new)
        if new != line and "Names and addresses are Oort NX's." not in notes:
            notes.append("Names and addresses are Oort NX's.")
        out.append(new)
    return "\n".join(out)


def main(checkout):
    source = checkout / "frontend-ios"
    commit = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "--short=7", "HEAD"], text=True).strip()
    rows = []

    def put(origin, target):
        raw = (source / origin).read_text()
        notes = []
        text = edit(Path(origin).stem, raw, notes)
        text = text.replace("import ShellUI\n", "import ShellModel\n")
        text = brand(text, notes)
        head = f"// From NX2Apple frontend-ios/{origin} at {commit} ({CREDIT}). Changes: mobile/PROVENANCE.md.\n"
        path = HERE / target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(head + text)
        rows.append((target, f"frontend-ios/{origin}", hashlib.sha256(raw.encode()).hexdigest()[:12], " ".join(notes) or "As is."))

    for name in HOST:
        put(f"Sources/ShellHost/{name}.swift", f"Sources/ShellHost/{name}.swift")
    put("Sources/ShellHost/SideloadCertificateStore.swift", "Sources/ShellHost/X509Certificate.swift")
    for name in CORE:
        put(f"Sources/ShellHost/{name}.swift", f"../Sources/OortCore/{name}.swift")
    for name in MODEL:
        put(f"Sources/ShellUI/{name}.swift", f"Sources/ShellModel/{name}.swift")
    for name in ("GamepadAdapter", "PadMapping"):
        put(f"Sources/ShellControllers/{name}.swift", f"Sources/ShellControllers/{name}.swift")
    for name in APP:
        put(f"Shell/App/{name}", f"App/{name}")
    for name in TESTS:
        put(f"Tests/ShellHostTests/{name}.swift", f"Tests/ShellHostTests/{name}.swift")
    put("Tests/ShellControllersTests/PadMappingTests.swift", "Tests/ShellControllersTests/PadMappingTests.swift")
    for file in sorted((source / "Tests/ShellHostTests/Fixtures").rglob("*")):
        if file.is_file():
            target = HERE / "Tests/ShellHostTests" / file.relative_to(source / "Tests/ShellHostTests")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(file.read_bytes())
    for old, new in (("ShellHost", "ShellHost"), ("ShellUI", "ShellModel")):
        catalog = json.loads((source / f"Sources/{old}/Resources/Localizable.xcstrings").read_text())
        catalog = json.loads(json.dumps(catalog, ensure_ascii=False).replace("NX2Apple", "Oort NX").replace(BRAND[3][0], ""))
        target = HERE / f"Sources/{new}/Resources/Localizable.xcstrings"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(catalog, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
        rows.append((f"Sources/{new}/Resources/Localizable.xcstrings", f"frontend-ios/Sources/{old}/Resources/Localizable.xcstrings", "generated",
                     f"{len(catalog['strings'])} texts. Names are Oort NX's."))
    table = "\n".join(f"| `{a}` | `{b}` | `{c}` | {d} |" for a, b, c, d in sorted(rows))
    (HERE / "PROVENANCE.md").write_text(f"""# Files from NX2Apple

[NX2Apple](https://github.com/LNPANDY/NX2Apple) at `{commit}`, {CREDIT}. The licence text is in the root `NOTICE`.
`mobile/scripts/import_nx2apple.py <checkout>` writes these files and this list. The SHA-256 is the original file's.
No view of NX2Apple's is here: the screens are Oort NX's (`Sources/OortMobile`).

| File | From | SHA-256 | Change |
|---|---|---|---|
{table}
""")
    print(f"{len(rows)} files from NX2Apple {commit}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]).resolve())
