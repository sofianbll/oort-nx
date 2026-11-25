---
title: Désinstaller
system: android
topic: uninstall
order: 9
version: 0.1.0-alpha.1
minutes: 1
tried: Essayé dans un émulateur (Android 10, 14 et 16) avec des jeux inventés. Jamais sur un vrai téléphone.
captures: app-info, game-bottom
---

## Retirer Oort
<!-- step oort code 1aaff5c0:android/app/src/main/AndroidManifest.xml -->
Appui long sur l’icône, puis désinstaller. Tes jeux restent, seuls les réglages d’Oort partent.

![La page Android de l’app (image en anglais)](../../media/android/app-info.en.webp)

## Retirer un jeu
<!-- step game code 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/GameLauncher.kt 1aaff5c0:android/app/src/main/res/values/strings.xml -->
Sur sa fiche, **Désinstaller** ouvre sa page Android. Exporte d’abord sa sauvegarde.

![Le bas de la fiche d’un jeu](../../media/android/game-bottom.fr.webp)
