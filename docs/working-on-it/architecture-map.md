# Architecture map

This page says where each kind of code lives, for the five systems, and which imports are allowed. Check the import rules with `python3 scripts/check_module_boundaries.py`. The tests are in `Tests/ModuleChecks`.

For how each area behaves, read [architecture](../how-it-works/architecture.md). For the recipe to add a kind of code, read [conventions](conventions.md).

## The five systems

| System | Folder | Built with | Status |
|---|---|---|---|
| macOS app | `Sources/NXLibrary`, `Sources/NXLibraryCore`, `Sources/ArcanePorting`, `Sources/OortCore` | Swift, SwiftUI, AppKit | `main`, the main product |
| Windows and Linux | `desktop/` (Tauri host, Rust) and `oort-core` (Swift, portable subset) | Swift, Rust, web page | `alpha/windows` |
| Android | `android/` (Kotlin, Gradle) | Kotlin, Compose | `alpha/android` |
| iPhone and iPad | `mobile/` (Swift package and app) | Swift, SwiftUI, UIKit shell | `alpha/ios` |
| Engine | nxnative, external, pinned by URL and commit | Python, its own toolchain | Not in this repository |

The engine is never copied in. The app reaches it through the adapter in `Sources/ArcanePorting`, and the other systems reach it through their own adapters. See the [engine rules](../how-it-works/architecture.md).

## Layers on macOS

Imports go one way only. A module may import the layers below it.

~~~text
NXLibrary        (layer 3)  app shell, views, view models, Selene, window and pad input
   |
ArcanePorting    (layer 2)  nxnative adapter: setup, build, launch, saves, mods, cloud, Mac paths
   |
NXLibraryCore    (layer 1)  shared rules: catalog, library, settings, artwork, achievements, Steam
   |
OortCore         (layer 0)  portable pure logic, Foundation only
~~~

Measured on `bf0c3410`:

| Module | Swift files | Tests target | Imports checked |
|---|---:|---|---|
| OortCore | 9 | `OortCoreTests` | Foundation only. Zero exceptions |
| NXLibraryCore | 172 | `NXLibraryCoreTests` | Imports `OortCore` in 2 files. Interface imports: 2 files on the baseline |
| ArcanePorting | 162 | `ArcanePortingTests` | Imports `NXLibraryCore`; may use AppKit, GameController and IOKit |
| NXLibrary | 297 (219 in `Views/`, 44 in `ViewModels/`) | none | Imports every layer below it |

## Rules checked by script

1. **OortCore imports Foundation only.** A new Apple framework in this module fails the check.
2. **Layer order.** A module imports only the modules below it. For example, `NXLibraryCore` may not import `NXLibrary`.
3. **No interface framework in the core.** `OortCore` and `NXLibraryCore` may not import AppKit, SwiftUI, Metal, MetalKit or GameController.
   - Two files are on the baseline, and the baseline can only shrink: `Sources/NXLibraryCore/Selene/Motion.swift` (SwiftUI) and `Sources/NXLibraryCore/Artwork/ArtworkStore.swift` (AppKit).
   - When one of them stops importing the framework, the check reports the stale entry, and the entry is removed in the same change.

The check reads imports, not the build graph. A transitive import through another module is still caught, because each module's own files are read.

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

- **Windows and Linux (`desktop/`).** The Swift `oort-core` executable is built from `OortCore` and the portable part of `NXLibraryCore`. The Tauri host and the web page live in `desktop/`. The page is generated: change its source, then run `python3 desktop/scripts/generate.py`, and check with `--check`.
- **Android (`android/`).** Kotlin code with its own core under `core/` and screens under `ui/`. Its numbers for the cloud, sounds and pad must match the Mac's own output. `Tests/AndroidChecks` and `android/tools/verify_cloud.py` hold that check.
- **iPhone and iPad (`mobile/`).** A Swift package that depends on `OortCore`. The app target and the capture target are separate.

The portable rules are the reason for `OortCore`. Before a shared rule is added there, check that every system needs it, and that the fixture in its tests is synthetic.

## Checks that keep the map true

| Check | Command | Where it runs |
|---|---|---|
| Module boundaries | `python3 scripts/check_module_boundaries.py` | CI, always, on macOS |
| Boundary tests | `python3 -m unittest discover -s Tests/ModuleChecks` | CI, always |
| Which CI areas run | `python3 -m unittest discover -s Tests/CIChecks` | CI, always |
| Public skills | `python3 -m unittest discover -s Tests/SkillChecks` | CI, always |
| Portable core imports (Windows and Linux) | `python3 scripts/check_portable_core.py` | `alpha/windows` |

Update this page in the same change as any new module, any new folder under `Sources/`, or any rule above.
