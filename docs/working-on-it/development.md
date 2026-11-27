# Development and releases

This guide covers building Oort NX itself. For app setup, game preparation and daily use, start with the [user guide](../../README.md). Read [AGENTS.md](../../AGENTS.md) before changing engine integration or installation behaviour.

## Development prerequisites

- An Apple-silicon Mac running macOS 26 or later.
- Full Xcode selected for the build. The current game toolchain requires Xcode 27.2 or later and the Metal compiler certified for the pinned engine. `Package.swift` declares Swift tools 6.0 (`OortCore`, `OortLibrary` and `NxnativeAdapter` build in the Swift 6 language mode, the app and the tests in Swift 5; in Swift 6 a block written inside a main-actor method stops the app when another queue runs it, so write such a block in a `nonisolated` helper) and macOS 26 as package minimums; those values do not certify an engine/compiler combination.
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

A development copy carries the version in progress from the `VERSION` file at the repository root and shows it as "(Dev · Launcher)" on this development line in Settings; it has no release marker, so it never offers or installs app updates. `scripts/release.sh <version>` sets the released version itself and refuses to run unless `VERSION` already says that version. After a release, raise `VERSION` to the next version being worked on.

An alternate destination can be supplied without replacing the installed development copy:

~~~sh
bash scripts/build_app.sh /tmp/Oort-NX-Review.app
~~~

A plain development app uses bundle ID `local.nxlibrary.development`, takes its version from `VERSION` and has no release marker. It never installs its own updates.
For an identifiable trial build, set `NX_DEV_COMMIT` to the full SHA of the clean checkout. The bundle records it and Settings → About shows its short form beside the build date.

Register a public PKCE application with Nextendo for `http://127.0.0.1:47823/callback`, with the engine's `identity`, `friends`, `game.matchmaking`, `presence` and `profil` scopes. Enter the public ID in Online services when the selected engine declares support. To package a default instead, optionally set `DM_NEXTENDO_CLIENT_ID` when running `build_app.sh`; it writes only the public ID to `DMNextendoClientID`. Do not supply a client secret.

`BuildCommandBuilder` adds `--nextendo` to `scripts/build_ipa_from_nsp.py` only when the selected checkout declares it and a valid public client ID is available (settings first, then Arcane's `Info.plist`). Only that command gets `DM_NEXTENDO_CLIENT_ID` in its environment; building does not check the player's session. The engine can reuse a valid cached patch catalog and can continue when a verified catalog has no patch for the exact game build. A fetch or verification failure fails the build; Arcane shows the engine error and does not retry without Nextendo. The engine pin is unchanged.

### Private Google Drive builds

Supply both `ARCANE_GOOGLE_CLIENT_ID` and `ARCANE_GOOGLE_CLIENT_SECRET` in the environment of `scripts/release.sh` (without `--publish`) or `scripts/build_app.sh`. Use a desktop OAuth client. If either variable is missing or blank, no Google client keys are added to `Info.plist`. These keys are readable by anyone with the app, ZIP or DMG: keep the artifacts private and don't run the scripts with shell tracing. `release.sh --publish` refuses either variable even if set to an empty string and checks that the built plist has neither key. Personal releases go to `work/release-private`, accept an existing version tag without changing it, and can lose the embedded client when a public update replaces the app.

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

`release.sh` runs the same `CatalogAppChecks/run_*.py` set after the Swift suite and stops if any check fails. These checks use synthetic inputs without opening windows. The Cloud screen checks with optional output paths use temporary directories by default. The downgrade comparison and download capture report a skip without their explicit inputs; the NUP engine-snapshot probe remains optional.

### Continuous integration

The [Checks workflow](../../.github/workflows/ci.yml) runs on both `main` pushes and pull requests, including forks. Its **Rules** job runs `scripts/check` on Linux in seconds; every build job waits for it. The Mac jobs use GitHub-hosted `xcode-27`, at most five at a time per account. The single **Checks** verdict requires the rules and, for Swift changes, the Swift unit suite with the shared application probes, every standalone probe batch, and the Release build. `swift test` already builds the Debug app, so the shared probes run in the same job on that build, then the Python tests run again on the Mac (`release.sh` needs macOS). CI runs at most two standalone package builds per runner. Each package starts from the SDK modules Swift Build precompiled for the same runner image and Xcode, kept in the Actions cache (`OORT_PROBE_MODULE_SEED`, see `build_probe`); the first build of an image fills it. The common build helper uses the runner home for Xcode mounts, then the probe binary runs with its isolated fixture home. Every `run_*.py` still runs and reports its timing.

Checkout is pinned and does not retain credentials. Permissions are read-only; the workflow needs no secrets, self-hosted runners, packaging or publishing. It does not run the UI or games or certify the engine. See the [runner measurements](../history/reviews/2026-11-26-mac-ci.md).

Standalone probes use a SHA-256-verified rclone release for the synthetic local transport. SwiftUI-only text checks read a companion PDF from the same offscreen renderer and prove each expected text visible from its pixels (`assertVisible`); the AppKit settings probe still reads its screenshots and uses CPU-only Tesseract in CI for the hidden windows. The OCR package lock and language files are test dependencies, not application dependencies (Tesseract and its language data: Apache-2.0; see the [npm wrapper](https://github.com/naptha/tesseract.js)). `workflow_dispatch` can exercise all jobs on an authorized fix branch without changing `main`.

### Manual checks

Interactive app and game checks are performed by the user. Agents must not use computer-use or other UI automation. Compilation, unit tests and signature verification cannot establish that the interface or a game works.

Before a game/toolchain combination is described as working, the user checks **Settings → Setup and engine**, builds a real game and launches it to a visible screen. Record the engine and Metal versions and whether the untested override was used.

## Engine upgrades

Never patch `~/nxnative` or follow its `main` branch automatically. The default pin is in `AppViewModel.defaultPinnedEngineCommit`; an explicit release pin supplies both the repository and commit. `ToolchainRequirements.current` describes the supported setup requirements and downloadable Metal assets.

An upgrade requires reviewing the upstream delta and CLI, deciding which capabilities to adopt, wiring applicable flags, updating certification data and verifying tests, the gate, a real build and a visible launch. Follow the [upgrade checklist](../history/engine-upgrades/README.md), write a dated note and update the README, design spec and changelog. A newer engine commit alone is not sufficient evidence.

## Release packaging

Use `scripts/release.sh` for releases. It requires a clean working tree, a `VERSION` file that names the release and a runtime that matches the lock. It tests the exact engine pin shipped in the bundle in an anonymous temporary checkout and runs the publication checks before packaging. An unavailable pin fails the release. Commit or deliberately stash local work first; do not discard changes to satisfy the check.

Publication normally requires an unused tag. If the tag was pushed but the release is absent, run the same publish command again: it accepts only identical local and remote tag objects that resolve to the published release commit. An existing release (including a draft) or an unverified release list stops the script. This does not move or re-push the tag.

With `--publish`, the effective `origin` push URL must point to the one public GitHub repository resolved from the updater source. The script reads `main` and the version tag directly in that repository, not from the fetch URL or a cached tracking ref. It requires `HEAD` to match that `main`, the version tag to be unused locally and remotely, and the engine pin to be reachable from a public branch. It checks again after packaging, pushes only that tag, and verifies its commit before asking GitHub to create the release in the same repository. If the tag push or release upload fails, check the remote tag and release state before retrying.

The release DMG uses the Oort artwork by default. Set up its build-only Python
tools once in a virtual environment outside the repository:

```bash
dmg_env="$(mktemp -d "${TMPDIR:-/tmp}/oort-dmg-tools.XXXXXX")"
python3 -m venv "$dmg_env"
"$dmg_env/bin/python" -m pip install --require-hashes --only-binary=:all: -r scripts/dmg-requirements.txt
export OORT_DMG_PYTHON="$dmg_env/bin/python"
```

[dmgbuild](https://github.com/dmgbuild/dmgbuild), [ds_store](https://github.com/dmgbuild/ds_store) and [mac_alias](https://github.com/dmgbuild/mac_alias) (both MIT) are not included in the app or installer. The DMG step works offline after setup and needs Xcode's Swift and SetFile. `diskutil image create from` drops the canonical spelling `.DS_Store` when copying a folder on macOS 27; the builder stages it as `.ds_store` and verifies its contents at the canonical path on the case-insensitive APFS volume.

For example, to prepare a later release locally:

~~~sh
bash scripts/release.sh 0.1.2
~~~

The script builds a release-marked app, verifies its version and signature, and produces a ZIP and DMG in `work/release/`. Without `--publish`, it does not push a tag or create a GitHub release. Version `0.1.0` is the first public alpha; use an unused version for later releases.

To package an app you have already built, run `bash scripts/build_dmg.sh /path/to/Oort\ NX.app`; it writes `dist/Oort NX.dmg` only after verifying the app in a hidden, read-only mount. Use `build_dmg.sh --plain` (or `release.sh <version> --plain-dmg`) to make the original unstyled installer without the Python tools. Missing tools do not silently change the style.

Platform SVGs, generic Lucide fallbacks and notices live in `design/Brands/Platforms`.
Publication checks verify reviewed hashes and reject extra brand files. Only the two Switch platform symbols are an exception to the Nintendo artwork rule.

Publishing requires an explicit maintainer decision and the script's `--publish --notes <file>` options. Prepare reviewed notes from [CHANGELOG.md](../../CHANGELOG.md), then date the version when it is actually published. The script adds engine/Xcode requirement metadata to release notes for the updater. Never publish automatically as part of an agent's verification.

### Publication perso (Sofian)

Oort NX utilise son propre `MAJOR.MINOR.PATCH` : **PATCH** pour les correctifs seuls, **MINOR** pour les nouveautés compatibles et **MAJOR** pour les changements incompatibles. La base amont (« basé sur Arcane 0.2.1 ») figure dans les notes et dans À propos, jamais dans le numéro. Les anciennes releases `0.2.1.2026112x` conservent leurs versions et leurs tags ; l’updater les reconnaît toujours.

1. Choisir un commit **testé** du fork moteur, accessible depuis une branche publique. Après accord, poser le tag moteur `oort-vX.Y.Z` sur ce SHA exact ; Oort NX épingle le SHA, pas le tag. Pour `0.3.0` :

   ~~~sh
   git -C ~/Games/Switch/Engine tag oort-v0.3.0 46612553ee409a7f42549d0533cb76655e72cd77
   git -C ~/Games/Switch/Engine push https://github.com/sofianbll/nxnative refs/tags/oort-v0.3.0
   ~~~

2. Dans le dépôt du lanceur, inscrire `0.3.0` dans `VERSION`, préparer les notes à partir du [modèle FR](perso-release-notes.md), valider et commiter sur un arbre propre. Préparer `work/Runtime` avec `scripts/bundle_runtime.sh`, puis vérifier ZIP, DMG et plist sans publier :

   ~~~sh
   DM_NEXTENDO_CLIENT_ID="$YOUR_PUBLIC_NEXTENDO_CLIENT_ID" bash scripts/release.sh 0.3.0 \
     --engine-repo https://github.com/sofianbll/nxnative \
     --engine-commit 46612553ee409a7f42549d0533cb76655e72cd77
   ~~~

   Pour la publication perso, passer `DM_NEXTENDO_CLIENT_ID="$YOUR_PUBLIC_NEXTENDO_CLIENT_ID"` aux deux commandes : le build inscrit cet identifiant public dans `DMNextendoClientID` dans le plist de l’app. Ne pas fournir de secret Nextendo. Le script refuse un SHA qui n'est pas accessible depuis une branche du dépôt. Sans les deux options moteur, la build conserve le dépôt et le pin amont.

3. Après validation et accord de publication, placer le commit de release sur `main` dans le dépôt public et refaire la même build avec les notes approuvées. Depuis 0.4.0, le script vise `sofianbll/oort-nx`. L’envoi d’`origin` doit viser ce même dépôt pour le tag `vX.Y.Z` et la release. Pour 0.4.0 seulement, publier ensuite les mêmes fichiers et le même tag dans `sofianbll/NxLibrary` : les copies jusqu’à 0.3.0 y cherchent leur mise à jour. Les notes peuvent rester hors du dépôt ; le script y ajoute le dépôt et le SHA embarqués et les métadonnées Xcode/moteur.

   ~~~sh
   DM_NEXTENDO_CLIENT_ID="$YOUR_PUBLIC_NEXTENDO_CLIENT_ID" bash scripts/release.sh 0.3.0 \
     --engine-repo https://github.com/sofianbll/nxnative \
     --engine-commit 46612553ee409a7f42549d0533cb76655e72cd77 \
     --publish --notes "$HOME/oort-nx-0.3.0.md"
   ~~~

4. Le pote qui utilise déjà une **release du fork** voit la version et ses notes dans **Settings → About → Check now** (ou à l'ouverture si le contrôle automatique est dû). Une copie Dev ou une release Bium23 ne bascule pas sur le fork : première installation depuis le DMG du fork. Après le redémarrage, **Setup** propose de cloner, mettre à jour ou basculer vers le moteur épinglé. Les jeux existants restent jouables ; recompiler les titres indiqués dans les notes pour appliquer les changements moteur. Le bouton **Upstream** compare toujours à `seedds/nxnative` `main`.

### Distribution work still open

The first public alpha uses the existing `local.nxlibrary` bundle identity and ad-hoc signing, without notarisation. Developer ID distribution will need signing-identity verification and notarisation. Updates verify GitHub's SHA-256 digest and the sealed app signature; ad-hoc signatures do not independently identify the publisher.

From 0.4.0 the updater uses `sofianbll/oort-nx` directly, with anonymous public access. Copies up to 0.3.0 check `sofianbll/NxLibrary`, where the same files of 0.4.0 are published. No separate download repository or login is needed for users. Release copies update themselves; source builds remain excluded. `release.sh --publish` requires the configured repository to be public. ZIP downloads are limited to 512 MiB, restricted to GitHub's HTTPS download hosts and checked against the published size and digest. The bundled Python checks paths, symlinks, duplicates, special files and a 30,000-entry limit, then extracts using bounded raw decompression with a 2 GiB total limit. It verifies actual output size and CRC rather than trusting ZIP size fields. Release packaging uses this same extraction path and verifies the extracted bundle signature; ZIPs omit Finder metadata sidecars.

### First installation and A → B update test

Validate installation from the published DMG and replacement of an installed release. Keep the same bundle ID and data paths between versions. Engine upgrades additionally follow the [upgrade checklist](../history/engine-upgrades/README.md).

1. Download release A's DMG from GitHub, install normally, eject the DMG and complete Setup. Check that the installation folder is writable; updates must not change permissions silently.
2. Build and launch one supported game using the user's own files. Save progress, set a favourite and change one preference. Create a save backup, then close the game and app.
3. Prepare B with a higher numeric version and clear test notes, keeping the same bundle ID, data paths and engine pin. No artificial feature is required to exercise replacement.
4. Publish B through `scripts/release.sh`, then open the installed A. Automatic checks run at most once per 24 hours; use **Settings → About → Check now** for an immediate check. The manual check exposes availability in About; the launch popup is a separate check after the interval.
5. Update from inside A. Verify B reopens, reports its version and retains the library, favourite, preference, keys, backups and game progress. Test the automatic launch offer separately. Record actual results; compilation does not establish that this interactive flow worked.

The updater reads `releases/latest`, which excludes draft and prerelease entries. A copy running a pre-release reads the release list instead, so a beta finds the next beta. Keep both A's DMG and ZIP when preparing B: `release.sh` replaces its local `work/release` output. Do not alter the Mac's clock to exercise the interval.

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
