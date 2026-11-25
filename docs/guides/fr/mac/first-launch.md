---
title: Premier lancement
system: mac
topic: first-launch
order: 2
version: 0.5.0-beta.3
minutes: 4
tried: Vérifié par des contrôles automatiques avec des jeux inventés. Ni vrai jeu lancé, ni vrai transfert Drive, ni vraie manette avec cette version.
captures: missing:library-copy, tour-controller, tour-games, tour-services, tour-look
---

## Tu viens de la 0.3.0 ?
<!-- step old code bf0c3410:Sources/NXLibraryCore/App/AppDataProfile.swift bf0c3410:CHANGELOG.md https://github.com/sofianbll/oort-nx/releases/tag/v0.5.0-beta.3 -->
Ta bibliothèque est copiée et chaque fichier vérifié ; l’ancienne reste intacte. Reconnecte tes services une fois, et n’ouvre pas les deux versions ensemble.

<!-- missing library-copy: L’écran de copie de la bibliothèque 0.3.0. -->

## Ta manette
<!-- step controller checked bf0c3410:Sources/NXLibrary/Views/Setup/OnboardingView.swift bf0c3410:Tests/CatalogAppChecks/run_onboarding.py -->
L’accueil dit si elle est reconnue. Sinon, continue au clavier ou à la souris.

![Accueil, étape 2 : la manette](../../media/mac/tour-controller.fr.webp)

## Les jeux déjà là
<!-- step games checked bf0c3410:Sources/NXLibrary/Views/Setup/OnboardingView.swift bf0c3410:Tests/CatalogAppChecks/run_onboarding.py -->
Oort liste les apps de jeux trouvées et les fichiers du dossier que tu choisis. Ajouter ne déplace rien et ne compile rien.

![Accueil, étape 4 : des jeux inventés](../../media/mac/tour-games.fr.webp)

## Les services, plus tard
<!-- step services checked bf0c3410:Sources/NXLibrary/Views/Setup/OnboardingView.swift bf0c3410:Tests/CatalogAppChecks/run_onboarding.py -->
Google Drive, Nextendo, Steam et copies de sauvegardes sont facultatifs. **Plus tard** les laisse coupés.

![Accueil, étape 5 : les services](../../media/mac/tour-services.fr.webp)

## Refaire l’accueil
<!-- step again code bf0c3410:Sources/NXLibraryCore/Settings/SettingsCatalog.swift bf0c3410:PLAYER-GUIDE.md -->
**Réglages › Général › Assistant de bienvenue**. Rien n’est remis à zéro.

![Accueil, étape 6 : apparence et son](../../media/mac/tour-look.fr.webp)
