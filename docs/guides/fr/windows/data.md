---
title: Ce qu’Oort lit, écrit et envoie
system: windows
topic: data
order: 14
version: 0.1.0-alpha.2
minutes: 2
tried: Essayé sur une machine neuve de GitHub, avec des jeux inventés, un faux Steam et de faux services. Un joueur a lancé un jeu sur son PC avec l’alpha.1, pas encore avec celle-ci.
captures: settings-integrations, settings-about, setup-online
---

## Lit
<!-- step reads code f18e2119:desktop/README.md f18e2119:Sources/OortCompanion/SteamShelf.swift f18e2119:Sources/OortCompanion/ProgramFile.swift -->
Les dossiers et les programmes que tu ajoutes, dont le nom et l’icône dans leur fichier. Si Steam est activé : ses listes de jeux installés et ses images, jamais ton compte ni tes sauvegardes.

![Réglages › Intégrations](../../media/windows/settings-integrations.fr.webp)

## Écrit
<!-- step writes code f18e2119:Sources/OortCompanion/Store.swift f18e2119:Sources/OortCompanion/Places.swift -->
Son dossier `%LOCALAPPDATA%\io.github.sofianbll.oort-nx.desktop` et les fichiers de réglages qu’un jeu recompilé déclare. Rien chez Steam.

![Réglages › Informations](../../media/windows/settings-about.fr.webp)

## Envoie
<!-- step sends code f18e2119:desktop/README.md f18e2119:Sources/OortCompanion/Online.swift f18e2119:desktop/src-tauri/src/online.rs -->
Rien tant que les informations en ligne sont coupées. Activées : le nom du jeu ou son numéro Steam, et ta langue, au magasin Steam, à Wikidata et à Wikipédia, qui voient ton adresse internet. L’installateur peut demander WebView2 à Microsoft.

![La question de l’accueil guidé](../../media/windows/setup-online.fr.webp)
