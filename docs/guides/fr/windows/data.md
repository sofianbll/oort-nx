---
title: Ce qu’Oort lit, écrit et envoie
system: windows
topic: data
order: 13
version: 0.1.0-alpha.1
minutes: 2
tried: Essayé sur une machine neuve de GitHub avec des jeux inventés, et par un joueur sur son PC (un jeu lancé, le 25 novembre 2026).
captures: settings-integrations, settings-about, settings-about
---

## Lit
<!-- step reads code cc9db84a:desktop/README.md cc9db84a:Sources/OortCompanion/Companion.swift -->
Les dossiers et les programmes que tu ajoutes, et le `recomplauncher.json` de chaque jeu. D’une copie que tu choisis, il regarde le nom et l’emplacement.

![Réglages › Intégrations](../../media/windows/settings-integrations.fr.webp)

## Écrit
<!-- step writes code cc9db84a:Sources/OortCompanion/Store.swift cc9db84a:Sources/OortCompanion/Places.swift -->
Son dossier `%LOCALAPPDATA%\io.github.sofianbll.oort-nx.desktop` et les fichiers de réglages qu’un jeu recompilé déclare. Les derniers messages d’un jeu sont gardés dans ses journaux.

![Réglages › Informations](../../media/windows/settings-about.fr.webp)

## Envoie
<!-- step sends code cc9db84a:desktop/README.md cc9db84a:desktop/src-tauri/tauri.conf.json -->
Rien : pas de compte, pas de mesure, aucune donnée. Les liens vers les projets s’ouvrent dans ton navigateur, et l’installateur peut demander WebView2 à Microsoft.

![Réglages › Informations](../../media/windows/settings-about.fr.webp)
