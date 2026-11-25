---
title: Play and come back
system: windows
topic: play
order: 6
version: 0.1.0-alpha.2
minutes: 3
tried: Tried on a fresh GitHub machine, with invented games, an invented Steam and invented services. A player started a game on their PC with alpha.1, not yet with this one.
captures: launch, session-card, running
---

## Start
<!-- step play checked f18e2119:desktop/src-tauri/src/lib.rs f18e2119:desktop/tests/windows/prove.ps1 -->
Choose **Play**. The screen shows the game, then Oort steps aside.

![The launch screen (picture in French)](../../media/windows/launch.fr.webp)

## Come back
<!-- step back checked f18e2119:desktop/src-tauri/src/lib.rs f18e2119:desktop/tests/windows/prove.ps1 -->
Quit the game as usual: Oort comes back in front and shows how long you played.

![The session card, at the top right (picture in French)](../../media/windows/session-card.fr.webp)

## Close a stuck game
<!-- step close checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/play.js -->
Go back to the Oort window: **Close Game** appears after four seconds. What is not saved is lost. The Home button is not supported in a game yet.

![The Close Game button (picture in French)](../../media/windows/running.fr.webp)
