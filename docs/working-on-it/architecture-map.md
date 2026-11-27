# Architecture map

The [LikeC4 model](../../architecture/model.c4) describes the systems, modules and domain ownership. Its [views](../../architecture/views.c4) show three scales of the same model and one short Play sequence; [structure.c4](../../architecture/structure.c4) shows the repository's folders. Swift import layers come from its `layer` metadata.

For how each area behaves, read [architecture](../how-it-works/architecture.md). For the recipe to add a kind of code, read [conventions](conventions.md).

## Work in LikeC4

From the repository root, run:

```sh
npx --yes --package=node@22.23.3 --package=likec4@1.61.1 likec4 serve architecture --listen 127.0.0.1 --port 4173 --theme dark --no-build-webcomponent
```

Open [127.0.0.1:4173](http://127.0.0.1:4173/). In **Écosystème**, use the navigation arrow on **Mac**, then on **Interface moteur** to see **Qui possède quoi ?**. Edit the `.c4` source in your editor; the preview reloads. Stop with Ctrl+C.

In [OpenChamber → Settings → Projects → Project Actions](https://docs.openchamber.dev/project-actions/#add-an-action), add **LikeC4** with the command above; leave it running from the session folder (the current worktree), and set its URL to `http://127.0.0.1:4173/`. The action is not required to use LikeC4.

### Optional MCP for OpenCode

The [LikeC4 MCP server](https://likec4.dev/tooling/ai-tools/#mcp-server) queries the model's elements, dependencies and views without rewriting `.c4` files. In a project-local [OpenCode v2 config](https://opencode.ai/docs/mcp-servers#local), merge this entry if you want it. It is independent of the web preview.

```json
{
  "mcp": {
    "servers": {
      "likec4": {
        "type": "local",
        "command": ["npx", "--yes", "--package=node@22.23.3", "--package=likec4@1.61.1", "likec4", "mcp", "--stdio", "architecture"]
      }
    }
  }
}
```

## Rules checked by script

1. **OortCore imports Foundation only.** A new Apple framework in this module fails the check.
2. **Layer order.** A module imports only the modules below it. For example, `OortLibrary` may not import `NXLibrary`.
3. **No interface framework in the core.** `OortCore` and `OortLibrary` may not import AppKit, SwiftUI, Metal, MetalKit or GameController.
   - Two files are on the baseline, and the baseline can only shrink: `core/OortLibrary/Selene/Motion.swift` (SwiftUI) and `core/OortLibrary/Artwork/ArtworkStore.swift` (AppKit).
   - When one of them stops importing the framework, the check reports the stale entry, and the entry is removed in the same change.

The check compares `swiftModule` declarations with the regular and executable targets returned by `swift package dump-package`. It reads actual source imports, not the build graph.

## Where new code goes

| The code… | Goes in | Example |
|---|---|---|
| Is pure logic with no Apple framework, and is shared by every system | `OortCore` | version numbers, focus index, hold detector |
| Describes the catalog, library, settings, artwork or achievements | `OortLibrary` | a catalog record, a library filter, a settings key |
| Talks to nxnative, the engine, Steam files, rclone, Keychain, or Mac paths for a game | `NxnativeAdapter` | a build step, a save transaction, a cloud archive |
| Draws a view, handles a window, a focus or the pad, or plays a sound | `NXLibrary` | a screen, a Selene component, a controller binding |
| Is needed by the Windows and Linux core | `OortCore`, or `OortLibrary` files listed in `Package.swift` | the portable subset |

When unsure, put the code in the lowest layer that does not need a higher one. Moving code down is cheap. Moving it up, or importing up, is what the check blocks.

## Other systems

- **Windows and Linux (`desktop/`).** The page is generated: change its source, then run `python3 desktop/scripts/generate.py`, and check with `--check`.
- **Android (`android/`).** Put core code under `core/` and screens under `ui/`. Its numbers for the cloud, sounds and pad must match the Mac's own output. `Tests/AndroidChecks` and `android/tools/verify_cloud.py` hold that check.
- **iPhone and iPad (`mobile/`).** The app target and the capture target are separate.

The portable rules are the reason for `OortCore`. Before a shared rule is added there, check that every system needs it, and that the fixture in its tests is synthetic.

## Checks that keep the map true

`architecture/structure.c4` declares every root file and first- and second-level folder, and which folders may hold documentation; `scripts/check` refuses anything undeclared (`structure`, `docs`) and holds Swift imports to `architecture/model.c4` (`boundaries`). `scripts/check --list` names the tests of each rule. On `alpha/windows`, `scripts/check_portable_core.py` also keeps the portable core free of Apple imports, until that app joins `main`.

Update `architecture/model.c4` in the same change as a changed system, module or domain boundary. Keep the `swiftModule` identifier and its `metadata { layer "…" }` on one line. Run `npx --yes --package=node@22.23.3 --package=likec4@1.61.1 likec4 validate --max-warnings 0 architecture` and the Swift boundary check: the first verifies the model, the second checks Swift against it and does not need Node. Check navigability and labels in the live preview when a view changes.

For the two detail views, use one question as the title, at most seven boxes, short labels in the player's vocabulary, and no crossed arrows. Filter the view, not the model; link to another view if more detail is needed.

The engine view shows a request through the interface, not a module dependency: on Mac, `EngineAdapter` reads engine state through `MacNXNative`. It does not trigger launch or preparation. The dashed PC path shows the intended integration, not current behavior.
