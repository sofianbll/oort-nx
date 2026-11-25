---
title: What Oort reads, writes and sends
system: linux
topic: data
order: 14
version: 0.1.0-alpha.2
minutes: 2
tried: Tried on a fresh GitHub machine (Ubuntu 24.04), with invented games and an invented Steam. Never on a player’s computer.
captures: settings-integrations, settings-about, setup-online
---

## Reads
<!-- step reads code f18e2119:desktop/README.md f18e2119:Sources/OortCompanion/SteamShelf.swift f18e2119:Sources/OortCompanion/ProgramFile.swift -->
The folders and programs you add, with the name and icon in their file. If Steam is on: its lists of installed games and its pictures, never your account or your saves.

![Settings › Integrations (captured on Windows)](../../media/windows/settings-integrations.en.webp)

## Writes
<!-- step writes code f18e2119:Sources/OortCompanion/Store.swift f18e2119:Sources/OortCompanion/Places.swift -->
Its folder `~/.local/share/io.github.sofianbll.oort-nx.desktop` and the settings files a recompiled game declares. Nothing in Steam.

![Settings › About (captured on Windows)](../../media/windows/settings-about.en.webp)

## Sends
<!-- step sends code f18e2119:desktop/README.md f18e2119:Sources/OortCompanion/Online.swift f18e2119:desktop/src-tauri/src/online.rs -->
Nothing while information online is off. On: the game’s name or its Steam number, and your language, to the Steam store, Wikidata and Wikipedia, which see your internet address.

![The question of the guided setup (captured on Windows)](../../media/windows/setup-online.en.webp)
