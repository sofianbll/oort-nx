---
title: What Oort reads, writes and sends
system: android
topic: data
order: 11
version: 0.1.0-alpha.1
minutes: 2
tried: Tried in an emulator (Android 10, 14 and 16) with invented games. Never on a real phone.
captures: which-games, settings, app-info
---

## Reads
<!-- step reads code 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/GameScanner.kt 1aaff5c0:android/app/src/main/AndroidManifest.xml -->
The list of apps Android shows in its own launcher. Oort only keeps those of nx2android games.

![The Which games Oort finds page](../../media/android/which-games.en.webp)

## Writes
<!-- step writes code 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/Prefs.kt -->
Its settings and the day each game was last started, inside the app. Nothing in your games.

![The Settings page](../../media/android/settings.en.webp)

## Sends
<!-- step sends checked 1aaff5c0:android/app/src/main/AndroidManifest.xml 1aaff5c0:android/tools/emulator_check.py -->
Nothing. The app asks Android for no permission, not even the network.

![Android’s page for the app: no permission](../../media/android/app-info.en.webp)
