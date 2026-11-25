---
title: Play and come back
system: windows
topic: play
order: 6
version: 0.1.0-alpha.1
minutes: 3
tried: Tried on a fresh GitHub machine with invented games, and by one player on their PC (one game started, 25 November 2026).
captures: launch, session-card, running
---

## Start
<!-- step play played cc9db84a:desktop/src-tauri/src/lib.rs cc9db84a:desktop/tests/windows/prove.ps1 -->
Choose **Play**. The screen shows the game, then Oort steps aside.

![The launch screen (picture in French)](../../media/windows/launch.fr.webp)

## Come back
<!-- step back checked cc9db84a:desktop/src-tauri/src/lib.rs cc9db84a:desktop/tests/windows/prove.ps1 -->
Quit the game as usual: Oort comes back in front and shows how long you played.

![The session card, at the top right (picture in French)](../../media/windows/session-card.fr.webp)

## Close a stuck game
<!-- step close checked cc9db84a:desktop/ui/app.js cc9db84a:desktop/tests/play.js -->
Go back to the Oort window: **Close Game** appears after four seconds. What is not saved is lost. The Home button is not supported in a game yet.

![The Close Game button (picture in French)](../../media/windows/running.fr.webp)
