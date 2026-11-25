---
title: Update
system: mac
topic: updates
order: 12
version: 0.5.0-beta.3
minutes: 2
tried: Checked automatically with invented games. No real game started, no real Drive transfer and no real controller with this version.
captures: settings-about, missing:update-dialog, dmg
---

## Check
<!-- step check checked bf0c3410:Tests/CatalogAppChecks/run_settings_confirmations.py bf0c3410:Sources/NXLibraryCore/Settings/SettingsCatalog.swift -->
**Settings › About › Check now**. Oort also looks by itself, once a day at most.

![Settings › About, in a trial copy](../../media/mac/settings-about.en.webp)

## Install
<!-- step install code bf0c3410:docs/how-it-works/flows.md bf0c3410:CHANGELOG.md -->
**Update** downloads, checks, replaces and reopens Oort. It waits for a build or a game to end.

<!-- missing update-dialog: The update window with an invented version. -->

## From 0.3.0
<!-- step old code bf0c3410:CHANGELOG.md bf0c3410:PLAYER-GUIDE.fr.md -->
It cannot move to this version by itself: install the DMG once.

![The DMG window, captured on an earlier trial](../../media/mac/dmg.webp)
