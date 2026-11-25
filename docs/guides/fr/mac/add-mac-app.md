---
title: Ajouter une app Mac
system: mac
topic: add-mac-app
order: 6
version: 0.5.0-beta.3
minutes: 2
tried: Vérifié par des contrôles automatiques avec des jeux inventés. Ni vrai jeu lancé, ni vrai transfert Drive, ni vraie manette avec cette version.
captures: settings-integrations, missing:mac-app-tile
---

## Ajoute-la
<!-- step add checked bf0c3410:Tests/CatalogAppChecks/MacShortcutProbe.swift bf0c3410:Sources/NXLibrary/Views/Settings/SettingsSourcesSection.swift -->
**Réglages › Intégrations › Apps Mac › Ajouter une app…**, ou dépose un `.app` sur la bibliothèque.

![Réglages › Intégrations](../../media/mac/settings-integrations.fr.webp)

## Ce qu’Oort fait
<!-- step what code bf0c3410:PLAYER-GUIDE.fr.md bf0c3410:Sources/NXLibraryCore/Catalog/MacShortcutRecord.swift -->
Il ouvre l’app, sans la modifier et sans compter le temps. Si elle change de place, **Retrouver l’app…**.

<!-- missing mac-app-tile: Une app Mac inventée dans la bibliothèque, options ouvertes. -->
