---
title: Troubleshooting
system: mac
topic: troubleshooting
order: 14
version: 0.5.0-beta.3
minutes: 5
tried: Checked automatically with invented games. No real game started, no real Drive transfer and no real controller with this version.
captures: settings-integrations, settings-engine, game-build, settings-cloud, settings-about
---

## A Steam game is missing
<!-- step steam code bf0c3410:PLAYER-GUIDE.md bf0c3410:Sources/NXLibrary/Views/Settings/SettingsSourcesSection.swift -->
**Settings › Integrations**: check the Steam folder, then **Refresh Steam**. The game must be installed and made for Mac.

![Settings › Integrations](../../media/mac/settings-integrations.en.webp)

## Building is blocked
<!-- step build checked bf0c3410:Tests/CatalogAppChecks/run_build_gates.py bf0c3410:PLAYER-GUIDE.md -->
**Settings › Switch › Engine** says what is wrong. A game already built still starts.

![Settings › Switch › Engine](../../media/mac/settings-engine.en.webp)

## Game files not found
<!-- step files code bf0c3410:PLAYER-GUIDE.md bf0c3410:Sources/NXLibrary/Views/GameOptions/GameOptionsView+Rows.swift -->
To rebuild: **Game options › Edit details › Attach sources…**. To play, the app is enough.

![An invented game, Build button (picture in French)](../../media/mac/game-build.fr.webp)

## The cloud does not answer
<!-- step cloud checked bf0c3410:Tests/CatalogAppChecks/run_cloud_shelf.py bf0c3410:Sources/NXLibrary/Views/Settings/SettingsCloudLibrarySection.swift -->
**Settings › Cloud library**, then test the connection. Oort keeps the last known state and says so.

![Settings › Cloud library](../../media/mac/settings-cloud.en.webp)

## Tell us
<!-- step report code bf0c3410:SECURITY.md bf0c3410:CONTRIBUTING.md -->
[Open a report](https://github.com/sofianbll/oort-nx/issues): what you were doing, what you saw, your versions. Read **Copy diagnostics** before pasting it. Attach no game, key or save.

![Settings › About](../../media/mac/settings-about.en.webp)
