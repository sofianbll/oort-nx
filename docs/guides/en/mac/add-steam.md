---
title: Add your Steam games
system: mac
topic: add-steam
order: 5
version: 0.5.0-beta.3
minutes: 3
tried: Checked automatically with invented games. No real game started, no real Drive transfer and no real controller with this version.
captures: settings-integrations, settings-integrations, steam-spotlight
---

## Turn on Steam
<!-- step on checked bf0c3410:Sources/NXLibrary/Views/Settings/SettingsSourcesSection.swift bf0c3410:Tests/CatalogAppChecks/run_settings_confirmations.py -->
**Settings › Integrations › Steam**. Oort reads the list of installed games and writes nothing in Steam.

![Settings › Integrations](../../media/mac/settings-integrations.en.webp)

## Refresh
<!-- step refresh code bf0c3410:Sources/NXLibrary/Views/Settings/SettingsSourcesSection.swift bf0c3410:docs/how-it-works/steam.md -->
**Refresh Steam** reads the list again. Only installed Mac games show.

![Settings › Integrations](../../media/mac/settings-integrations.en.webp)

## Play
<!-- step play checked bf0c3410:Tests/CatalogAppChecks/run_profiles.py bf0c3410:docs/how-it-works/steam.md -->
**Play** goes through Steam, which opens the game. Checked with a fake Steam.

![An invented Steam game](../../media/mac/steam-spotlight.en.webp)
