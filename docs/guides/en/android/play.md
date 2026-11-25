---
title: Play and come back
system: android
topic: play
order: 4
version: 0.1.0-alpha.1
minutes: 2
tried: Tried in an emulator (Android 10, 14 and 16) with invented games. Never on a real phone.
captures: game, in-game, game-bottom
---

## Start
<!-- step play checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/GameLauncher.kt -->
Tap **Play**. Android opens the game’s app.

![An invented game’s page](../../media/android/game.en.webp)

## While playing
<!-- step in-game code 1aaff5c0:android/app/src/main/res/values/strings.xml 1aaff5c0:android/README.md -->
The Back gesture, or the controller’s Menu button, opens the game’s pause menu. Its settings and saves are there.

![An invented game](../../media/android/in-game.en.webp)

## Come back
<!-- step back checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/LastStart.kt -->
Quit the game or use the recent apps. Oort notes the day it was started, not the play time.

![The bottom of a game’s page](../../media/android/game-bottom.en.webp)
