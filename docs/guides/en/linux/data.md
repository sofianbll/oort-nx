---
title: What Oort reads, writes and sends
system: linux
topic: data
order: 13
version: 0.1.0-alpha.1
minutes: 2
tried: Tried on a fresh GitHub machine (Ubuntu 24.04) with invented games. Never on a player’s computer.
captures: settings-integrations, settings-about, settings-about
---

## Reads
<!-- step reads code cc9db84a:desktop/README.md cc9db84a:Sources/OortCompanion/Companion.swift -->
The folders and programs you add, and each game’s `recomplauncher.json`. Of a copy you choose, it looks at the name and place.

![Settings › Integrations (captured on Windows)](../../media/windows/settings-integrations.en.webp)

## Writes
<!-- step writes code cc9db84a:Sources/OortCompanion/Store.swift cc9db84a:Sources/OortCompanion/Places.swift -->
Its folder `~/.local/share/io.github.sofianbll.oort-nx.desktop` and the settings files a recompiled game declares. A game’s last messages are kept in its logs.

![Settings › About (captured on Windows)](../../media/windows/settings-about.en.webp)

## Sends
<!-- step sends code cc9db84a:desktop/README.md cc9db84a:desktop/src-tauri/tauri.conf.json -->
Nothing: no account, no measurement, no data. Project links open in your browser.

![Settings › About (captured on Windows)](../../media/windows/settings-about.en.webp)
