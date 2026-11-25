---
title: Sauvegardes
system: android
topic: saves
order: 7
version: 0.1.0-alpha.1
minutes: 2
tried: Essayé dans un émulateur (Android 10, 14 et 16) avec des jeux inventés. Jamais sur un vrai téléphone.
captures: which-games, game-bottom
---

## Elles restent dans le jeu
<!-- step where code 1aaff5c0:android/README.md 1aaff5c0:android/app/src/main/res/values/strings.xml -->
Android ferme les fichiers d’un jeu aux autres apps. Oort ne peut ni les lire, ni les copier.

![La page Les jeux qu’Oort trouve](../../media/android/which-games.fr.webp)

## Exporte avant de désinstaller
<!-- step export code 1aaff5c0:android/app/src/main/res/values/strings.xml -->
Dans le jeu : menu pause, onglet Jeu, Exporter la sauvegarde. Désinstaller un jeu supprime ses sauvegardes. Pas essayé avec un vrai jeu.

![Le bas de la fiche d’un jeu](../../media/android/game-bottom.fr.webp)
