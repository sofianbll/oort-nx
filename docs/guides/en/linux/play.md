---
title: Play and come back
system: linux
topic: play
order: 6
version: 0.1.0-alpha.2
minutes: 3
tried: Tried on a fresh GitHub machine (Ubuntu 24.04), with invented games and an invented Steam. Never on a player’s computer.
captures: launch, back, running
---

## Start
<!-- step play checked f18e2119:desktop/src-tauri/src/lib.rs f18e2119:desktop/tests/linux/prove.sh -->
Choose **Play**. The screen shows the game, then Oort steps aside.

![The launch screen (picture in French)](../../media/linux/launch.fr.webp)

## Come back
<!-- step back checked f18e2119:desktop/src-tauri/src/lib.rs f18e2119:desktop/tests/linux/prove.sh -->
Quit the game as usual: Oort comes back in front and shows how long you played.

![Oort after the game (picture in French)](../../media/linux/back.fr.webp)

## Close a stuck game
<!-- step close checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/play.js -->
Go back to the Oort window: **Close Game** appears after four seconds. What is not saved is lost. The Home button is not supported in a game yet.

![The Close Game button (picture in French) (captured on Windows)](../../media/windows/running.fr.webp)
