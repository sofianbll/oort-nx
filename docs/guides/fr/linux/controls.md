---
title: Manette et clavier
system: linux
topic: controls
order: 7
version: 0.1.0-alpha.2
minutes: 4
tried: Essayé sur une machine neuve de GitHub (Ubuntu 24.04), avec des jeux inventés et un faux Steam. Jamais sur l’ordinateur d’un joueur.
captures: home, prompts-playstation, search-pad, settings-controllers
---

## Les touches utiles
<!-- step keys checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/pad.js -->
Les rappels sont en bas de l’écran.

| Action | Xbox | Clavier |
|---|---|---|
| Jouer, choisir | A | Entrée |
| Retour | B | Échap |
| Détails | X | X |
| Rechercher | Y | Y ou Ctrl F |
| Grille ou à la une | View | V |
| Changer d’onglet | LB / RB | Q / E |
| Trier | Stick droit | F3 |
| Réglages | Menu | M |
| Plein écran | | F11 |

![L’accueil avec des jeux inventés](../../media/linux/home.fr.webp)

## Ta manette
<!-- step prompts checked f18e2119:desktop/ui/nav.js f18e2119:desktop/tests/pad.js -->
Son nom s’affiche en haut à gauche et les rappels prennent ses boutons : Xbox, PlayStation ou Nintendo. Vérifié avec des manettes simulées, pas encore avec une vraie.

![Les rappels PlayStation (capturé sous Windows)](../../media/windows/prompts-playstation.fr.webp)

## Écrire à la manette
<!-- step type checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/pad.js -->
La recherche ouvre un clavier à l’écran. **X** efface.

![Le clavier à l’écran (capturé sous Windows)](../../media/windows/search-pad.fr.webp)

## Changer les noms des boutons
<!-- step change checked f18e2119:Sources/OortCompanion/SettingRows.swift -->
**Réglages › Manettes › Noms des boutons**. Changer les touches d’un jeu se fait dans le jeu.

![Réglages › Manettes (capturé sous Windows)](../../media/windows/settings-controllers.fr.webp)
