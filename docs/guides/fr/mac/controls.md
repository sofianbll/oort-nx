---
title: Manette et clavier
system: mac
topic: controls
order: 8
version: 0.5.0-beta.3
minutes: 4
tried: Vérifié par des contrôles automatiques avec des jeux inventés. Ni vrai jeu lancé, ni vrai transfert Drive, ni vraie manette avec cette version.
captures: hints-keyboard, settings-controllers, settings-controllers, settings-controllers
---

## Les touches utiles
<!-- step keys checked bf0c3410:Tests/CatalogAppChecks/run_keymap_screens.py bf0c3410:docs/how-it-works/keymap.md -->
Les rappels sont en bas de l’écran.

| Action | Xbox | Switch | PlayStation | Clavier |
|---|---|---|---|---|
| Jouer, choisir | A | A | Croix | Entrée |
| Retour | B | B | Rond | Échap |
| Détails | X | X | Carré | X |
| Rechercher | Y | Y | Triangle | ⌘F |
| Options du jeu | Menu | + | Options | Y |
| Grille ou à la une | View | − | Pavé tactile | V |
| Onglet précédent, suivant | LB / RB | L / R | L1 / R1 | Q / E |
| Trier | Stick droit | Stick droit | R3 | F3 |
| Centre de contrôle | Maintenir Menu | Maintenir + | Maintenir Options | ⌘K |
| Réglages | Maintenir Guide | Maintenir Home | Maintenir PS | ⌘, |

![Les rappels du clavier, en bas de l’écran](../../media/mac/hints-keyboard.fr.webp)

## Deux dispositions
<!-- step layout code bf0c3410:docs/how-it-works/keymap.md bf0c3410:Sources/NXLibraryCore/Settings/SettingsCatalog.swift -->
Ce tableau est la disposition **Oort**. Un profil d’avant garde **Arcane**, où les réglages sont sur Menu maintenu : **Réglages › Manettes › Disposition**.

![Réglages › Manettes](../../media/mac/settings-controllers.fr.webp)

## Le bouton Home
<!-- step home code bf0c3410:docs/how-it-works/keymap.md bf0c3410:Sources/NXLibrary/Views/Settings/SettingsControllersSection.swift -->
Si macOS le garde pour lui, Oort le dit une fois. **Substitutions du bouton principal** ouvre le réglage de macOS.

![Réglages › Manettes](../../media/mac/settings-controllers.fr.webp)

## Essaie ta manette
<!-- step see checked bf0c3410:Tests/CatalogAppChecks/run_controller_identity.py bf0c3410:Sources/NXLibrary/Views/OortUI/OortControllerView.swift -->
Dans **Réglages › Manettes**, elle se dessine en points et allume ce que tu presses. Pas essayé avec une vraie manette dans cette version.

![Réglages › Manettes](../../media/mac/settings-controllers.fr.webp)
