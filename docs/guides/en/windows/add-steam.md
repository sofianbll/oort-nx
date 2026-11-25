---
title: Add your Steam games
system: windows
topic: add-steam
order: 5
version: 0.1.0-alpha.2
minutes: 2
tried: Tried on a fresh GitHub machine, with invented games, an invented Steam and invented services. A player started a game on their PC with alpha.1, not yet with this one.
captures: setup-games, steam-shelf, steam-waiting, steam-back
---

## Turn Steam on
<!-- step on checked f18e2119:desktop/tests/steam.js f18e2119:desktop/tests/windows/prove.ps1 f18e2119:Sources/OortCompanion/SteamShelf.swift -->
In the guided setup, the **+** tile or **Settings › Integrations › Steam**. Oort reads the installed games, on every drive, and writes nothing in Steam.

![Steam, with five invented games](../../media/windows/setup-games.en.webp)

## Find them
<!-- step shelf checked f18e2119:desktop/tests/steam.js f18e2119:desktop/tests/windows/prove.ps1 -->
Their pictures are the ones Steam already keeps on your computer. Tools and soundtracks are left out; a game must be fully downloaded.

![An invented Steam game in the library (picture in French)](../../media/windows/steam-shelf.fr.webp)

## Play
<!-- step play checked f18e2119:desktop/tests/steam.js f18e2119:desktop/tests/windows/prove.ps1 f18e2119:desktop/src-tauri/src/steam.rs -->
**Play** asks Steam for the game, and Steam starts it. If it updates it first, Oort waits; **Cancel** stops waiting.

![Waiting for Steam to start the game (picture in French)](../../media/windows/steam-waiting.fr.webp)

## Come back
<!-- step back checked f18e2119:desktop/tests/steam.js f18e2119:desktop/tests/windows/prove.ps1 -->
Quit the game: Oort comes back and counts the time. Checked with an invented Steam, never with the real one.

![Oort after the game (picture in French)](../../media/windows/steam-back.fr.webp)
