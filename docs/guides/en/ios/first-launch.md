---
title: First launch
system: ios
topic: first-launch
order: 4
version: 0.1.0-alpha.1
minutes: 2
tried: Tried only in a simulator (iPhone and iPad, iOS 27.2) with invented games. Never on a real device.
captures: empty, home-swiped, library
---

## An empty library
<!-- step empty checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/Resources/Localizable.xcstrings -->
The app contains no game, and says so. **Add a game** opens Files.

![The app with no game](../../media/ios/empty.en.webp)

## Home
<!-- step home checked e3cd6df1:mobile/UITests/OortUITests.swift -->
Swipe the large picture. **Play** is below, with the game page and options beside it.

![The home screen, another invented game](../../media/ios/home-swiped.en.webp)

## The library
<!-- step tabs checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/LibraryView.swift -->
Search at the top, sort by last played or by name, and add with **+**.

![The library with invented games](../../media/ios/library.en.webp)
