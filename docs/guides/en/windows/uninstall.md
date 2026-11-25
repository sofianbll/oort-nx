---
title: Uninstall
system: windows
topic: uninstall
order: 11
version: 0.1.0-alpha.1
minutes: 2
tried: Tried on a fresh GitHub machine with invented games, and by one player on their PC (one game started, 25 November 2026).
captures: missing:uninstall, missing:data-folder
---

## Remove the app
<!-- step remove checked cc9db84a:desktop/tests/windows/prove.ps1 -->
**Windows Settings › Apps › Oort NX › Uninstall**. Your games are not touched.

<!-- missing uninstall: The uninstall page or terminal. -->

## Erase your library if you like
<!-- step library checked cc9db84a:desktop/tests/windows/prove.ps1 cc9db84a:desktop/src-tauri/src/lib.rs -->
It stays in `%LOCALAPPDATA%\io.github.sofianbll.oort-nx.desktop`. Delete that folder to forget your settings and play time.

<!-- missing data-folder: The data folder, with an invented library. -->
