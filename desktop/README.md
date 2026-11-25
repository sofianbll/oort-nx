# Oort NX for Windows and Linux

The same library as on the Mac, for games that already run on these systems: recompilations with a `recomplauncher.json`, any program with its arguments, and the games Steam installed. It downloads and installs no game and has no account. It sends nothing unless the player turns on game information online.

| Part | Where | What |
|---|---|---|
| Logic | `Sources/OortCompanion`, `Sources/oort-core` (Swift 6) | Library, settings, profiles, manifests, programs' icons and names, Steam's lists, what to ask online, launch plans, sounds. See [PROTOCOL.md](PROTOCOL.md) |
| Host | `src-tauri` (Rust, Tauri 2) | The window, the controller, starting and following processes (`steam.rs` for what Steam starts), reading public addresses when asked (`online.rs`), packaging |
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
| `tests/windows/prove.ps1` | Silent install, the installed app driven through WebView2's debugging port (`drive.mjs`: the scripts of `desktop/tests`, `windows.js`), the real window and keys (`Desk.cs`), games made of `FakeGame.cs`, an update from the published alpha.1, an invented Steam (`FakeSteam.cs`, the registry, two drives), invented services on this computer (`tests/online.mjs`) and the ways they fail, a second install, uninstall |
| `tests/linux/prove.sh` | The .deb and the AppImage on a virtual screen, real keys, the first steps, a followed game, a game an invented Steam starts |
| `scripts/runtime_windows.py` | The libraries that travel with the core, and a check that none is missing |
| `scripts/licenses.py --texts`, `scripts/licenses_linux.py` | Licence texts of the Rust libraries of each package, and of the Debian libraries an AppImage carries |

`desktop/tests/*.js` also walk the real window on a Mac (debug build) with invented games made by `desktop/scripts/fixtures.py`: `OORT_RUN=<folder> OORT_APP=<binary> desktop/tests/run.sh walk.js <pictures> 1440x900`.

`OORT_DATA=<folder>` keeps everything the app writes in one folder. `OORT_ONLINE=http://127.0.0.1:<port>` answers online questions from this computer, and only from it; the proofs never use a network.

Credits: [NOTICE](NOTICE). Padwake by ddoinn (MIT) for following a game's processes on Windows; RecompLauncher SDK by Ripalda (MIT) for the format.

## What is read, written and sent

| | |
|---|---|
| Read | The folders and programs the player added: manifests, a program's own icon and name (`ProgramFile.swift`, the file is never run for it). Steam's folder when it is on: `libraryfolders.vdf`, `appmanifest_*.acf`, `appinfo.vdf`, its picture cache |
| Written | The app's own folder; the settings files games declare. Never in Steam's folders |
| Sent | Nothing, until the player turns on game information online. Then the game's name or its Steam number, and the language, to the Steam store, Wikidata and Wikipedia (https, no key, no cookie): `Online.swift` names the addresses, `online.rs` checks them again, one at a time, with limits of time and size |
