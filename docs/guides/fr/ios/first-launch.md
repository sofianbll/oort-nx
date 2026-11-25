---
title: Premier lancement
system: ios
topic: first-launch
order: 4
version: 0.1.0-alpha.1
minutes: 2
tried: Essayé seulement sur simulateur (iPhone et iPad, iOS 27.2) avec des jeux inventés. Jamais sur un vrai appareil.
captures: empty, home-swiped, library
---

## Une bibliothèque vide
<!-- step empty checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/Resources/Localizable.xcstrings -->
L’app ne contient aucun jeu, et le dit. **Ajouter un jeu** ouvre Fichiers.

![L’app sans aucun jeu](../../media/ios/empty.fr.webp)

## À la une
<!-- step home checked e3cd6df1:mobile/UITests/OortUITests.swift -->
Glisse la grande image. **Jouer** est dessous, la fiche et les options à côté.

![À la une, un autre jeu inventé](../../media/ios/home-swiped.fr.webp)

## La bibliothèque
<!-- step tabs checked e3cd6df1:mobile/UITests/OortUITests.swift e3cd6df1:mobile/Sources/OortMobile/LibraryView.swift -->
Cherche en haut, trie par dernière partie ou par nom, et ajoute avec **+**.

![La bibliothèque avec des jeux inventés](../../media/ios/library.fr.webp)
