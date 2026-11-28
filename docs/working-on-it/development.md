# Development and releases

This guide covers building Oort NX itself. For app setup, game preparation and daily use, start with the [user guide](../../README.md). Read [AGENTS.md](../../AGENTS.md) before changing engine integration or installation behaviour.

## Development prerequisites

- An Apple-silicon Mac running macOS 26 or later.
- Full Xcode selected for the build. The current game toolchain requires Xcode 27.2 or later and the Metal compiler certified for the pinned engine. `Package.swift` declares Swift tools 6.0 (`OortCore`, `OortLibrary` and `NxnativeAdapter` build in the Swift 6 language mode, the app and the tests in Swift 5; in Swift 6 a block written inside a main-actor method stops the app when another queue runs it, so write such a block in a `nonisolated` helper) and macOS 26 as package minimums; those values do not certify an engine/compiler combination.
- Only a normal launch from the `.app` bundle uses the player's Trash. Tests, fixture modes and headless probes use a private folder. `OORT_TRASH` must name an existing directory inside the system's temporary directory; the resolved destination is checked. `scripts/check swift` and `scripts/check app-probes` create it and fail if `~/.Trash` gains an entry or cannot be observed (`scripts/trash_guard.py`).
- Git and the command-line tools supplied with Xcode.
- Python 3 for the publication checks and packaging helpers.
- Homebrew's `zstd` and `glslang`, at the versions recorded in [engines/nxnative/runtime.lock](../../engines/nxnative/runtime.lock), when preparing the bundled runtime. The script checks installed versions; it does not install or silently upgrade them.

Building the frontend alone does not need games or keys. Running the game's build workflow also needs the pinned nxnative checkout (its tools are native executables since 641636e2, so no .NET) and the user's own authorised sources and keys. Setup explains and prepares the supported prerequisites.

## Build a development app

From the repository root:

~~~sh
bash scripts/bundle_runtime.sh
bash scripts/build_app.sh
codesign --verify --deep --strict "$HOME/Applications/Oort NX Dev.app"
~~~

The default destination is `~/Applications/Oort NX Dev.app`, named **Oort NX Dev**. It stays apart from the self-updating release (`Oort NX.app` for new installs; existing copies may keep a legacy path). On the launcher-development branch, Dev uses bundle ID `local.nxlibrary.development`, app data under `~/Library/Application Support/NXLibrary-Development`, a separate cache root and preference domain. A new Dev profile offers an independent copy of a stable local library if present. It copies catalog, profiles, artwork and play history, not builds, saves, preferences, queues or credentials. Close the release copy before importing. The held 0.1.4.3 branch retains its previously validated behavior. `build_app.sh` compiles the Release configuration, creates the bundle in staging, includes resources and notices, ad-hoc signs and verifies it, then installs it through the same atomic installer used by the application. It does not launch the app.

A development copy shows the version from the repository's `VERSION` file as "(Dev · Launcher)" in Settings and never updates itself. `scripts/release` packages that same version with a release marker. After a release, raise `VERSION` to the next version being worked on.

An alternate destination can be supplied without replacing the installed development copy:

~~~sh
bash scripts/build_app.sh /tmp/Oort-NX-Review.app
~~~

A plain development app uses bundle ID `local.nxlibrary.development`, takes its version from `VERSION` and has no release marker. It never installs its own updates.
For an identifiable trial build, set `NX_DEV_COMMIT` to the full SHA of the clean checkout. The bundle records it and Settings → About shows its short form beside the build date.

Register a public PKCE application with Nextendo for `http://127.0.0.1:47823/callback`, with the engine's `identity`, `friends`, `game.matchmaking`, `presence` and `profil` scopes. Enter the public ID in Online services when the selected engine declares support. To package a default instead, optionally set `DM_NEXTENDO_CLIENT_ID` when running `build_app.sh`; it writes only the public ID to `DMNextendoClientID`. Do not supply a client secret.

`BuildCommandBuilder` adds `--nextendo` to `scripts/build_ipa_from_nsp.py` only when the selected checkout declares it and a valid public client ID is available (settings first, then Arcane's `Info.plist`). Only that command gets `DM_NEXTENDO_CLIENT_ID` in its environment; building does not check the player's session. The engine can reuse a valid cached patch catalog and can continue when a verified catalog has no patch for the exact game build. A fetch or verification failure fails the build; Arcane shows the engine error and does not retry without Nextendo. The engine pin is unchanged.

### Private Google Drive builds

Supply both `ARCANE_GOOGLE_CLIENT_ID` and `ARCANE_GOOGLE_CLIENT_SECRET` to `scripts/release` or `scripts/build_app.sh` for a private build. Use a desktop OAuth client. If either variable is missing or blank, neither key is added to `Info.plist`. Anyone with the app, ZIP or DMG can read them: keep the artifacts private and do not use shell tracing. `scripts/release` puts these packages in `work/release-private` and refuses to build them in CI. A public update can replace a private copy's embedded client.

No app bundle includes rclone. With the player’s consent, `RcloneDownload` fetches the pinned macOS arm64 ZIP directly from the official HTTPS host, checks its exact size and SHA-256 against the reviewed [upstream checksums](https://downloads.rclone.org/v1.75.2/SHA256SUMS), and extracts only the expected member into the private app-data tree on the destination volume. `SecStaticCodeCheckValidity` verifies the original embedded signature before an exclusive atomic rename. The upstream signature is ad hoc, not a Developer ID or notarization claim; the checked archive hash is the identity of this release. URLSession writes bytes into app-created files, rather than opening a Finder download, and the app does not remove quarantine, re-sign or run approval overrides. Externally chosen executables retain their own signatures and quarantine. If macOS refuses one, choose a working executable in Advanced.

The managed path is `<profile support>/DriveTools/rclone-<version>/rclone`; only a completed, receipted copy can be resolved or offered for Trash. The same resolved absolute executable is used for CLI calls and the Unix-socket `rclone rcd`; replacing the backend stops the old daemon. Replacing the bundled binary rejects an external replacement with its own [portable config](https://rclone.org/docs/#config-string), including beside a symlink’s target, unless the same explicit `RCLONE_CONFIG` overrides it. A failed or cancelled download does not publish an executable or touch the configured remote.

### Bundled runtime

`bundle_runtime.sh` prepares `work/Runtime/` from the exact downloads and hashes in `engines/nxnative/runtime.lock`. It includes Python, capstone, lz4, fontTools, zbic (Nintendo's zstd variant, read by the engine for system 22.0.0+ code), nsz with its dependencies (NSZ / XCZ inputs), `zstd` and `glslangValidator`, their required non-system libraries and licence notices. zbic is GPLv2, so its source archive ships in `Runtime/sources/`. `EngineRuntimeRequirementsTests` fails when the pinned engine's README or `.github/requirements/tools.txt` asks for a Python package that `engines/nxnative/runtime.lock` lacks. It relinks the native libraries for the bundle, signs them and checks that the tools run without Homebrew on `PATH`.

For a complete Dev trial, prepare that same runtime before building and check Setup in an isolated home. The runtime does not include rclone. The bundler removes Python's upstream build-user path from sysconfig metadata; Python computes the current user's base at runtime.


Run it again when the lock changes. `build_app.sh` checks the runtime metadata against the lock before copying it. The lock is a reviewed input, not a request to install whichever package versions happen to be newest.

Builds reject a bundled rclone and check the licence manifest against the staged
app and, for releases, against the extracted release ZIP. Review applicable obligations, original
texts and source files whenever an input changes; update the checked hashes
only after that review. To check an existing release bundle without building it:

~~~sh
python3 scripts/check_publication.py --app /path/to/Oort\ NX.app
~~~

Passing this check establishes presence and byte identity of the reviewed files,
not redistribution rights or completeness of corresponding source.

For frontend-only work, `build_app.sh` can run without `work/Runtime/`. That development copy uses the configured engine's virtual environment and tools on `PATH` for game preparation. It is not a self-contained distribution build. A release requires the bundled runtime.

Generated `.build/`, `work/` and `dist/` content stays outside version control. Do not commit the user's engine checkout, game apps, source packages, keys or diagnostics.

### Debug configuration

~~~sh
NX_BUILD_CONFIG=debug bash scripts/build_app.sh /tmp/Oort-NX-Debug.app
~~~

Debug builds recognise `--show-setup` and `--preview-build` for manual inspection of Setup and the simulated porting presentation. These flags are compiled out of Release builds. The preview is UI development data, not evidence that a real game builds or launches.

For the offline integration fixture, run the packaged Debug executable with
`--integration-fixture` (add `--fixture-fr` to start in French). The fixture never
mounts the normal startup or opens real game, settings or service actions. It
uses a fresh private temporary app-data root and preferences file. The `Fixture`
button cycles synthetic states and `Onboarding` opens the setup preview. Use
`--render-integration-fixture /absolute/output` instead to write the same
Selene views to PNG in French and English, at 1440 and 780 points wide, without
opening a window.

`--render-sound-fixture /absolute/output` usa la stessa radice temporanea e
rende la pagina Sound reale nelle due lingue e larghezze, con la riga del
pacchetto in focus: le quattro voci, due pacchetti sotto Other (uno importato e
fittizio), senza eseguire l’avvio normale o riprodurre audio.

`--oort-ui-gallery` opens a Debug-only component gallery, with no game catalog
or service. Pass `--render-oort-ui-gallery /absolute/output` to render it
offscreen in French and German on Oort, Catppuccin Latte and Vantablack.
Compare the matching PNGs against a recorded run at the same size; use a
tolerant comparison across OS versions and inspect flagged differences.

From the checkout root, run `.build/debug/OortMac --render-file-picker /absolute/output`
to list synthetic folders and capture the real picker in French at two widths
over a bright fixture wallpaper. The probe never displays a window.

`--render-command-palette /absolute/output` presses every key and button of the
command palette, then renders its states in French, English and German, on a
dark and a light palette, at two window sizes. It never displays a window; a
build without this flag would open the app, so build first.

## Verification

~~~sh
scripts/check
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
scripts/check swift
scripts/check app-build && scripts/check app-probes debug   # then each batch of: python3 scripts/ci_catalog_checks.py matrix
bash scripts/build_app.sh
codesign --verify --deep --strict "$HOME/Applications/Oort NX Dev.app"
~~~

`scripts/check --list` names every rule and its tests. Edit `design/oort.tokens.json`, then run `scripts/generate`
and commit the generated outputs (Swift, CSS, palettes). The generator checks contrast on opaque
default Oort surfaces, not artwork or other palettes. The 26 px distance
reference is rendered glyph height at 1080p, not a 26-point SwiftUI font.

When reviewing an engine upgrade in a separate checkout, set `NX_TEST_ENGINE_REPO` to that checkout's absolute path for `swift test`. The engine-fragment regression reads the application's pin and checks it in that repository; an invalid explicit path fails. Without the variable it uses `~/nxnative`, skipping only when that default checkout is absent. This allows verification without fetching into or changing the engine used by the installed app.

To check the prepared runtime as well:

~~~sh
python3 scripts/check_publication.py --runtime work/Runtime
~~~

The Swift suite covers persistence, sources, keys and permissions, CLI contracts, process output and cancellation, compatibility gates, installation and retries, launch configuration, presentation state, artwork, cheats and save recovery. Publication regressions use temporary repositories and synthetic content. Tests must never require copyrighted game content or real keys.

The nested-bundle check creates tiny Mach-O fixtures with signed data bundles and relative Resources links. It exercises the real installer, icon writer and codesign, including signature rollback, interrupted publication and rejection of modified nested data. Its forced copy branch does not establish compatibility with a real external filesystem or game build.

The artwork-return check compiles the real tile views, loading tasks and retained Mods host with generated images and isolated preferences. It records which image the first body selects after view recreation, without rendering or opening a window, and checks pick removal, Steam app updates, Mods badges after external removal and changed GameBanana matches. Network is forbidden in the Mods fixture.

For the optional Mac shortcut handoff check, set `OORT_MAC_SHORTCUT_PROBE=1` for `apps/mac/Tests/CatalogAppChecks/run_profiles.py` and pass a fresh output directory. The probe renders Sources, Spotlight, Collection and the shortcut dialogs in English and French at two sizes, and hands only its own temporary, compiled fixture to Launch Services.

After building Debug, `python3 apps/mac/Tests/CatalogAppChecks/run_platform_cards.py /absolute/new-output` renders Spotlight in French at two sizes on a bright synthetic wallpaper. It exercises the card through the screen's controller action receiver without opening a window or running games; with ffmpeg it also saves a silent clip.

After building Debug, `python3 apps/mac/Tests/CatalogAppChecks/run_credits.py /absolute/new-output` renders Settings › About in French, English and German and checks that every credit is within the controller's reach. A new dependency, service, font or symbol needs its entry in `design/credits.json`; run `python3 scripts/generate_credits.py` (add `--engine <checkout>` and `--site <folder>` to check them too).

Passing checks do not establish that an interactive update or a game works. See the [test catalog](file-map.md#test-e-fixture).

For manual setup checks on an existing account, use **Settings → Start-up → Open Setup**: Continue opens Your games without resetting the library. Check file-picker cancellation, Back, Open library and source review. A fresh account additionally verifies Skip persistence and resuming an interrupted first setup. Interactive checks remain the user's responsibility; agents do not launch the UI.

`scripts/release` runs `scripts/check app-probes all` after the Swift suite and stops if any check fails. The probes use synthetic inputs and isolated homes. The downgrade comparison and download capture report a skip without their explicit inputs; the NUP engine-snapshot probe remains optional.

### Continuous integration

The [Checks workflow](../../.github/workflows/ci.yml) runs on `main` pushes and pull requests, including forks. Its **Rules** job runs `scripts/check` on Linux; every check build waits for it. The Mac jobs use GitHub-hosted `xcode-27`, at most five at a time per account. The single **Checks** verdict requires the rules and, for Swift changes, the Swift unit suite with the shared probes, every standalone probe batch and the Release build. The Debug job first repeats the Python tests on Mac. The common probe helper uses the runner home for Xcode mounts and an isolated fixture home for the probe. Every `run_*.py` reports its timing.

Checkout is pinned and does not retain credentials. Checks use read-only permissions and no secrets. Manual dispatch with `mac_packages` calls the Mac packaging job with the same read-only permissions. CI does not run real games or certify the engine. See the [runner measurements](../history/reviews/2026-11-26-mac-ci.md).

Standalone probes use a SHA-256-verified rclone release for the synthetic local transport. SwiftUI-only text checks read a companion PDF from the same offscreen renderer and prove each expected text visible from its pixels (`assertVisible`); the AppKit settings probe still reads its screenshots and uses CPU-only Tesseract in CI for the hidden windows. The OCR package lock and language files are test dependencies, not application dependencies (Tesseract and its language data: Apache-2.0; see the [npm wrapper](https://github.com/naptha/tesseract.js)). `workflow_dispatch` can exercise all jobs on an authorized fix branch without changing `main`.

### Manual checks

Interactive app and game checks are performed by the user. Agents must not use computer-use or other UI automation. Compilation, unit tests and signature verification cannot establish that the interface or a game works.

Before a game/toolchain combination is described as working, the user checks **Settings → Setup and engine**, builds a real game and launches it to a visible screen. Record the engine and Metal versions and whether the untested override was used.

## Engine upgrades

Never patch `~/nxnative` or follow `main` automatically. `AppViewModel.defaultPinnedEngineCommit` and `defaultPinnedEngineRepository` select the fork checkout; Mac builds write both to `Info.plist`. Choosing **Newest engine** explicitly still targets upstream. `ToolchainRequirements.current` describes the supported setup requirements and downloadable Metal assets.

An upgrade requires reviewing the upstream delta and CLI, deciding which capabilities to adopt, wiring applicable flags, updating certification data and verifying tests, the gate, a real build and a visible launch. Follow the [upgrade checklist](../history/engine-upgrades/README.md), write a dated note and update the README, design spec and changelog. A newer engine commit alone is not sufficient evidence.

## Release packaging

`scripts/release` builds the same Mac packages as CI. It requires a clean tree and `work/Runtime` from `scripts/bundle_runtime.sh`. It verifies that the exact engine SHA is reachable from a public branch of the selected fork, then tests the launcher against that SHA. `scripts/check version` validates `VERSION` and the current CI tag; `scripts/check release` guards the publication boundary. The local command cannot tag, push or publish.

The release DMG uses the Oort artwork by default. Set up its build-only Python
tools once in a virtual environment outside the repository:

```bash
dmg_env="$(mktemp -d "${TMPDIR:-/tmp}/oort-dmg-tools.XXXXXX")"
python3 -m venv "$dmg_env"
"$dmg_env/bin/python" -m pip install --require-hashes --only-binary=:all: -r scripts/dmg-requirements.txt
export OORT_DMG_PYTHON="$dmg_env/bin/python"
```

[dmgbuild](https://github.com/dmgbuild/dmgbuild), [ds_store](https://github.com/dmgbuild/ds_store) and [mac_alias](https://github.com/dmgbuild/mac_alias) (both MIT) are not included in the app or installer. The DMG step works offline after setup and needs Xcode's Swift and SetFile. `diskutil image create from` drops the canonical spelling `.DS_Store` when copying a folder on macOS 27; the builder stages it as `.ds_store` and verifies its contents at the canonical path on the case-insensitive APFS volume.

From a clean checkout, with the locked runtime and DMG tools ready:

~~~sh
scripts/release
~~~

The script verifies the signed bundle and re-reads its metadata in the updater ZIP and the mounted DMG. `work/release/` contains both packages, `SHA256SUMS` and the Xcode/engine note consumed by the updater. Use `scripts/release --plain-dmg` for the unstyled installer; missing tools do not silently change the style.

Platform SVGs, generic Lucide fallbacks and notices live in `design/Brands/Platforms`.
Publication checks verify reviewed hashes and reject extra brand files. Only the two Switch platform symbols are an exception to the Nintendo artwork rule.

[Release packages](../../.github/workflows/release.yml) builds on a matching `vX.Y.Z` tag or manual dispatch, and currently only uploads Mac artifacts. Before the release workflow joins the default branch, use the already-registered Checks workflow with `mac_packages` on the authorized branch. A rehearsal has read-only repository permissions.

### Publication perso (Sofian)

Oort NX utilise son propre `MAJOR.MINOR.PATCH` : **PATCH** pour les correctifs seuls, **MINOR** pour les nouveautés compatibles et **MAJOR** pour les changements incompatibles. La base amont (« basé sur Arcane 0.2.1 ») figure dans les notes et dans À propos, jamais dans le numéro. Les anciennes releases `0.2.1.2026112x` conservent leurs versions et leurs tags ; l’updater les reconnaît toujours.

1. Valider le commit moteur exact du fork. Avec accord, poser `oort-vX.Y.Z` côté moteur et `vX.Y.Z` sur le commit approuvé de `main` côté lanceur. Les deux tags restent immuables.
2. Donner à la CI l'identifiant **public** Nextendo via la variable de dépôt `DM_NEXTENDO_CLIENT_ID`, après accord séparé sur le réglage GitHub. Une répétition manuelle peut construire sans cet identifiant ; un tag le demande pour préserver le défaut du paquet distribué. Ne jamais fournir de secret Nextendo.
3. Préparer les [notes FR](perso-release-notes.md) à partir de `CHANGELOG.md`, avec le marqueur de compatibilité généré. Ne dater les notes dans le changelog qu'à la publication effective.
4. Dans une release du fork, **Settings → About → Check now** propose les nouvelles versions compatibles. Après redémarrage, **Setup** propose le moteur épinglé. Les jeux existants gardent le moteur avec lequel ils ont été compilés ; **Upstream** compare toujours à `seedds/nxnative` `main`.

### Distribution work still open

The first public alpha uses the existing `local.nxlibrary` bundle identity and ad-hoc signing, without notarisation. Developer ID distribution will need signing-identity verification and notarisation. Updates verify GitHub's SHA-256 digest and the sealed app signature; ad-hoc signatures do not independently identify the publisher.

From 0.4.0 the updater uses `sofianbll/oort-nx` directly, with anonymous public access. Copies up to 0.3.0 check `sofianbll/NxLibrary`. Release copies update themselves; source builds remain excluded. ZIP downloads are limited to 512 MiB, restricted to GitHub's HTTPS download hosts and checked against the published size and digest. The bundled Python checks paths, symlinks, duplicates, special files and a 30,000-entry limit, then extracts using bounded raw decompression with a 2 GiB total limit. It verifies actual output size and CRC rather than trusting ZIP size fields. Release packaging uses the same extraction path and verifies the extracted bundle signature; ZIPs omit Finder metadata sidecars.

### First installation and A → B update test

Validate installation from the published DMG and replacement of an installed release. Keep the same bundle ID and data paths between versions. Engine upgrades additionally follow the [upgrade checklist](../history/engine-upgrades/README.md).

1. Download release A's DMG from GitHub, install normally, eject the DMG and complete Setup. Check that the installation folder is writable; updates must not change permissions silently.
2. Build and launch one supported game using the user's own files. Save progress, set a favourite and change one preference. Create a save backup, then close the game and app.
3. Prepare B with a higher numeric version and clear test notes, keeping the same bundle ID, data paths and engine pin. No artificial feature is required to exercise replacement.
4. Once B is published with approval, open the installed A. Automatic checks run at most once per 24 hours; use **Settings → About → Check now** for an immediate check. The manual check exposes availability in About; the launch popup is a separate check after the interval.
5. Update from inside A. Verify B reopens, reports its version and retains the library, favourite, preference, keys, backups and game progress. Test the automatic launch offer separately. Record actual results; compilation does not establish that this interactive flow worked.

The updater reads `releases/latest`, which excludes draft and prerelease entries. A copy running a pre-release reads the release list instead, so a beta finds the next beta. Keep both A's DMG and ZIP outside `work/release` when preparing B. Do not alter the Mac's clock to exercise the interval.

These are distribution decisions. Do not bypass the dirty-tree check, change the engine pin or weaken the Metal gate to make packaging succeed.

## Repository areas

| Path | Responsibility |
|---|---|
| `core/OortLibrary/` | Models, rules and services without SwiftUI, one folder per area (`App`, `Catalog`, `Library`, `Selene`, `Details`, `Artwork`, `Achievements`, `Mods`, `Settings`, `Steam`); nothing Switch. |
| `engines/nxnative/NxnativeAdapter/` | The `NxnativeAdapter` target: everything Switch (Setup, build, launch, game settings, cheats, Nintendo store, saves, RomFS mods and GameBanana, the nxnative part of catalog and library), one folder per part; it depends on `OortLibrary`. |
| `apps/mac/OortMac/` | App entry, coordination, SwiftUI screens, theme and macOS integration. |
| `core/Tests/OortLibraryTests/` | Automated regressions of the base and synthetic fixtures; the target depends only on `OortLibrary`. |
| `engines/nxnative/Tests/NxnativeAdapterTests/` | Automated regressions of every file that uses the `NxnativeAdapter` module. |
| `scripts/tests/PublicationChecks/` | Publication-guard regressions. |
| `design/` | Tokens, vocabulary and credits; the app icon sources (`Icons/`), fonts and interface media (`Selene/`, `SoundPacks/`, `Brands/`), third-party licence texts, and their notices. |
| `apps/mac/AppIcon.icns` | The Mac's ICNS fallback icon. |
| `scripts/` | Runtime preparation, app packaging, installation helpers, release packaging and publication checks. |
| `docs/` | Current guides, audits, dated designs and engine-adoption evidence. |

For component interactions, read the [architecture guide](../how-it-works/architecture.md); for where new code goes, the [conventions](conventions.md); for end-to-end paths, the [flows](../how-it-works/flows.md). For the role of every individual file, use the [file catalog](file-map.md). Screenshots and demo placement are described in the [media guide](../media/README.md).

### Localization resources

SwiftPM processes the shared string catalog into `OortNX_OortLibrary.bundle` (`<package>_<library>`, from `architecture/names.json`). `build_app.sh` requires and copies that bundle into `Contents/Resources`, declares the seven supported app languages and validates the compiled strings/plurals before signing. `scripts/check_localizations.py --app <path.app>` verifies the same resources independently. Missing resources or placeholder mismatches fail packaging. Locale selection is independent from each game's DM_LANG setting.

### Isolated launcher-development data

`AppDataProfile` selects immutable roots from the explicit build marker, and `AppData` routes app-owned stores/default preferences through that policy. `DevelopmentStartupView` completes the background import before constructing app stores or the shell. A failure shows Retry/Close; it never opens a writable fallback on the release profile. A changed legacy library with a valid catalog also offers **Keep Arcane’s library**: it archives the catalog, backup and legacy inputs before acknowledging the changed fingerprint, keeping the catalog’s games and sources without merging older changes. `run_startup_recovery.py` exercises this coordinator using a synthetic profile without windows. The source is read directly, not through store load/recovery methods. A staged, hashed allowlist copy and preference import can resume after failure; a completed profile is never automatically reimported. Copied unfinished sessions end at their last recorded heartbeat.

After the import, `AppShellState` creates the view model and initial router and applies the initial locale/theme on the main actor before publishing the ready shell. Views retain these prepared objects; they do not run model startup or mutate shared theme state as SwiftUI inserts the shell into an already-visible window. Startup logs record only phase boundaries, without library contents or preference values.

The separate bundle IDs select separate standard preference domains. Do not open the app's own bundle ID with `UserDefaults(suiteName:)`: Foundation rejects that suite. Packaging runs `scripts/check_app_profile.swift` in a temporary headless app with the built Info.plist, exercising the real preferences accessor and profile roots without starting UI, running the importer or writing data. Ordinary unit-test hosts do not reproduce the packaged app's identity.

The Dev does not automatically import credentials or restore saves, reconcile app icons, install copied pending builds, sync real mod overlays, or sweep shared external staging. Explicit Dev icon/build requests are recorded in `DevelopmentOperationStore` and can resume on restart. When automatic mod maintenance is disabled, browsing reads the actual overlay without rewriting it or cleaning another profile's staging.

The isolation covers launcher data, not the physical game installations and their saves. Explicit Play, game settings, builds, save/mod actions and cleanup still refer to real resources. Do not describe this as a sandbox of all game effects. Release packaging excludes the development marker, and the updater rejects a release that also selects the development profile. Initial Dev import and native interaction remain awaiting maintainer validation.

Launch the packaged Dev for app checks: an unmarked executable cannot silently choose the stable data profile. Build markers and bundle identity must agree before the startup transaction opens any app store.
