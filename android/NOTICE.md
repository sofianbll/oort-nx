# Oort NX for Android: notices

Oort NX is MIT-licensed (see the repository's LICENSE and NOTICE). This file lists what the Android launcher
starts, what it ports from Oort NX for Mac, and the libraries it builds with. It copies no code from the projects
below; it starts the apps they produce and follows the conventions they document.

To add to the root NOTICE when this branch is merged (the root NOTICE is pinned by scripts/check_publication.py,
so it is left alone here):

```text
--------------------------------------------------------------------------------
shirai91/nx2android
https://github.com/shirai91/nx2android
Oort NX for Android lists and starts the apps nx2android makes (package names org.nx2a.*). No nx2android code
is included. nx2android is MIT-licensed: its README (section License) says "MIT, as nxnative (see
nxnative/LICENSE)", and nxnative/LICENSE reads "Copyright (c) 2026 seedds". nx2android has no LICENSE file at its
root; third-party code in it keeps its own license.

enjoyerofslop/droidplay-core
https://github.com/enjoyerofslop/droidplay-core
Read as a reference for how an Android launcher around nxnative is built (its docs/frontends.md and
docs/launcher.schema.json). No code is included. MIT, Copyright (c) 2026 seedds (its LICENSE). It names
RogelioLB/nxnative-android as the start of the Android port.
```

## From Oort NX for Mac (same project, MIT)

- `core/OortCloud.kt`: port of `OortCloudPoint.field()` and of the cloud's vertex shader (`MoonlightShaders.swift`).
- `core/OortSynth.kt`: port of `OortSynth.swift`; the four sound packs are synthesized, with no audio file.
- `core/DirectionRepeat.kt`, `core/PadShape.kt`: ports of OortCore's `DirectionRepeat` and `OortPadShape`.
- The launcher icon: the mark in `Resources/AppIcon.icon`, converted by `tools/make_icon.py`.
- `ui/OortTokens.kt`, `res/values/oort_colors.xml`: generated from `design/oort.tokens.json`.

Oort NX is maintained independently of Arcane by Bium23 (MIT, Copyright (c) 2026 bium), on which it is built.

## Libraries (not copied into this repository; those marked * are inside the APK)

| Library | License |
|---|---|
| Kotlin and kotlinx.coroutines (JetBrains) * | Apache-2.0 |
| AndroidX: Activity, Compose (UI, Foundation, Material 3) and what they need (Core, Lifecycle, Collection...) * | Apache-2.0 |
| Android Gradle plugin, Gradle | Apache-2.0 |
| JUnit 4 (tests only) | EPL-1.0 |

The full Apache-2.0 text, the MIT text of this repository and this file are in the app: Settings, Thanks and licences.

No font is bundled: the app uses the system's.

No Nintendo games, keys, fonts, sounds or other game assets are included. Oort NX is not affiliated with,
endorsed by, or sponsored by Nintendo.
