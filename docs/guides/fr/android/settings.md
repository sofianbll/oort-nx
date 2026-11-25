---
title: Réglages essentiels
system: android
topic: settings
order: 6
version: 0.1.0-alpha.1
minutes: 2
tried: Essayé dans un émulateur (Android 10, 14 et 16) avec des jeux inventés. Jamais sur un vrai téléphone.
captures: settings, sounds, cloud-look, thanks
---

## Tout est sur une page
<!-- step all checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/Prefs.kt -->
Jeux, sons, boutons, nuage et version.

![La page Réglages](../../media/android/settings.fr.webp)

## Les sons
<!-- step sounds checked 1aaff5c0:android/tools/emulator_check.py -->
Coupe-les, ou choisis Oort, Pollen, Umbra ou Impulsion. Personne ne les a encore écoutés sur un vrai appareil.

![La page Sons](../../media/android/sounds.fr.webp)

## Le nuage immobile
<!-- step calm checked 1aaff5c0:android/tools/emulator_check.py 1aaff5c0:android/app/src/main/kotlin/io/github/sofianbll/oortnx/core/Prefs.kt -->
**Nuage calme** arrête tout mouvement. Par défaut il suit « Supprimer les animations » d’Android.

![Le réglage Nuage calme](../../media/android/cloud-look.fr.webp)

## La langue
<!-- step language code 1aaff5c0:android/app/src/main/res/xml/locales.xml -->
Français ou anglais, selon Android. À partir d’Android 13, choisis-la dans les réglages Android de l’app.

![La page Remerciements](../../media/android/thanks.fr.webp)
