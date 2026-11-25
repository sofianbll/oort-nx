---
title: Uninstall
system: linux
topic: uninstall
order: 12
version: 0.1.0-alpha.2
minutes: 2
tried: Tried on a fresh GitHub machine (Ubuntu 24.04), with invented games and an invented Steam. Never on a player’s computer.
captures: missing:uninstall, missing:data-folder
---

## Remove the app
<!-- step remove checked f18e2119:desktop/tests/linux/prove.sh -->
`sudo apt remove oort-nx`. Your games are not touched.

<!-- missing uninstall: The uninstall page or terminal. -->

## Erase your library if you like
<!-- step library checked f18e2119:desktop/tests/linux/prove.sh f18e2119:desktop/src-tauri/src/lib.rs -->
It stays in `~/.local/share/io.github.sofianbll.oort-nx.desktop`. Delete that folder to forget your settings and play time.

<!-- missing data-folder: The data folder, with an invented library. -->
