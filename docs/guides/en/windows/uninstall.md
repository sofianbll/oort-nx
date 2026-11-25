---
title: Uninstall
system: windows
topic: uninstall
order: 12
version: 0.1.0-alpha.2
minutes: 2
tried: Tried on a fresh GitHub machine, with invented games, an invented Steam and invented services. A player started a game on their PC with alpha.1, not yet with this one.
captures: missing:uninstall, missing:data-folder
---

## Remove the app
<!-- step remove checked f18e2119:desktop/tests/windows/prove.ps1 -->
**Windows Settings › Apps › Oort NX › Uninstall**. Your games are not touched.

<!-- missing uninstall: The uninstall page or terminal. -->

## Erase your library if you like
<!-- step library checked f18e2119:desktop/tests/windows/prove.ps1 f18e2119:desktop/src-tauri/src/lib.rs -->
It stays in `%LOCALAPPDATA%\io.github.sofianbll.oort-nx.desktop`. Delete that folder to forget your settings and play time.

<!-- missing data-folder: The data folder, with an invented library. -->
