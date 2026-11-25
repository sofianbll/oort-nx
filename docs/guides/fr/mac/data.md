---
title: Ce qu’Oort lit, écrit et envoie
system: mac
topic: data
order: 15
version: 0.5.0-beta.3
minutes: 3
tried: Vérifié par des contrôles automatiques avec des jeux inventés. Ni vrai jeu lancé, ni vrai transfert Drive, ni vraie manette avec cette version.
captures: settings-integrations, settings-storage, settings-about, settings-cloud
---

## Lit
<!-- step reads code bf0c3410:docs/how-it-works/steam.md bf0c3410:docs/how-it-works/architecture.md -->
Les dossiers que tu choisis. Si tu l’actives, les listes de jeux de Steam. Si tu compiles, tes fichiers et tes clés, sur ce Mac.

![Réglages › Intégrations](../../media/mac/settings-integrations.fr.webp)

## Écrit
<!-- step writes code bf0c3410:docs/how-it-works/architecture.md bf0c3410:Sources/NXLibraryCore/App/AppDataProfile.swift -->
`~/Library/Application Support/Oort NX`, les apps qu’il compile, et les réglages et mods des jeux compilés. Rien chez Steam. La copie de tes clés est lisible par toi seul.

![Réglages › Stockage](../../media/mac/settings-storage.fr.webp)

## Envoie, de lui-même
<!-- step alone code bf0c3410:Sources/NXLibraryCore/Resources/Localizable.xcstrings bf0c3410:docs/how-it-works/architecture.md -->
Il demande à GitHub s’il existe une version plus récente. Il cherche images, notes et descriptions avec le nom ou le numéro de tes jeux : Nlib, GameTDB, Steam, Wikidata, Wikipédia et d’autres sources publiques.

![Réglages › Informations](../../media/mac/settings-about.fr.webp)

## Envoie, si tu le demandes
<!-- step asked code bf0c3410:Sources/NXLibraryCore/Resources/Localizable.xcstrings bf0c3410:PLAYER-GUIDE.md -->
Google Drive, Nextendo, mods GameBanana, SteamGridDB, IGDB : seulement une fois activés, avec ton propre compte s’il en faut un. Compiler n’envoie ni fichier de jeu ni clé.

![Réglages › Bibliothèque cloud](../../media/mac/settings-cloud.fr.webp)
