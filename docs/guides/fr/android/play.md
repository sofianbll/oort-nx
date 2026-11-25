---
title: Jouer et revenir
system: android
topic: play
order: 4
version: 0.1.0-alpha.1
minutes: 2
tried: Essayé dans un émulateur (Android 10, 14 et 16) avec des jeux inventés. Jamais sur un vrai téléphone.
captures: game, in-game, game-bottom
---

## Lance
<!-- step play checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/GameLauncher.kt -->
Touche **Jouer**. Android ouvre l’app du jeu.

![La fiche d’un jeu inventé](../../media/android/game.fr.webp)

## Pendant la partie
<!-- step in-game code 1aaff5c0:android/app/src/main/res/values/strings.xml 1aaff5c0:android/README.md -->
Le geste Retour, ou le bouton Menu de la manette, ouvre le menu pause du jeu. C’est là que se trouvent ses réglages et ses sauvegardes.

![Un jeu inventé](../../media/android/in-game.fr.webp)

## Reviens
<!-- step back checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/LastStart.kt -->
Quitte le jeu ou repasse par les apps récentes. Oort note le jour du lancement, pas le temps de jeu.

![Le bas de la fiche d’un jeu](../../media/android/game-bottom.fr.webp)
