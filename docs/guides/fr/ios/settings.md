---
title: Réglages essentiels
system: ios
topic: settings
order: 8
version: 0.1.0-alpha.1
minutes: 2
tried: Essayé seulement sur simulateur (iPhone et iPad, iOS 27.2) avec des jeux inventés. Jamais sur un vrai appareil.
captures: settings, settings-end, options
---

## La page Réglages
<!-- step all checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/SettingsScreens.swift -->
Ajouter un jeu, temps de jeu, dossiers, options communes à tous les jeux.

![La page Réglages](../../media/ios/settings.fr.webp)

## Sons et vibrations
<!-- step sounds checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/SettingsScreens.swift -->
Coupe-les ou change de voix. Pas écoutés sur un vrai appareil.

![Le bas des Réglages](../../media/ios/settings-end.fr.webp)

## Options d’un jeu
<!-- step game checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/GameScreens.swift -->
Elles viennent du jeu lui-même, et passent avant les réglages communs.

![Les options d’un jeu](../../media/ios/options.fr.webp)
