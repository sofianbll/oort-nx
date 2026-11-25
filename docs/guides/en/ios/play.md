---
title: Play and come back
system: ios
topic: play
order: 6
version: 0.1.0-alpha.1
minutes: 2
tried: Tried only in a simulator (iPhone and iPad, iOS 27.2) with invented games. Never on a real device.
captures: game, in-game, back
---

## Start
<!-- step play checked e3cd6df1:mobile/UITests/OortUITests.swift -->
Tap **Play** on the game page.

![An invented game’s page](../../media/ios/game.en.webp)

## While playing
<!-- step in-game checked e3cd6df1:mobile/UITests/OortUITests.swift -->
Checked with an invented game only. Coming back from a real game waits for the engine.

![An invented game](../../media/ios/in-game.en.webp)

## Come back
<!-- step back checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/SettingsScreens.swift -->
Play time is counted on this device, in **Settings › Play time**.

![Oort after the game](../../media/ios/back.en.webp)
