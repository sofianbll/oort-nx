# Oort NX for Windows and Linux

The same library as on the Mac, for games that already run on these systems: recompilations with a `recomplauncher.json`, and any program with its arguments. It downloads and installs no game, has no account, and sends nothing.

| Part | Where | What |
|---|---|---|
| Logic | `Sources/OortCompanion`, `Sources/oort-core` (Swift 6) | Library, settings, profiles, manifests, launch plans, sounds. See [PROTOCOL.md](PROTOCOL.md) |
| Host | `src-tauri` (Rust, Tauri 2) | The window, the controller, starting and following processes, packaging |
| Interface | `ui` (no framework) | The screens, from the site's pieces |
| Generated | `ui/gen` | Tokens and palettes from `design/oort.tokens.json`, texts from `Localizable.xcstrings`: `python3 desktop/scripts/generate.py` |

```
desktop/scripts/core.sh                     # build oort-core, put it beside the app
cd desktop/src-tauri && cargo run           # the window
cargo test                                  # host
node --test desktop/tests/nav.test.mjs      # page
OORT_PORTABLE=1 swift test --filter OortCompanionTests
```

`desktop/tests/*.js` walk the real window on a Mac (debug build) with invented games made by `desktop/scripts/fixtures.py`: `OORT_RUN=<folder> OORT_APP=<binary> desktop/tests/run.sh walk.js <pictures> 1440x900`.

`OORT_DATA=<folder>` keeps everything the app writes in one folder.

Credits: [NOTICE](NOTICE). Padwake by ddoinn (MIT) for following a game's processes on Windows; RecompLauncher SDK by Ripalda (MIT) for the format.
