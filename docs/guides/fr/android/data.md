---
title: Ce qu’Oort lit, écrit et envoie
system: android
topic: data
order: 11
version: 0.1.0-alpha.1
minutes: 2
tried: Essayé dans un émulateur (Android 10, 14 et 16) avec des jeux inventés. Jamais sur un vrai téléphone.
captures: which-games, settings, app-info
---

## Lit
<!-- step reads code 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/GameScanner.kt 1aaff5c0:android/app/src/main/AndroidManifest.xml -->
La liste des apps qu’Android montre dans son propre lanceur. Oort ne garde que celles des jeux nx2android.

![La page Les jeux qu’Oort trouve](../../media/android/which-games.fr.webp)

## Écrit
<!-- step writes code 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/Prefs.kt -->
Ses réglages et le jour du dernier lancement de chaque jeu, dans l’app. Rien dans tes jeux.

![La page Réglages](../../media/android/settings.fr.webp)

## Envoie
<!-- step sends checked 1aaff5c0:android/app/src/main/AndroidManifest.xml 1aaff5c0:android/tools/emulator_check.py -->
Rien. L’app ne demande aucune autorisation à Android, pas même le réseau.

![La page Android de l’app : aucune autorisation (image en anglais)](../../media/android/app-info.en.webp)
