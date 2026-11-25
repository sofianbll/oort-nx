---
title: Uninstall
system: linux
topic: uninstall
order: 11
version: 0.1.0-alpha.1
minutes: 2
tried: Tried on a fresh GitHub machine (Ubuntu 24.04) with invented games. Never on a player’s computer.
captures: missing:uninstall, missing:data-folder
---

## Remove the app
<!-- step remove checked cc9db84a:desktop/tests/linux/prove.sh -->
`sudo apt remove oort-nx`. Your games are not touched.

<!-- missing uninstall: The uninstall page or terminal. -->

## Erase your library if you like
<!-- step library checked cc9db84a:desktop/tests/linux/prove.sh cc9db84a:desktop/src-tauri/src/lib.rs -->
It stays in `~/.local/share/io.github.sofianbll.oort-nx.desktop`. Delete that folder to forget your settings and play time.

<!-- missing data-folder: The data folder, with an invented library. -->
