---
title: Essential settings
system: android
topic: settings
order: 6
version: 0.1.0-alpha.1
minutes: 2
tried: Tried in an emulator (Android 10, 14 and 16) with invented games. Never on a real phone.
captures: settings, sounds, cloud-look, thanks
---

## All on one page
<!-- step all checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/Prefs.kt -->
Games, sounds, buttons, cloud and version.

![The Settings page](../../media/android/settings.en.webp)

## Sounds
<!-- step sounds checked 1aaff5c0:android/tools/emulator_check.py -->
Turn them off, or choose Oort, Pollen, Umbra or Impulsion. Nobody has listened to them on a real device yet.

![The Sounds page](../../media/android/sounds.en.webp)

## A still cloud
<!-- step calm checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/Prefs.kt -->
**Calm cloud** stops all movement. By default it follows Android’s “Remove animations”.

![The Calm cloud setting](../../media/android/cloud-look.en.webp)

## Language
<!-- step language code 1aaff5c0:android/app/src/main/res/xml/locales.xml -->
French or English, following Android. From Android 13, choose it in Android’s settings for the app.

![The Thanks page](../../media/android/thanks.en.webp)
