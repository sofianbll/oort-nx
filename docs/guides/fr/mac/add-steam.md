---
title: Ajouter tes jeux Steam
system: mac
topic: add-steam
order: 5
version: 0.5.0-beta.3
minutes: 3
tried: Vérifié par des contrôles automatiques avec des jeux inventés. Ni vrai jeu lancé, ni vrai transfert Drive, ni vraie manette avec cette version.
captures: settings-integrations, settings-integrations, steam-spotlight
---

## Active Steam
<!-- step on checked bf0c3410:Sources/NXLibrary/Views/Settings/SettingsSourcesSection.swift bf0c3410:Tests/CatalogAppChecks/run_settings_confirmations.py -->
**Réglages › Intégrations › Steam**. Oort lit la liste des jeux installés et n’écrit rien chez Steam.

![Réglages › Intégrations](../../media/mac/settings-integrations.fr.webp)

## Actualise
<!-- step refresh code bf0c3410:Sources/NXLibrary/Views/Settings/SettingsSourcesSection.swift bf0c3410:docs/how-it-works/steam.md -->
**Actualiser Steam** relit la liste. Seuls les jeux pour Mac installés apparaissent.

![Réglages › Intégrations](../../media/mac/settings-integrations.fr.webp)

## Joue
<!-- step play checked bf0c3410:Tests/CatalogAppChecks/run_profiles.py bf0c3410:docs/how-it-works/steam.md -->
**Jouer** passe par Steam, qui ouvre le jeu. Vérifié avec un faux Steam.

![Un jeu Steam inventé (image en anglais)](../../media/mac/steam-spotlight.en.webp)
