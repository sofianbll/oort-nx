# Architecture map

The [LikeC4 model](../../architecture/model.c4) describes the systems, modules and domain ownership. Its [three views](../../architecture/views.c4) show the same model at different scales. Swift import layers are read directly from its `layer` metadata by `python3 scripts/check_module_boundaries.py`.

For how each area behaves, read [architecture](../how-it-works/architecture.md). For the recipe to add a kind of code, read [conventions](conventions.md).

## Rules checked by script

1. **OortCore imports Foundation only.** A new Apple framework in this module fails the check.
2. **Layer order.** A module imports only the modules below it. For example, `NXLibraryCore` may not import `NXLibrary`.
3. **No interface framework in the core.** `OortCore` and `NXLibraryCore` may not import AppKit, SwiftUI, Metal, MetalKit or GameController.
   - Two files are on the baseline, and the baseline can only shrink: `Sources/NXLibraryCore/Selene/Motion.swift` (SwiftUI) and `Sources/NXLibraryCore/Artwork/ArtworkStore.swift` (AppKit).
   - When one of them stops importing the framework, the check reports the stale entry, and the entry is removed in the same change.

The check compares `swiftModule` declarations with the regular and executable targets returned by `swift package dump-package`. It reads actual source imports, not the build graph.

## Where new code goes

| The code… | Goes in | Example |
|---|---|---|
| Is pure logic with no Apple framework, and is shared by every system | `OortCore` | version numbers, focus index, hold detector |
| Describes the catalog, library, settings, artwork or achievements | `NXLibraryCore` | a catalog record, a library filter, a settings key |
| Talks to nxnative, the engine, Steam files, rclone, Keychain, or Mac paths for a game | `ArcanePorting` | a build step, a save transaction, a cloud archive |
| Draws a view, handles a window, a focus or the pad, or plays a sound | `NXLibrary` | a screen, a Selene component, a controller binding |
| Is needed by the Windows and Linux core | `OortCore`, or `NXLibraryCore` files listed in `Package.swift` | the portable subset |

When unsure, put the code in the lowest layer that does not need a higher one. Moving code down is cheap. Moving it up, or importing up, is what the check blocks.

## Other systems

- **Windows and Linux (`desktop/`).** The page is generated: change its source, then run `python3 desktop/scripts/generate.py`, and check with `--check`.
- **Android (`android/`).** Put core code under `core/` and screens under `ui/`. Its numbers for the cloud, sounds and pad must match the Mac's own output. `Tests/AndroidChecks` and `android/tools/verify_cloud.py` hold that check.
- **iPhone and iPad (`mobile/`).** The app target and the capture target are separate.

The portable rules are the reason for `OortCore`. Before a shared rule is added there, check that every system needs it, and that the fixture in its tests is synthetic.

## Checks that keep the map true

| Check | Command | Where it runs |
|---|---|---|
| Module boundaries | `python3 scripts/check_module_boundaries.py` | CI, always, on macOS |
| Boundary tests | `python3 -m unittest discover -s Tests/ModuleChecks` | CI, always |
| Which CI areas run | `python3 -m unittest discover -s Tests/CIChecks` | CI, always |
| Public skills | `python3 -m unittest discover -s Tests/SkillChecks` | CI, always |
| Portable core imports (Windows and Linux) | `python3 scripts/check_portable_core.py` | `alpha/windows` |

Update `architecture/model.c4` when a system, module or domain boundary changes. Keep the `swiftModule` identifier and its `metadata { layer "…" }` on one line. Validate the model with LikeC4; Node is not needed for the Swift check.
