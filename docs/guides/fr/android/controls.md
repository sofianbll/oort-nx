---
title: Manette et toucher
system: android
topic: controls
order: 5
version: 0.1.0-alpha.1
minutes: 3
tried: Essayé dans un émulateur (Android 10, 14 et 16) avec des jeux inventés. Jamais sur un vrai téléphone.
captures: home, pad-home, pad-held, controllers
---

## Au doigt
<!-- step touch checked 1aaff5c0:android/tools/emulator_check.py -->
Tout marche au doigt. Toutes les cibles font au moins 48 dp.

![L’accueil avec des jeux inventés](../../media/android/home.fr.webp)

## À la manette
<!-- step pad checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/PadKeys.kt -->
Croix ou sticks pour bouger. A valide, B revient, X trie ou ouvre la fiche, Y ouvre les manettes. Start ouvre les réglages, L1 et R1 changent d’onglet.

![L’accueil à la manette](../../media/android/pad-home.fr.webp)

## Essaie tes boutons
<!-- step test checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/PadMonitor.kt -->
**Manettes › Essayer les boutons** : chaque bouton s’allume. Maintiens A ou B pour fermer. Vérifié avec une manette simulée, pas une vraie.

![Des boutons allumés sur la manette en points (image en anglais)](../../media/android/pad-held.en.webp)

## Inverse A et B
<!-- step swap checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/Prefs.kt -->
Pour une manette à la disposition Switch : **Manettes › Inverser A et B**.

![La page Manettes](../../media/android/controllers.fr.webp)
