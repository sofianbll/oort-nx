---
title: Controller and touch
system: android
topic: controls
order: 5
version: 0.1.0-alpha.1
minutes: 3
tried: Tried in an emulator (Android 10, 14 and 16) with invented games. Never on a real phone.
captures: home, pad-home, pad-held, controllers
---

## By touch
<!-- step touch checked 1aaff5c0:android/tools/emulator_check.py -->
Everything works by touch. Every target is at least 48 dp.

![The home screen with invented games](../../media/android/home.en.webp)

## With a controller
<!-- step pad checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/PadKeys.kt -->
D-pad or sticks to move. A confirms, B goes back, X sorts or opens the page, Y opens the controllers. Start opens the settings, L1 and R1 change tab.

![The home screen with a controller](../../media/android/pad-home.en.webp)

## Try your buttons
<!-- step test checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/PadMonitor.kt -->
**Controllers › Try the buttons**: each button lights up. Hold A or B to close. Checked with a simulated controller, not a real one.

![Lit buttons on the controller in dots](../../media/android/pad-held.en.webp)

## Swap A and B
<!-- step swap checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/Prefs.kt -->
For a controller with the Switch layout: **Controllers › Swap A and B**.

![The Controllers page](../../media/android/controllers.en.webp)
