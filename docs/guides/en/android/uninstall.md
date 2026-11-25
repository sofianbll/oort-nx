---
title: Uninstall
system: android
topic: uninstall
order: 9
version: 0.1.0-alpha.1
minutes: 1
tried: Tried in an emulator (Android 10, 14 and 16) with invented games. Never on a real phone.
captures: app-info, game-bottom
---

## Remove Oort
<!-- step oort code 1aaff5c0:android/app/src/main/AndroidManifest.xml -->
Long press the icon, then uninstall. Your games stay, only Oort’s settings go.

![Android’s page for the app](../../media/android/app-info.en.webp)

## Remove a game
<!-- step game code 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/GameLauncher.kt 1aaff5c0:android/app/src/main/res/values/strings.xml -->
On its page, **Uninstall** opens its Android page. Export its save first.

![The bottom of a game’s page](../../media/android/game-bottom.en.webp)
