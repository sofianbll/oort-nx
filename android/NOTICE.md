# Oort NX for Android: notices

Oort NX is MIT-licensed (see the repository's LICENSE and NOTICE). This file lists what the Android launcher
starts, what it ports from Oort NX for Mac, and the libraries it builds with. It copies no code from the projects
below; it starts the apps they produce and follows the conventions they document.

## Projects it follows

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

<!-- BEGIN GENERATED CREDITS (design/credits.json, scripts/generate_credits.py) -->
## Every credit

The same list as in the app’s settings and on the site. The licence texts are in this file, in LICENSE and in
the folders it names; a project whose code is not in the app keeps its own licence where it lives.

Built on
- Arcane, by Bium23. The app Oort NX is built on. MIT. Code adapted (Mac, Windows, Linux, iPhone and iPad, Android, site). https://github.com/Bium23/NxLibrary
- Selene, by Matthew Silva. The theme its interface, palettes and first sounds come from. MIT. Code adapted (Mac, Windows, Linux, iPhone and iPad, Android, site). https://github.com/mattxslv/Selene
- Playnite, by Josef Nemec. Inspired the artwork picker; no code taken. MIT. Reference, no code in the app (Mac, site). https://github.com/JosefNemec/Playnite
- nxnative, by seedds. The engine for Switch games. MIT. In the engine, which is downloaded separately (Mac, Windows, Linux, iPhone and iPad, Android, site). https://github.com/seedds/nxnative
- NX2Apple, by LNPANDY. Adapted diagnostics; games on iPhone. MIT. Code adapted (Mac, iPhone and iPad, site). https://github.com/LNPANDY/NX2Apple
- Nextendo, by eyasbzour. Optional online play. MIT. Service, off until used (Mac, site). https://github.com/eyasbzour/nxnative-online

Projects
- nxnative_Launcher, by rennan101. The first interface the app started from. MIT. Code adapted (Mac). https://github.com/sofianbll/oort-nx/blob/main/NOTICE
- LumaNX, by Xc1Ym. Method for bundling the build tools, followed. MIT. Reference, no code in the app (Mac). https://github.com/Xc1Ym/LumaNX
- LASRecomp, by Peiikai. Save format facts, for achievements. MIT. Reference, no code in the app (Mac). https://github.com/peiikai/LASRecomp
- Padwake, by ddoinn. Follows a game’s processes on Windows. MIT. Code adapted (Windows). https://github.com/ddoinn/padwake
- RecompLauncher SDK, by Ripalda. The recomplauncher.json format. MIT. Reference, no code in the app (Windows, Linux). https://github.com/elripalda/RecompLauncher-SDK
- nx2android, by shirai91. Makes the Android games Oort NX starts; no code included. MIT. Reference, no code in the app (Android). https://github.com/shirai91/nx2android
- DroidPlay Core, by enjoyerofslop. Reference for an Android launcher; no code included. MIT. Reference, no code in the app (Android). https://github.com/enjoyerofslop/droidplay-core

Engine
- d2r-mobile, by jhaizhou. Where native execution began. MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/jhaizhou-ops/d2r-mobile
- Ryujinx, by Ryujinx Team. Maxwell shader translator and SPIR-V generator. MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/seedds/nxnative/tree/main/dm/third_party/ryujinx
- .NET, by .NET Foundation. Part of the shader translator and file reader. MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/dotnet/runtime
- Gommon, by Evan Husted (GreemDev). Part of the shader translator and file reader. MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/GreemDev/Gommon
- Humanizer, by .NET Foundation. Part of the shader translator and file reader. MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/Humanizr/Humanizer
- MessagePack for CLI, by FUJIWARA, Yusuke. Part of the shader translator and file reader. Apache-2.0. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/msgpack/msgpack-cli
- RecyclableMemoryStream, by Microsoft. Part of the shader translator and file reader. MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/microsoft/Microsoft.IO.RecyclableMemoryStream
- Atmosphère, by Atmosphère-NX. Mesosphère kernel synchronization semantics. GPL-2.0-only. Reference, no code in the app (Mac, iPhone and iPad, Android). https://github.com/Atmosphere-NX/Atmosphere
- LibHac, by Alex Barney. NSP reading and PFS/HFS layered filesystem. BSD-3-Clause. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/seedds/nxnative/tree/main/dm/tools/nx_extract
- SPIRV-Cross, by Khronos Group. SPIRV-Cross Metal Shading Language compiler. Apache-2.0. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/KhronosGroup/SPIRV-Cross
- dav1d, by VideoLAN. Decodes the movies of games. BSD-2-Clause. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://code.videolan.org/videolan/dav1d
- libvpx, by The WebM Project. Decodes the movies of games. BSD-3-Clause. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://chromium.googlesource.com/webm/libvpx
- stb_vorbis, by Sean Barrett. Decodes the sound of those movies. MIT OR Unlicense. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/nothings/stb
- Vulkan-Headers, by Khronos Group. Headers of the graphics interface. Apache-2.0 OR MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/KhronosGroup/Vulkan-Headers
- nvn.h, by h1k421. Headers of the graphics interface. MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/seedds/nxnative/blob/main/dm/gfx/nvn/include/nvn.h
- deko3d, by fincs. Texture layout calculation, ported. Zlib. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/devkitPro/deko3d
- MacNativeGames, by ly05010419 and contributors. Graphics code, adapted. MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/ly05010419/MacNativeGames
- MonZaMac, by Peiikai, lucabravi. Graphics code, adapted. MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/lucabravi/MonZaMac
- Touchline23, by ohxiaoguang. Graphics code, adapted. MIT. In the engine, which is downloaded separately (Mac, iPhone and iPad, Android). https://github.com/ohxiaoguang/touchline23
- OpenSSL, by The OpenSSL Project. Cryptography. Apache-2.0. In the engine, which is downloaded separately (Mac, iPhone and iPad). https://www.openssl.org
- FLIP, by NVIDIA. Compares images in the engine’s checks. BSD-3-Clause. In the engine, which is downloaded separately (Mac). https://github.com/NVlabs/flip

Tools
- CPython, by Python Software Foundation. Runs the engine’s build tools. PSF-2.0. In the app (Mac). https://www.python.org
  Includes bzip2, libffi, Expat, mpdecimal, libuuid, OpenSSL, SQLite, liblzma, zstd, Tcl/Tk, Itcl, Thread, LibTomMath, zlib.
- python-build-standalone, by Astral. Runs the engine’s build tools. MPL-2.0. Used to make the app (Mac). https://github.com/astral-sh/python-build-standalone
- capstone, by Nguyen Anh Quynh. Python library of the build tools. BSD-3-Clause AND NCSA. In the app (Mac). https://pypi.org/project/capstone
- python-lz4, by Jonathan Underwood. Python library of the build tools. BSD-3-Clause AND BSD-2-Clause. In the app (Mac). https://pypi.org/project/lz4
- fontTools, by Just van Rossum. Python library of the build tools. MIT. In the app (Mac). https://pypi.org/project/fonttools
- zbic, by Yannik Marchand (kinnay). Python library of the build tools. GPL-2.0-only. In the app (Mac). https://github.com/kinnay/zbic
- nsz, by Nico Bosshard, Blake Warner. Python library of the build tools. MIT. In the app (Mac). https://github.com/nicoboss/nsz
- pycryptodome, by Helder Eijs. Python library of the build tools. BSD-2-Clause AND Unlicense. In the app (Mac). https://pypi.org/project/pycryptodome
- python-zstandard, by Gregory Szorc. Python library of the build tools. BSD-3-Clause. In the app (Mac). https://pypi.org/project/zstandard
- Enlighten, by Avram Lubkin. Python library of the build tools. MPL-2.0. In the app (Mac). https://pypi.org/project/enlighten
- blessed, by Jeff Quast, Erik Rose, Avram Lubkin. Python library of the build tools. MIT. In the app (Mac). https://pypi.org/project/blessed
- Jinxed, by Avram Lubkin. Python library of the build tools. MPL-2.0. In the app (Mac). https://pypi.org/project/jinxed
- Prefixed, by Avram Lubkin. Python library of the build tools. MPL-2.0. In the app (Mac). https://pypi.org/project/prefixed
- wcwidth, by Jeff Quast. Python library of the build tools. MIT. In the app (Mac). https://pypi.org/project/wcwidth
- Zstandard, by Meta. Compression. BSD-3-Clause. In the app (Mac). https://github.com/facebook/zstd
- LZ4, by Yann Collet. Compression. BSD-2-Clause. In the app (Mac). https://github.com/lz4/lz4
- XZ Utils (liblzma), by The Tukaani Project. Compression. 0BSD. In the app (Mac). https://github.com/tukaani-project/xz
- glslang, by Khronos Group. Compiles shaders to SPIR-V. BSD-3-Clause. In the app (Mac). https://github.com/KhronosGroup/glslang
- SPIRV-Tools, by Khronos Group. Checks and optimizes SPIR-V. Apache-2.0. In the app (Mac). https://github.com/KhronosGroup/SPIRV-Tools
- Swift, by Apple and the Swift project. Programming language and its standard library. Apache-2.0 WITH Swift-exception. In the app (Windows, Linux). https://swift.org
- ICU, by Unicode, Inc.. Text in every language. Unicode-3.0. In the app (Windows, Linux). https://icu.unicode.org
- Rust, by The Rust Project. Programming language and its standard library. MIT OR Apache-2.0. In the app (Windows, Linux). https://www.rust-lang.org
- Tauri, by Tauri Programme. App window and packages. Apache-2.0 OR MIT. In the app (Windows, Linux). https://tauri.app
- Serde, by Erick Tryzelaar, David Tolnay. Data format. MIT OR Apache-2.0. In the app (Windows, Linux). https://serde.rs
- GilRs, by Arvamer. Controllers. Apache-2.0 OR MIT. In the app (Windows, Linux). https://gitlab.com/gilrs-project/gilrs
- ureq, by Martin Algesten, Jacob Hoffman-Andrews. Web requests. MIT OR Apache-2.0. In the app (Windows, Linux). https://github.com/algesten/ureq
- windows-rs, by Microsoft. Access to the system. MIT OR Apache-2.0. In the app (Windows). https://github.com/microsoft/windows-rs
- libc, by The Rust Project. Access to the system. MIT OR Apache-2.0. In the app (Linux). https://github.com/rust-lang/libc
- objc2, by Mads Marquart. Used to make the app; not inside it. MIT. Used to make the app (Windows, Linux). https://github.com/madsmtm/objc2
- Rust libraries, by Their authors. Every other Rust library in the app, listed with its licence. MIT AND Apache-2.0 AND MPL-2.0 AND Unicode-3.0. In the app (Windows, Linux). https://github.com/sofianbll/oort-nx/blob/alpha/windows/desktop/licenses-rust.txt
- WebView2, by Microsoft. Shows the window’s content. LicenseRef-Microsoft-WebView2. In the app (Windows). https://developer.microsoft.com/microsoft-edge/webview2/
- Visual C++ runtime, by Microsoft. C++ runtime. LicenseRef-Microsoft-Visual-Studio. In the app (Windows). https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist
- NSIS, by NSIS contributors. Installer. Zlib. In the app (Windows). https://nsis.sourceforge.io
- WebKitGTK, by WebKitGTK team. Shows the window’s content. LGPL-2.1-or-later. Reference, no code in the app (Linux). https://webkitgtk.org
- Kotlin, by JetBrains. Programming language and its standard library. Apache-2.0. In the app (Android). https://kotlinlang.org
- AndroidX and Jetpack Compose, by The Android Open Source Project. Interface toolkit. Apache-2.0. In the app (Android). https://developer.android.com/jetpack
- JNA, by java-native-access. Access to the system. Apache-2.0. In the app (Android). https://github.com/java-native-access/jna/tree/5.19.1
- XcodeGen, by Yonas Kolb. Used to make the app; not inside it. MIT. Used to make the app (iPhone and iPad). https://github.com/yonaskolb/XcodeGen
- dmgbuild, by Alastair Houghton. Used to make the app; not inside it. MIT. Used to make the app (Mac). https://github.com/dmgbuild/dmgbuild
- Tauri CLI, by Tauri Programme. Used to make the app; not inside it. Apache-2.0 OR MIT. Used to make the app (Windows, Linux). https://tauri.app
- Gradle and the Android Gradle plugin, by Gradle, Google. Used to make the app; not inside it. Apache-2.0. Used to make the app (Android). https://gradle.org
- JUnit 4, by JUnit. Used to make the app; not inside it. EPL-1.0. Used to make the app (Android). https://junit.org/junit4/

Icons and sounds
- Material Icons, by Google. Interface icons. Apache-2.0. In the app (Mac, Windows, Linux). https://github.com/google/material-design-icons
- Lucide, by Lucide Icons and Contributors, Feather by Cole Bemis. Interface icons. ISC AND MIT. In the app (Mac). https://github.com/lucide-icons/lucide
- Simple Icons, by Simple Icons contributors. Symbols that identify platforms. CC0-1.0. In the app (Mac). https://github.com/simple-icons/simple-icons
- Wikimedia Commons, by Its contributors. Symbols that identify platforms. No licence stated. In the app (Mac). https://commons.wikimedia.org
- CrossOver emblem, by CodeWeavers. Symbols that identify platforms. No licence stated. In the app (Mac). https://www.codeweavers.com
- Omarchy, by David Heinemeier Hansson. The set Selene’s colour palettes come from. MIT. Code adapted (Mac, Windows, Linux). https://github.com/basecamp/omarchy
- Catppuccin, by Catppuccin. Colour palette. MIT. Reference, no code in the app (Mac, Windows, Linux). https://github.com/catppuccin/catppuccin
- Everforest, by sainnhe. Colour palette. MIT. Reference, no code in the app (Mac, Windows, Linux). https://github.com/sainnhe/everforest
- Flexoki, by Steph Ango. Colour palette. MIT. Reference, no code in the app (Mac, Windows, Linux). https://github.com/kepano/flexoki
- Gruvbox, by Pavel Pertsev. Colour palette. MIT. Reference, no code in the app (Mac, Windows, Linux). https://github.com/morhetz/gruvbox
- Kanagawa, by Tommaso Laurenzi. Colour palette. MIT. Reference, no code in the app (Mac, Windows, Linux). https://github.com/rebelot/kanagawa.nvim
- Nord, by Sven Greb. Colour palette. MIT. Reference, no code in the app (Mac, Windows, Linux). https://github.com/nordtheme/nord
- Rosé Pine, by Rosé Pine. Colour palette. MIT. Reference, no code in the app (Mac, Windows, Linux). https://github.com/rose-pine/rose-pine-theme
- Tokyo Night, by Folke Lemaitre. Colour palette. Apache-2.0. Reference, no code in the app (Mac, Windows, Linux). https://github.com/folke/tokyonight.nvim
- Inter, by Rasmus Andersson. Text font. OFL-1.1. In the app (Windows, Linux, site). https://rsms.me/inter
- M+ 1p, by The M+ Project Authors. Font inside a bundled tool. OFL-1.1. In the app (Mac). https://fonts.google.com/specimen/M+PLUS+1p
- Oort, Pollen, Umbra, Impulsion, by Oort NX. Four packs of synthesized sounds. CC0-1.0. In the app (Mac, Windows, Linux, iPhone and iPad, Android, site). https://creativecommons.org/publicdomain/zero/1.0/
- SOHO Solar Sounds, by A. Kosovichev, Stanford, ESA/NASA. Measured vibrations of the Sun, the starting point of its sound; no recording included. No licence stated. Reference, no code in the app (Mac, Windows, Linux, iPhone and iPad, Android, site). https://solar-center.stanford.edu/singing/index.html

Services
- GameTDB, by GameTDB. Switch box covers. No licence stated. Service, off until used (Mac). https://www.gametdb.com
- Title DB, by blawar. Game names, icons and banners. MIT. Service, off until used (Mac). https://github.com/blawar/titledb
- nlib, by nlib. Game names, icons and banners. No licence stated. Service, off until used (Mac). https://api.nlib.cc
- LaunchBox Games Database, by Unbroken Software. Community metadata and game artwork. No licence stated. Service, off until used (Mac). https://gamesdb.launchbox-app.com
- TheGamesDB, by TheGamesDB. Community metadata and game artwork. No licence stated. Service, off until used (Mac). https://thegamesdb.net
- SteamGridDB, by SteamGridDB. Community covers, backgrounds, logos and icons, with your API key. No licence stated. Service, off until used (Mac). https://www.steamgriddb.com
- IGDB, by IGDB, Twitch. Critic scores with your own credentials. No licence stated. Service, off until used (Mac). https://www.igdb.com
- Wikipedia, by Its contributors. Game introductions in your language (CC BY-SA). CC-BY-SA-4.0. Service, off until used (Mac, Windows, Linux). https://www.wikipedia.org
- Wikidata, by Its contributors. Facts about games. CC0-1.0. Service, off until used (Mac, Windows, Linux). https://www.wikidata.org
- Steam, by Valve. Game information and artwork from the store. No licence stated. Service, off until used (Mac, Windows, Linux). https://store.steampowered.com
- Nintendo, by Nintendo. Game information and artwork from the store. No licence stated. Service, off until used (Mac). https://www.nintendo.com
- GOG, by GOG sp. z o.o.. Game information and artwork from the store. No licence stated. Service, off until used (Mac). https://www.gog.com
- Microsoft Store, by Microsoft. Game information and artwork from the store. No licence stated. Service, off until used (Mac). https://www.microsoft.com/store
- Game wikis, by Super Mario Wiki, SmashWiki, WiKirby, Nookipedia, Fire Emblem Wiki, Metroid Wiki, Pikipedia, Xeno Series Wiki. Artwork from community wikis. No licence stated. Service, off until used (Mac). https://www.niwanetwork.org
- Switch Icon Showdown, by Its contributors. Community Switch icons. No licence stated. Service, off until used (Mac). https://www.switchiconshowdown.com
- GameBanana, by GameBanana. Community mods. No licence stated. Service, off until used (Mac). https://gamebanana.com
- Wallhaven, by Wallhaven. Backgrounds you choose. No licence stated. Service, off until used (Mac). https://wallhaven.cc
- Danbooru, by Danbooru. Backgrounds you choose. No licence stated. Service, off until used (Mac). https://danbooru.donmai.us
- MotionBGs, by MotionBGs. Backgrounds you choose. No licence stated. Service, off until used (Mac). https://motionbgs.com
- HowLongToBeat, by Ziff Davis. Play times, opened in your browser. No licence stated. Service, off until used (Mac). https://howlongtobeat.com
- rclone, by Nick Craig-Wood. Reaches your cloud storage; downloaded only if you accept. MIT. Downloaded only on request (Mac). https://github.com/rclone/rclone
- Google Drive, by Google. Cloud storage you connect. No licence stated. Service, off until used (Mac). https://www.google.com/drive/
- Tailscale, by Tailscale. Private network for playing together, if you use it. No licence stated. Service, off until used (Mac). https://tailscale.com
- ZeroTier, by ZeroTier. Private network for playing together, if you use it. No licence stated. Service, off until used (Mac). https://www.zerotier.com
- NetBird, by NetBird. Private network for playing together, if you use it. No licence stated. Service, off until used (Mac). https://netbird.io
- GitHub, by GitHub. Source code and updates. No licence stated. Service, off until used (Mac, site). https://github.com
- Buy Me a Coffee, by Buy Me a Coffee. Optional contributions to Arcane’s author. No licence stated. Service, off until used (Mac). https://buymeacoffee.com/bium
<!-- END GENERATED CREDITS -->
