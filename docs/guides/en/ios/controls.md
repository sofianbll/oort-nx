---
title: Controller and touch
system: ios
topic: controls
order: 7
version: 0.1.0-alpha.1
minutes: 3
tried: Tried only in a simulator (iPhone and iPad, iOS 27.2) with invented games. Never on a real device.
captures: ipad-home, controllers, mapping, controllers
---

## By touch
<!-- step touch checked e3cd6df1:mobile/UITests/OortUITests.swift -->
Upright, on its side, on iPad, and with very large text.

![The home screen on iPad](../../media/ios/ipad-home.en.webp)

## With a controller
<!-- step pad checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/OortNav.swift e3cd6df1:mobile/Sources/ShellControllers/PadMapping.swift -->
Pair it in iOS Settings › Bluetooth. A opens, B goes back, L and R change tab. Checked with a simulated controller.

![The Controllers page](../../media/ios/controllers.en.webp)

## Change the buttons
<!-- step map checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/ControllersScreen.swift -->
**Controllers › What each button sends**, for every game or on one game’s page. Not tried in a real game.

![The Buttons page](../../media/ios/mapping.en.webp)

## Touch controls in a game
<!-- step onscreen code e3cd6df1:mobile/Sources/OortMobile/ControllersScreen.swift https://github.com/sofianbll/oort-nx/releases/tag/ios-v0.1.0-alpha.1 -->
Their settings are there (size, stick, 2D or 3D), but they wait for the engine.

![The Controllers page](../../media/ios/controllers.en.webp)
