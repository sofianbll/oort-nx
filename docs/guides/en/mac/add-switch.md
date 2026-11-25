---
title: Add a Switch game to build
system: mac
topic: add-switch
order: 3
version: 0.5.0-beta.3
minutes: 15
tried: Checked automatically with invented games. No real game started, no real Drive transfer and no real controller with this version.
captures: tools, settings-engine, add-menu, missing:add-review, game-build
---

## What you need
<!-- step needs code bf0c3410:PLAYER-GUIDE.md bf0c3410:README.fr.md -->
Your own game files, your `prod.keys`, and the right to use them. Oort provides no game, key or firmware. Building also needs Xcode 27.2 or later, the expected Metal compiler and macOS 26.6.

![The build tools; the keys shown are an invented, refused file (picture in French)](../../media/mac/tools.fr.webp)

## Prepare the tools
<!-- step tools code bf0c3410:Sources/NXLibrary/Views/Setup/SetupCheckView.swift bf0c3410:PLAYER-GUIDE.md -->
**Settings › Switch › Engine › Open Setup** shows what is missing. Each installation asks first and shows where it goes.

![Settings › Switch › Engine](../../media/mac/settings-engine.en.webp)

## Choose the files
<!-- step choose code bf0c3410:Sources/NXLibrary/Views/AddGame/AddGameView.swift bf0c3410:Sources/NXLibrary/Views/AddGame/AddGameRows.swift -->
**Add game**, or ⌘N, then your NSP, XCI, NSZ, XCZ or NUP files. They stay where they are.

![The Library menu of the control center](../../media/mac/add-menu.en.webp)

## Review
<!-- step review code bf0c3410:Sources/NXLibrary/Views/AddGame/AddGameView.swift bf0c3410:PLAYER-GUIDE.md -->
Look at the game, update, DLC, destination and space. **Add to library only** keeps the game for later.

<!-- missing add-review: The Review step with an invented game. -->

## Build
<!-- step build code bf0c3410:Sources/NXLibrary/Views/AddGame/AddGameStepThreeView.swift bf0c3410:PLAYER-GUIDE.md -->
**Add and port** starts the engine; you can close the screen, it goes on. How long depends on the game and the Mac. No real game was built with this version.

![An invented game, Build button (picture in French)](../../media/mac/game-build.fr.webp)
