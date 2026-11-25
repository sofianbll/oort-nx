---
title: Ajouter un jeu déjà compilé (.app)
system: mac
topic: add-ported-app
order: 4
version: 0.5.0-beta.3
minutes: 3
tried: Vérifié par des contrôles automatiques avec des jeux inventés. Ni vrai jeu lancé, ni vrai transfert Drive, ni vraie manette avec cette version.
captures: settings-switch, tour-games, adopted
---

## Dis où sont tes apps
<!-- step folder code bf0c3410:Sources/NXLibrary/Views/Settings/SettingsLibrarySection.swift bf0c3410:PLAYER-GUIDE.md -->
**Réglages › Switch › Dossiers de jeux**, ligne **Apps de jeux**. Changer de dossier ne déplace aucune app.

![Réglages › Switch](../../media/mac/settings-switch.fr.webp)

## Analyse
<!-- step scan code bf0c3410:Sources/NXLibraryCore/Settings/SettingsCatalog.swift bf0c3410:PLAYER-GUIDE.md -->
**Analyser les apps de jeux › Analyser**. Un jeu déjà compilé se lance sans Xcode ni fichiers d’origine.

![Accueil, étape 4 : des jeux inventés](../../media/mac/tour-games.fr.webp)

## Ou donne une copie
<!-- step adopt checked bf0c3410:Tests/CatalogAppChecks/run_cloud_screens.py bf0c3410:Sources/NXLibrary/Views/AddGame/AddGameRows.swift -->
**Ajouter un jeu › Ajouter une app déjà portée** copie l’app et vérifie sa signature. N’ajoute que ce qui vient d’une source sûre.

![L’app ajoutée, contenu non vérifié](../../media/mac/adopted.fr.webp)
