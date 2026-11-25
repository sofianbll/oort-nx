# Oort NX for Windows and Linux

The same library as on the Mac, for games that already run on these systems: recompilations with a `recomplauncher.json`, and any program with its arguments. It downloads and installs no game, has no account, and sends nothing.

| Part | Where | What |
|---|---|---|
| Logic | `Sources/OortCompanion`, `Sources/oort-core` (Swift 6) | Library, settings, profiles, manifests, launch plans, sounds. See [PROTOCOL.md](PROTOCOL.md) |
| Host | `src-tauri` (Rust, Tauri 2) | The window, the controller, starting and following processes, packaging |
| Interface | `ui` (no framework) | The screens, from the site's pieces |
| Generated | `ui/gen` | Tokens and palettes from `design/oort.tokens.json`, texts from `Localizable.xcstrings`, known game setting names from `game-words.json`: `python3 desktop/scripts/generate.py` |

```
desktop/scripts/core.sh                     # build oort-core, put it beside the app
cd desktop/src-tauri && cargo run           # the window
cargo test                                  # host
node --test desktop/tests/nav.test.mjs      # page
OORT_PORTABLE=1 swift test --filter OortCompanionTests
```

`.github/workflows/desktop.yml` builds the packages, then proves them on machines without Swift or Rust:

| Where | What |
|---|---|
| `tests/windows/prove.ps1` | Silent install, the installed app driven through WebView2's debugging port (`drive.mjs`: the scripts of `desktop/tests`, `windows.js`), the real window and keys (`Desk.cs`), games made of `FakeGame.cs`, a second install, uninstall |
| `tests/linux/prove.sh` | The .deb and the AppImage on a virtual screen, real keys, a followed game |
| `scripts/runtime_windows.py` | The libraries that travel with the core, and a check that none is missing |
| `scripts/licenses.py --texts` | The Rust libraries' licence texts, made for each package |

`desktop/tests/*.js` also walk the real window on a Mac (debug build) with invented games made by `desktop/scripts/fixtures.py`: `OORT_RUN=<folder> OORT_APP=<binary> desktop/tests/run.sh walk.js <pictures> 1440x900`.

`OORT_DATA=<folder>` keeps everything the app writes in one folder.

Credits: [NOTICE](NOTICE). Padwake by ddoinn (MIT) for following a game's processes on Windows; RecompLauncher SDK by Ripalda (MIT) for the format.
