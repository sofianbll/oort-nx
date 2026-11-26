---
title: Add a game already built (.app)
system: mac
topic: add-ported-app
order: 4
version: 0.5.0-beta.3
minutes: 3
tried: Checked automatically with invented games. No real game started, no real Drive transfer and no real controller with this version.
captures: settings-switch, tour-games, adopted
---

## Say where your apps are
<!-- step folder code bf0c3410:Sources/NXLibrary/Views/Settings/SettingsLibrarySection.swift bf0c3410:PLAYER-GUIDE.md -->
**Settings › Switch › Game folders**, **Game apps** row. Changing folder moves no app.

![Settings › Switch](../../media/mac/settings-switch.en.webp)

## Scan
<!-- step scan code bf0c3410:Sources/NXLibraryCore/Settings/SettingsCatalog.swift bf0c3410:PLAYER-GUIDE.md -->
**Library refresh › Refresh**. A game already built starts without Xcode or its original files.

![Tour, step 4: invented games](../../media/mac/tour-games.en.webp)

## Or give a copy
<!-- step adopt checked bf0c3410:Tests/CatalogAppChecks/run_cloud_screens.py bf0c3410:Sources/NXLibrary/Views/AddGame/AddGameRows.swift -->
**Add game › Add ported app** copies the app and checks its signature. Only add what comes from a source you trust.

![The app added, content not verified (picture in French)](../../media/mac/adopted.fr.webp)
