---
title: Saves
system: android
topic: saves
order: 7
version: 0.1.0-alpha.1
minutes: 2
tried: Tried in an emulator (Android 10, 14 and 16) with invented games. Never on a real phone.
captures: which-games, game-bottom
---

## They stay in the game
<!-- step where code 1aaff5c0:android/README.md 1aaff5c0:android/app/src/main/res/values/strings.xml -->
Android closes a game’s files to other apps. Oort can neither read nor copy them.

![The Which games Oort finds page](../../media/android/which-games.en.webp)

## Export before uninstalling
<!-- step export code 1aaff5c0:android/app/src/main/res/values/strings.xml -->
In the game: pause menu, Game tab, Export save. Uninstalling a game deletes its saves. Not tried with a real game.

![The bottom of a game’s page](../../media/android/game-bottom.en.webp)
