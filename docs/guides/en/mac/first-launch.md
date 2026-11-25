---
title: First launch
system: mac
topic: first-launch
order: 2
version: 0.5.0-beta.3
minutes: 4
tried: Checked automatically with invented games. No real game started, no real Drive transfer and no real controller with this version.
captures: missing:library-copy, tour-controller, tour-games, tour-services, tour-look
---

## Coming from 0.3.0?
<!-- step old code bf0c3410:Sources/NXLibraryCore/App/AppDataProfile.swift bf0c3410:CHANGELOG.md https://github.com/sofianbll/oort-nx/releases/tag/v0.5.0-beta.3 -->
Your library is copied and every file checked; the old one stays intact. Sign in to your services once, and do not open both versions together.

<!-- missing library-copy: The 0.3.0 library copy screen. -->

## Your controller
<!-- step controller checked bf0c3410:Sources/NXLibrary/Views/Setup/OnboardingView.swift bf0c3410:Tests/CatalogAppChecks/run_onboarding.py -->
The tour says whether it is recognised. Otherwise, go on with keyboard or mouse.

![Tour, step 2: controller](../../media/mac/tour-controller.en.webp)

## Games already here
<!-- step games checked bf0c3410:Sources/NXLibrary/Views/Setup/OnboardingView.swift bf0c3410:Tests/CatalogAppChecks/run_onboarding.py -->
Oort lists the game apps it finds and the files of a folder you choose. Adding moves nothing and builds nothing.

![Tour, step 4: invented games](../../media/mac/tour-games.en.webp)

## Services, later
<!-- step services checked bf0c3410:Sources/NXLibrary/Views/Setup/OnboardingView.swift bf0c3410:Tests/CatalogAppChecks/run_onboarding.py -->
Google Drive, Nextendo, Steam and save copies are optional. **Later** leaves them off.

![Tour, step 5: services](../../media/mac/tour-services.en.webp)

## Take the tour again
<!-- step again code bf0c3410:Sources/NXLibraryCore/Settings/SettingsCatalog.swift bf0c3410:PLAYER-GUIDE.md -->
**Settings › General › Welcome setup**. Nothing is reset.

![Tour, step 6: look and sound](../../media/mac/tour-look.en.webp)
