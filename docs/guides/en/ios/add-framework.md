---
title: Add a game (.framework)
system: ios
topic: add-framework
order: 5
version: 0.1.0-alpha.1
minutes: 3
tried: Tried only in a simulator (iPhone and iPad, iOS 27.2) with invented games. Never on a real device.
captures: empty, picker, import-refused
---

## What it takes
<!-- step know code e3cd6df1:mobile/Sources/OortMobile/Resources/Localizable.xcstrings e3cd6df1:mobile/Sources/OortMobile/FrameworkImport.swift -->
A `DmGame….framework` folder, signed with the same account as the app. Oort for Mac cannot make one yet, and no real game was tried.

![The app with no game](../../media/ios/empty.en.webp)

## Choose the folder
<!-- step pick checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/FrameworkImport.swift -->
**Add a game**, then the folder in Files. Oort copies it and leaves the original.

![Apple’s Files](../../media/ios/picker.en.webp)

## If Oort refuses
<!-- step refused checked e3cd6df1:mobile/UITests/OortUITests.swift -->
It says why: not a game, not enough space or another signature. Nothing has changed.

![The refused-folder message](../../media/ios/import-refused.en.webp)
